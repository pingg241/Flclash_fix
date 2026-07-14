import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  group('CommonAction traffic polling', () {
    test('shares an in-flight request', () async {
      final response = Completer<TrafficSnapshot>();
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          trafficSnapshotLoaderProvider.overrideWithValue((_) {
            calls++;
            return response.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(commonActionProvider.notifier);

      final first = notifier.updateTraffic();
      final second = notifier.updateTraffic();

      expect(calls, 1);
      response.complete((
        now: const Traffic(up: 1, down: 2),
        total: const Traffic(up: 3, down: 4),
      ));
      await Future.wait([first, second]);

      expect(container.read(trafficsProvider).list.single.up, 1);
      expect(container.read(totalTrafficProvider).down, 4);
    });

    test('ignores a response invalidated by a new session', () async {
      final responses = <Completer<TrafficSnapshot>>[
        Completer<TrafficSnapshot>(),
        Completer<TrafficSnapshot>(),
      ];
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          trafficSnapshotLoaderProvider.overrideWithValue(
            (_) => responses[calls++].future,
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(commonActionProvider.notifier);

      final staleRequest = notifier.updateTraffic();
      notifier.invalidateTraffic();
      final currentRequest = notifier.updateTraffic();
      responses[1].complete((
        now: const Traffic(up: 20),
        total: const Traffic(up: 200),
      ));
      await currentRequest;
      responses[0].complete((
        now: const Traffic(up: 10),
        total: const Traffic(up: 100),
      ));
      await staleRequest;

      expect(calls, 2);
      expect(container.read(trafficsProvider).list.single.up, 20);
      expect(container.read(totalTrafficProvider).up, 200);
    });
  });

  group('ProfilesAction', () {
    test('keeps edited profile data when remote update fails', () async {
      final original = Profile.normal(label: 'old label', url: 'bad-url');
      final edited = original.copyWith(
        label: 'new label',
        url: 'still-bad-url',
      );
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(() => _TestProfiles([original])),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(profilesProvider).getProfile(original.id),
        original,
      );

      await expectLater(
        container
            .read(profilesActionProvider.notifier)
            .updateProfile(edited, replaceProfile: true),
        throwsA(anything),
      );

      final profile = container.read(profilesProvider).getProfile(original.id);
      expect(profile?.label, edited.label);
      expect(profile?.url, edited.url);
    });

    test('serializes updates and ignores an older profile response', () async {
      final firstResponse = Completer<Profile>();
      final secondResponse = Completer<Profile>();
      final original = Profile.normal(label: 'old', url: 'first-url');
      final replacement = original.copyWith(label: 'new', url: 'second-url');
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(() => _TestProfiles([original])),
          profileUpdaterProvider.overrideWithValue((
            profile,
            guard,
            commit,
          ) async {
            calls++;
            final result = await (profile.url == original.url
                ? firstResponse.future
                : secondResponse.future);
            if (!guard()) throw const ProfileUpdateCancelled();
            await commit(result);
            if (!guard()) throw const ProfileUpdateCancelled();
            return result;
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(profilesActionProvider.notifier);

      final first = notifier.updateProfile(original);
      final second = notifier.updateProfile(replacement, replaceProfile: true);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);

      firstResponse.complete(original.copyWith(label: 'stale'));
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      expect(container.read(profilesProvider).single.label, replacement.label);

      secondResponse.complete(replacement.copyWith(label: 'current'));
      await second;
      expect(container.read(profilesProvider).single.label, 'current');
      expect(container.read(profilesProvider).single.url, replacement.url);
    });

    test('does not restore a profile deleted during an update', () async {
      final response = Completer<Profile>();
      final profile = Profile.normal(label: 'old', url: 'remote-url');
      late bool Function() shouldSave;
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(() => _TestProfiles([profile])),
          profileUpdaterProvider.overrideWithValue((_, guard, _) {
            shouldSave = guard;
            return response.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(profilesActionProvider.notifier);

      final update = notifier.updateProfile(profile);
      notifier.invalidateProfileUpdate(profile.id);
      await container.read(profilesProvider.notifier).del(profile.id);
      expect(shouldSave(), false);
      response.complete(profile.copyWith(label: 'stale'));
      await update;

      expect(container.read(profilesProvider), isEmpty);
    });

    test(
      'accepts an equivalent profile instance from the database stream',
      () async {
        final response = Completer<Profile>();
        final profile = Profile.normal(label: 'old', url: 'remote-url');
        late bool Function() shouldSave;
        final testProfiles = _TestProfiles([profile]);
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => null),
            profilesProvider.overrideWith(() => testProfiles),
            profileUpdaterProvider.overrideWithValue((_, guard, commit) async {
              shouldSave = guard;
              final result = await response.future;
              if (!guard()) throw const ProfileUpdateCancelled();
              await commit(result);
              if (!guard()) throw const ProfileUpdateCancelled();
              return result;
            }),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(profilesActionProvider.notifier);

        final update = notifier.updateProfile(profile);
        await Future<void>.delayed(Duration.zero);
        final beforeStreamUpdate = container.read(profilesProvider).single;
        testProfiles.replaceWithEquivalent(profile.id);
        final afterStreamUpdate = container.read(profilesProvider).single;
        expect(afterStreamUpdate, beforeStreamUpdate);
        expect(identical(afterStreamUpdate, beforeStreamUpdate), false);
        expect(shouldSave(), true);

        response.complete(profile.copyWith(label: 'updated'));
        await update;

        expect(container.read(profilesProvider).single.label, 'updated');
      },
    );

    test(
      'queued refresh reads the latest profile instead of its snapshot',
      () async {
        final firstResponse = Completer<Profile>();
        final secondResponse = Completer<Profile>();
        final original = Profile.normal(label: 'old', url: 'old-url');
        final edited = original.copyWith(label: 'edited', url: 'new-url');
        final seen = <Profile>[];
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => null),
            profilesProvider.overrideWith(() => _TestProfiles([original])),
            profileUpdaterProvider.overrideWithValue((
              profile,
              guard,
              commit,
            ) async {
              seen.add(profile);
              final response = seen.length == 1
                  ? await firstResponse.future
                  : await secondResponse.future;
              if (!guard()) throw const ProfileUpdateCancelled();
              await commit(response);
              if (!guard()) throw const ProfileUpdateCancelled();
              return response;
            }),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(profilesActionProvider.notifier);

        final first = notifier.updateProfile(original);
        final queued = notifier.updateProfile(original);
        await container.read(profilesProvider.notifier).put(edited);
        firstResponse.complete(original.copyWith(label: 'stale'));
        await first;
        await Future<void>.delayed(Duration.zero);

        expect(seen, hasLength(2));
        expect(seen.last.url, edited.url);
        expect(seen.last.label, edited.label);
        secondResponse.complete(
          edited.copyWith(subscriptionInfo: const SubscriptionInfo(total: 10)),
        );
        await queued;
        expect(container.read(profilesProvider).single.url, edited.url);
      },
    );

    test('cancels when the profile changes after validation', () async {
      final validated = Completer<void>();
      final continueAfterEdit = Completer<void>();
      var committed = false;
      final profile = Profile.normal(label: 'old', url: 'old-url');
      final edited = profile.copyWith(url: 'new-url');
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(() => _TestProfiles([profile])),
          profileUpdaterProvider.overrideWithValue((
            source,
            guard,
            commit,
          ) async {
            validated.complete();
            await continueAfterEdit.future;
            if (!guard()) throw const ProfileUpdateCancelled();
            committed = true;
            final result = source.copyWith(label: 'remote');
            await commit(result);
            return result;
          }),
        ],
      );
      addTearDown(container.dispose);

      final update = container
          .read(profilesActionProvider.notifier)
          .updateProfile(profile);
      await validated.future;
      await container.read(profilesProvider.notifier).put(edited);
      continueAfterEdit.complete();
      await update;

      expect(committed, false);
      expect(container.read(profilesProvider).single.url, edited.url);
    });

    test('rejects commit when the profile changes after rename', () async {
      final renamed = Completer<void>();
      final continueToCommit = Completer<void>();
      final profile = Profile.normal(label: 'old', url: 'old-url');
      final edited = profile.copyWith(url: 'new-url');
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(() => _TestProfiles([profile])),
          profileUpdaterProvider.overrideWithValue((
            source,
            guard,
            commit,
          ) async {
            expect(guard(), true);
            renamed.complete();
            await continueToCommit.future;
            final result = source.copyWith(label: 'remote');
            await commit(result);
            return result;
          }),
        ],
      );
      addTearDown(container.dispose);

      final update = container
          .read(profilesActionProvider.notifier)
          .updateProfile(profile);
      await renamed.future;
      await container.read(profilesProvider.notifier).put(edited);
      continueToCommit.complete();
      await update;

      expect(container.read(profilesProvider).single.url, edited.url);
      expect(container.read(profilesProvider).single.label, edited.label);
    });

    test('awaits stop, database deletion, and cleanup in order', () async {
      final events = <String>[];
      final profile = Profile.normal(label: 'only');
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          profilesProvider.overrideWith(
            () => _TestProfiles([
              profile,
            ], onDelete: (_) async => events.add('delete')),
          ),
          profileStatusUpdaterProvider.overrideWithValue((_) async {
            events.add('stop');
            return true;
          }),
          profileEffectCleanerProvider.overrideWithValue((_) async {
            events.add('clean');
          }),
          profileFileCleanerProvider.overrideWithValue((_) async {
            events.add('file');
          }),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(profilesActionProvider.notifier)
          .deleteProfile(profile.id);

      expect(events, ['stop', 'clean', 'delete', 'file']);
      expect(container.read(profilesProvider), isEmpty);
      expect(container.read(currentProfileIdProvider), isNull);
    });

    test('propagates database deletion failure and skips cleanup', () async {
      final events = <String>[];
      final profile = Profile.normal(label: 'only');
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          profilesProvider.overrideWith(
            () => _TestProfiles(
              [profile],
              onDelete: (_) async {
                events.add('delete');
                throw StateError('database failure');
              },
            ),
          ),
          profileStatusUpdaterProvider.overrideWithValue((_) async {
            events.add('stop');
            return true;
          }),
          profileEffectCleanerProvider.overrideWithValue((_) async {
            events.add('clean');
          }),
          profileFileCleanerProvider.overrideWithValue((_) async {
            events.add('file');
          }),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(profilesActionProvider.notifier)
            .deleteProfile(profile.id),
        throwsStateError,
      );

      expect(events, ['stop', 'clean', 'delete']);
      expect(container.read(currentProfileIdProvider), profile.id);
    });

    test(
      'provider cache failure keeps profile state and skips deletion',
      () async {
        final events = <String>[];
        final profile = Profile.normal(label: 'only');
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            profilesProvider.overrideWith(
              () => _TestProfiles(
                [profile],
                onDelete: (_) async {
                  events.add('delete');
                },
              ),
            ),
            profileStatusUpdaterProvider.overrideWithValue((_) async {
              events.add('stop');
              return true;
            }),
            profileEffectCleanerProvider.overrideWithValue((_) async {
              events.add('cache');
              throw const FileSystemException('cache cleanup failed');
            }),
            profileFileCleanerProvider.overrideWithValue((_) async {
              events.add('file');
            }),
          ],
        );
        addTearDown(container.dispose);

        await expectLater(
          container
              .read(profilesActionProvider.notifier)
              .deleteProfile(profile.id),
          throwsA(isA<FileSystemException>()),
        );

        expect(events, ['stop', 'cache']);
        expect(container.read(profilesProvider), [profile]);
        expect(container.read(currentProfileIdProvider), profile.id);
      },
    );

    test(
      'profile file cleanup failure is reported and can be retried',
      () async {
        final events = <String>[];
        final profile = Profile.normal(label: 'only');
        var fileAttempts = 0;
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            profilesProvider.overrideWith(
              () => _TestProfiles(
                [profile],
                onDelete: (_) async {
                  events.add('delete');
                },
              ),
            ),
            profileStatusUpdaterProvider.overrideWithValue((_) async {
              events.add('stop');
              return true;
            }),
            profileEffectCleanerProvider.overrideWithValue((_) async {
              events.add('cache');
            }),
            profileFileCleanerProvider.overrideWithValue((_) async {
              fileAttempts++;
              events.add('file-$fileAttempts');
              if (fileAttempts == 1) {
                throw const FileSystemException('profile cleanup failed');
              }
            }),
          ],
        );
        addTearDown(container.dispose);

        await expectLater(
          container
              .read(profilesActionProvider.notifier)
              .deleteProfile(profile.id),
          throwsA(isA<FileSystemException>()),
        );
        expect(container.read(profilesProvider), isEmpty);
        expect(container.read(currentProfileIdProvider), isNull);

        await container
            .read(profilesActionProvider.notifier)
            .deleteProfile(profile.id);

        expect(events, [
          'stop',
          'cache',
          'delete',
          'file-1',
          'cache',
          'delete',
          'file-2',
        ]);
      },
    );
  });

  group('ProxiesAction provider updates', () {
    test('shares an in-flight update for the same provider', () async {
      final updateResponse = Completer<String>();
      var updateCalls = 0;
      var loadCalls = 0;
      final provider = ExternalProvider(
        name: 'remote',
        type: 'Proxy',
        count: 1,
        vehicleType: 'HTTP',
        updateAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final updated = provider.copyWith(count: 2);
      final container = ProviderContainer(
        overrides: [
          providersProvider.overrideWith(() => _TestProviders([provider])),
          externalProviderUpdaterProvider.overrideWithValue((_) {
            updateCalls++;
            return updateResponse.future;
          }),
          externalProviderLoaderProvider.overrideWithValue((_) async {
            loadCalls++;
            return updated;
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(proxiesActionProvider.notifier);

      final first = notifier.updateProvider(provider);
      final second = notifier.updateProvider(provider);
      expect(updateCalls, 1);
      updateResponse.complete('');
      await Future.wait([first, second]);

      expect(loadCalls, 1);
      expect(container.read(providersProvider).single.count, 2);
    });

    test(
      'proxy changes in different groups do not cancel each other',
      () async {
        final profile = Profile.normal(
          label: 'profile',
        ).copyWith(selectedMap: {'group-a': 'old-a', 'group-b': 'old-b'});
        final calls = <(String, String)>[];
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            profilesProvider.overrideWith(() => _TestProfiles([profile])),
            proxyChangeExecutorProvider.overrideWithValue((group, proxy) async {
              calls.add((group, proxy));
              return '';
            }),
            proxyConnectionRefresherProvider.overrideWithValue(() async {}),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(proxiesActionProvider.notifier);

        await Future.wait([
          notifier.changeProxyDebounce(
            'group-a',
            'new-a',
            duration: Duration.zero,
          ),
          notifier.changeProxyDebounce(
            'group-b',
            'new-b',
            duration: Duration.zero,
          ),
        ]);

        expect(
          calls,
          containsAll([('group-a', 'new-a'), ('group-b', 'new-b')]),
        );
        final selected = container.read(profilesProvider).single.selectedMap;
        expect(selected['group-a'], 'new-a');
        expect(selected['group-b'], 'new-b');
      },
    );

    test(
      'core proxy rejection leaves the persisted selection unchanged',
      () async {
        final profile = Profile.normal(
          label: 'profile',
        ).copyWith(selectedMap: {'group': 'old'});
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            profilesProvider.overrideWith(() => _TestProfiles([profile])),
            proxyChangeExecutorProvider.overrideWithValue(
              (_, _) async => 'group rejected the proxy',
            ),
            proxyConnectionRefresherProvider.overrideWithValue(() async {}),
          ],
        );
        addTearDown(container.dispose);

        await expectLater(
          container
              .read(proxiesActionProvider.notifier)
              .changeProxyDebounce('group', 'new', duration: Duration.zero),
          throwsStateError,
        );

        expect(
          container.read(profilesProvider).single.selectedMap['group'],
          'old',
        );
      },
    );

    test('connection close failure propagates from proxy action', () async {
      final container = ProviderContainer(
        overrides: [
          proxyChangeExecutorProvider.overrideWithValue((_, _) async => ''),
          proxyConnectionRefresherProvider.overrideWithValue(
            () async => throw StateError('core rejected connection close'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(proxiesActionProvider.notifier)
            .changeProxy(groupName: 'group', proxyName: 'proxy'),
        throwsStateError,
      );
    });

    test('rapid same-group changes execute only the latest intent', () async {
      final profile = Profile.normal(
        label: 'profile',
      ).copyWith(selectedMap: {'group': 'old'});
      final calls = <String>[];
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          profilesProvider.overrideWith(() => _TestProfiles([profile])),
          proxyChangeExecutorProvider.overrideWithValue((_, proxy) async {
            calls.add(proxy);
            return '';
          }),
          proxyConnectionRefresherProvider.overrideWithValue(() async {}),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(proxiesActionProvider.notifier);

      final first = notifier.changeProxyDebounce(
        'group',
        'first',
        duration: const Duration(milliseconds: 10),
      );
      final second = notifier.changeProxyDebounce(
        'group',
        'second',
        duration: const Duration(milliseconds: 10),
      );
      await Future.wait([first, second]);

      expect(calls, ['second']);
      expect(
        container.read(profilesProvider).single.selectedMap['group'],
        'second',
      );
    });

    test(
      'a stale same-group completion cannot overwrite the latest intent',
      () async {
        final profile = Profile.normal(
          label: 'profile',
        ).copyWith(selectedMap: {'group': 'old'});
        final firstStarted = Completer<void>();
        final releaseFirst = Completer<void>();
        final secondStarted = Completer<void>();
        final releaseSecond = Completer<void>();
        final calls = <String>[];
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            profilesProvider.overrideWith(() => _TestProfiles([profile])),
            proxyChangeExecutorProvider.overrideWithValue((_, proxy) async {
              calls.add(proxy);
              if (proxy == 'first') {
                firstStarted.complete();
                await releaseFirst.future;
              } else {
                secondStarted.complete();
                await releaseSecond.future;
              }
              return '';
            }),
            proxyConnectionRefresherProvider.overrideWithValue(() async {}),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(proxiesActionProvider.notifier);

        final first = notifier.changeProxyDebounce(
          'group',
          'first',
          duration: Duration.zero,
        );
        await firstStarted.future;
        final second = notifier.changeProxyDebounce(
          'group',
          'second',
          duration: Duration.zero,
        );
        await Future<void>.delayed(Duration.zero);
        releaseFirst.complete();
        await secondStarted.future;

        expect(
          container.read(profilesProvider).single.selectedMap['group'],
          'old',
        );
        releaseSecond.complete();
        await Future.wait([first, second]);

        expect(calls, ['first', 'second']);
        expect(
          container.read(profilesProvider).single.selectedMap['group'],
          'second',
        );
      },
    );
  });

  group('GeoResourceAction', () {
    test('GeoResource has correct updatingKey', () {
      expect(GeoResource.MMDB.updatingKey, 'geo_resource_MMDB');
      expect(GeoResource.ASN.updatingKey, 'geo_resource_ASN');
      expect(GeoResource.GEOIP.updatingKey, 'geo_resource_GEOIP');
      expect(GeoResource.GEOSITE.updatingKey, 'geo_resource_GEOSITE');
    });

    test('IsUpdating provider works with geo resource key', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final key = GeoResource.MMDB.updatingKey;
      expect(container.read(isUpdatingProvider(key)), false);

      container.read(isUpdatingProvider(key).notifier).value = true;
      expect(container.read(isUpdatingProvider(key)), true);

      container.read(isUpdatingProvider(key).notifier).value = false;
      expect(container.read(isUpdatingProvider(key)), false);
    });
  });
}

class _TestProfiles extends Profiles {
  final List<Profile> initial;
  final Future<void> Function(int id)? onDelete;

  _TestProfiles(this.initial, {this.onDelete});

  @override
  List<Profile> build() => initial;

  @override
  Future<void> put(Profile profile) async {
    final next = List<Profile>.from(state);
    final index = next.indexWhere((item) => item.id == profile.id);
    if (index == -1) {
      next.add(profile);
    } else {
      next[index] = profile;
    }
    state = next;
  }

  @override
  Future<void> del(int id) async {
    await onDelete?.call(id);
    state = state.where((profile) => profile.id != id).toList();
  }

  void replaceWithEquivalent(int id) {
    state = state
        .map(
          (profile) => profile.id == id
              ? Profile.fromJson(
                  jsonDecode(jsonEncode(profile.toJson()))
                      as Map<String, Object?>,
                )
              : profile,
        )
        .toList();
  }
}

class _TestProviders extends Providers {
  final List<ExternalProvider> initial;

  _TestProviders(this.initial);

  @override
  List<ExternalProvider> build() => initial;
}
