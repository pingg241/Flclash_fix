import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  group('TrafficRateSampler', () {
    test('uses the core rate while establishing the first baseline', () {
      final sampler = TrafficRateSampler();

      final traffic = sampler.sample(
        fallback: const Traffic(up: 7, down: 9),
        total: const Traffic(up: 100, down: 200),
        elapsed: Duration.zero,
        session: 1,
      );

      expect(traffic, const Traffic(up: 7, down: 9));
    });

    test('derives rates from adjacent totals', () {
      final sampler = TrafficRateSampler();
      sampler.sample(
        fallback: const Traffic(),
        total: const Traffic(up: 100, down: 200),
        elapsed: Duration.zero,
        session: 1,
      );

      final traffic = sampler.sample(
        fallback: const Traffic(),
        total: const Traffic(up: 1124, down: 2248),
        elapsed: const Duration(seconds: 1),
        session: 1,
      );

      expect(traffic, const Traffic(up: 1024, down: 2048));
    });

    test('returns zero when totals do not change', () {
      final sampler = TrafficRateSampler();
      sampler.sample(
        fallback: const Traffic(up: 10, down: 20),
        total: const Traffic(up: 100, down: 200),
        elapsed: Duration.zero,
        session: 1,
      );

      final traffic = sampler.sample(
        fallback: const Traffic(up: 10, down: 20),
        total: const Traffic(up: 100, down: 200),
        elapsed: const Duration(seconds: 1),
        session: 1,
      );

      expect(traffic, const Traffic());
    });

    test('uses monotonic elapsed time across timer jitter', () {
      final sampler = TrafficRateSampler();
      sampler.sample(
        fallback: const Traffic(),
        total: const Traffic(up: 100, down: 200),
        elapsed: Duration.zero,
        session: 1,
      );

      final traffic = sampler.sample(
        fallback: const Traffic(),
        total: const Traffic(up: 850, down: 1700),
        elapsed: const Duration(milliseconds: 1500),
        session: 1,
      );

      expect(traffic, const Traffic(up: 500, down: 1000));
    });

    test('rebases when a total counter resets', () {
      final sampler = TrafficRateSampler();
      sampler.sample(
        fallback: const Traffic(),
        total: const Traffic(up: 1000, down: 2000),
        elapsed: Duration.zero,
        session: 1,
      );

      final reset = sampler.sample(
        fallback: const Traffic(up: 3, down: 4),
        total: const Traffic(up: 10, down: 20),
        elapsed: const Duration(seconds: 1),
        session: 1,
      );
      final afterReset = sampler.sample(
        fallback: const Traffic(),
        total: const Traffic(up: 110, down: 220),
        elapsed: const Duration(seconds: 2),
        session: 1,
      );

      expect(reset, const Traffic(up: 3, down: 4));
      expect(afterReset, const Traffic(up: 100, down: 200));
    });

    test('does not carry a baseline into a new session', () {
      final sampler = TrafficRateSampler();
      sampler.sample(
        fallback: const Traffic(),
        total: const Traffic(up: 100, down: 200),
        elapsed: Duration.zero,
        session: 1,
      );

      final traffic = sampler.sample(
        fallback: const Traffic(up: 5, down: 6),
        total: const Traffic(up: 300, down: 400),
        elapsed: const Duration(seconds: 1),
        session: 2,
      );

      expect(traffic, const Traffic(up: 5, down: 6));
    });

    test('falls back when the sample interval is too short', () {
      final sampler = TrafficRateSampler();
      sampler.sample(
        fallback: const Traffic(),
        total: const Traffic(up: 100, down: 200),
        elapsed: Duration.zero,
        session: 1,
      );

      final traffic = sampler.sample(
        fallback: const Traffic(up: 7, down: 8),
        total: const Traffic(up: 200, down: 300),
        elapsed:
            TrafficRateSampler.minimumSampleInterval -
            const Duration(microseconds: 1),
        session: 1,
      );

      expect(traffic, const Traffic(up: 7, down: 8));
    });

    test('falls back when the sample interval is too long', () {
      final sampler = TrafficRateSampler();
      sampler.sample(
        fallback: const Traffic(),
        total: const Traffic(up: 100, down: 200),
        elapsed: Duration.zero,
        session: 1,
      );

      final traffic = sampler.sample(
        fallback: const Traffic(up: 7, down: 8),
        total: const Traffic(up: 2100, down: 4200),
        elapsed:
            TrafficRateSampler.maximumSampleInterval +
            const Duration(microseconds: 1),
        session: 1,
      );

      expect(traffic, const Traffic(up: 7, down: 8));
    });

    test('rebases after an out-of-window sample', () {
      final sampler = TrafficRateSampler();
      sampler.sample(
        fallback: const Traffic(),
        total: const Traffic(up: 100, down: 200),
        elapsed: Duration.zero,
        session: 1,
      );
      sampler.sample(
        fallback: const Traffic(),
        total: const Traffic(up: 2100, down: 4200),
        elapsed:
            TrafficRateSampler.maximumSampleInterval +
            const Duration(microseconds: 1),
        session: 1,
      );

      final traffic = sampler.sample(
        fallback: const Traffic(),
        total: const Traffic(up: 2612, down: 5224),
        elapsed:
            TrafficRateSampler.maximumSampleInterval +
            const Duration(seconds: 1, microseconds: 1),
        session: 1,
      );

      expect(traffic, const Traffic(up: 512, down: 1024));
    });

    test('falls back when an extreme delta cannot produce a finite rate', () {
      final sampler = TrafficRateSampler();
      sampler.sample(
        fallback: const Traffic(),
        total: const Traffic(),
        elapsed: Duration.zero,
        session: 1,
      );

      final traffic = sampler.sample(
        fallback: const Traffic(up: 7, down: 8),
        total: const Traffic(up: double.maxFinite, down: double.maxFinite),
        elapsed: TrafficRateSampler.minimumSampleInterval,
        session: 1,
      );

      expect(traffic, const Traffic(up: 7, down: 8));
    });
  });

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

    test('invalidates a pending sample when the core disconnects', () async {
      final response = Completer<TrafficSnapshot>();
      final container = ProviderContainer(
        overrides: [
          trafficSnapshotLoaderProvider.overrideWithValue(
            (_) => response.future,
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(coreStatusProvider.notifier).value = CoreStatus.connected;
      final notifier = container.read(commonActionProvider.notifier);

      final staleRequest = notifier.updateTraffic();
      container.read(coreStatusProvider.notifier).value =
          CoreStatus.disconnected;
      response.complete((
        now: const Traffic(up: 10),
        total: const Traffic(up: 100),
      ));
      await staleRequest;

      expect(container.read(trafficsProvider).list, isEmpty);
      expect(container.read(totalTrafficProvider), const Traffic());
    });

    test(
      'invalidates a pending sample when the statistic scope changes',
      () async {
        final response = Completer<TrafficSnapshot>();
        final container = ProviderContainer(
          overrides: [
            trafficSnapshotLoaderProvider.overrideWithValue(
              (_) => response.future,
            ),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(commonActionProvider.notifier);

        final staleRequest = notifier.updateTraffic();
        container
            .read(appSettingProvider.notifier)
            .update(
              (state) => state.copyWith(
                onlyStatisticsProxy: !state.onlyStatisticsProxy,
              ),
            );
        response.complete((
          now: const Traffic(up: 10),
          total: const Traffic(up: 100),
        ));
        await staleRequest;

        expect(container.read(trafficsProvider).list, isEmpty);
        expect(container.read(totalTrafficProvider), const Traffic());
      },
    );
  });

  group('ProfilesAction', () {
    test('explicit profile selection waits for the apply operation', () async {
      final first = Profile.normal(label: 'first');
      final second = Profile.normal(label: 'second');
      final applyStarted = Completer<void>();
      final releaseApply = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => first.id),
          profilesProvider.overrideWith(() => _TestProfiles([first, second])),
          profileSwitchApplierProvider.overrideWithValue(() async {
            applyStarted.complete();
            await releaseApply.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(profilesActionProvider.notifier);

      var completed = false;
      final selection = notifier.selectProfile(second.id).then((value) {
        completed = true;
        return value;
      });
      await applyStarted.future;

      expect(container.read(currentProfileIdProvider), second.id);
      expect(completed, isFalse);
      releaseApply.complete();
      expect(await selection, isTrue);
    });

    test(
      'clearing an externally selected running profile stops first',
      () async {
        final profile = Profile.normal(label: 'current');
        var stopCalls = 0;
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            profilesProvider.overrideWith(() => _TestProfiles([profile])),
            isStartProvider.overrideWithValue(true),
            profileSwitchClearerProvider.overrideWithValue(() async {
              stopCalls++;
              return true;
            }),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(profilesActionProvider.notifier);
        container.read(currentProfileIdProvider.notifier).value = null;

        expect(await notifier.applyExternalProfileSelection(null), isTrue);
        expect(stopCalls, 1);
        expect(container.read(currentProfileIdProvider), isNull);
      },
    );

    test('failed external clear restores the applied profile', () async {
      final profile = Profile.normal(label: 'current');
      var stopCalls = 0;
      var applyCalls = 0;
      var persistCalls = 0;
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          profilesProvider.overrideWith(() => _TestProfiles([profile])),
          isStartProvider.overrideWithValue(true),
          profileSwitchClearerProvider.overrideWithValue(() async {
            stopCalls++;
            return false;
          }),
          profileSwitchApplierProvider.overrideWithValue(() async {
            applyCalls++;
          }),
          profileSwitchPersisterProvider.overrideWithValue(() async {
            persistCalls++;
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(profilesActionProvider.notifier);
      container.read(currentProfileIdProvider.notifier).value = null;

      await expectLater(
        notifier.applyExternalProfileSelection(null),
        throwsA(isA<ProfileSwitchException>()),
      );

      expect(stopCalls, 1);
      expect(applyCalls, 0);
      expect(persistCalls, 1);
      expect(container.read(currentProfileIdProvider), profile.id);
      expect(await notifier.selectProfile(profile.id), isTrue);
      expect(applyCalls, 0);
    });

    test('failed first profile activation removes the new profile', () async {
      final events = <String>[];
      final profile = Profile.normal(label: 'new');
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(
            () => _TestProfiles(
              [],
              onDelete: (_) async => events.add('metadata'),
            ),
          ),
          profileSwitchApplierProvider.overrideWithValue(() async {
            events.add('apply');
            throw StateError('setup failed');
          }),
          profileSwitchPersisterProvider.overrideWithValue(() async {
            events.add('persist-rollback');
          }),
          profileEffectCleanerProvider.overrideWithValue((_) async {
            events.add('cache');
          }),
          profileFileCleanerProvider.overrideWithValue((_) async {
            events.add('file');
          }),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(profilesActionProvider.notifier).addProfile(profile),
        throwsA(isA<ProfileSwitchException>()),
      );

      expect(events, [
        'apply',
        'persist-rollback',
        'metadata',
        'cache',
        'file',
      ]);
      expect(container.read(profilesProvider), isEmpty);
      expect(container.read(currentProfileIdProvider), isNull);
    });

    test('failed metadata rollback preserves the new profile files', () async {
      final events = <String>[];
      final profile = Profile.normal(label: 'new');
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(
            () => _TestProfiles(
              [],
              onDelete: (_) async {
                events.add('metadata');
                throw StateError('database rollback failed');
              },
            ),
          ),
          profileSwitchApplierProvider.overrideWithValue(() async {
            events.add('apply');
            throw StateError('setup failed');
          }),
          profileSwitchPersisterProvider.overrideWithValue(() async {
            events.add('persist-rollback');
          }),
          profileEffectCleanerProvider.overrideWithValue((_) async {
            events.add('cache');
          }),
          profileFileCleanerProvider.overrideWithValue((_) async {
            events.add('file');
          }),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(profilesActionProvider.notifier).addProfile(profile),
        throwsA(
          isA<ProfileOperationException>().having(
            (error) => error.rollbackErrors.join(' '),
            'rollback errors',
            contains('database rollback failed'),
          ),
        ),
      );

      expect(events, ['apply', 'persist-rollback', 'metadata']);
      expect(container.read(profilesProvider), [profile]);
      expect(container.read(currentProfileIdProvider), isNull);
    });

    test(
      'deleting the current profile applies its replacement first',
      () async {
        final events = <String>[];
        final first = Profile.normal(label: 'first');
        final second = Profile.normal(label: 'second');
        late ProviderContainer container;
        container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => first.id),
            profilesProvider.overrideWith(
              () => _TestProfiles([
                first,
                second,
              ], onDelete: (_) async => events.add('delete')),
            ),
            profileSwitchApplierProvider.overrideWithValue(() async {
              events.add('apply-${container.read(currentProfileIdProvider)}');
            }),
            profileEffectCleanerProvider.overrideWithValue((_) async {
              events.add('cache');
            }),
            profileFileCleanerProvider.overrideWithValue((_) async {
              events.add('file');
            }),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(profilesActionProvider.notifier)
            .deleteProfile(first.id);

        expect(events, ['apply-${second.id}', 'delete', 'cache', 'file']);
        expect(container.read(currentProfileIdProvider), second.id);
        expect(container.read(profilesProvider), [second]);
      },
    );

    test(
      'deleting the last stopped profile does not apply empty config',
      () async {
        final profile = Profile.normal(label: 'only');
        var applyCalls = 0;
        late ProviderContainer container;
        container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            profilesProvider.overrideWith(() => _TestProfiles([profile])),
            isStartProvider.overrideWithValue(false),
            profileSwitchApplierProvider.overrideWithValue(() async {
              applyCalls++;
            }),
            profileEffectCleanerProvider.overrideWithValue((_) async {}),
            profileFileCleanerProvider.overrideWithValue((_) async {}),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(profilesActionProvider.notifier)
            .deleteProfile(profile.id);

        expect(applyCalls, 0);
        expect(container.read(currentProfileIdProvider), isNull);
        expect(container.read(profilesProvider), isEmpty);
      },
    );

    test('keeps original profile data when edited URL update fails', () async {
      final original = Profile.normal(label: 'old label', url: 'bad-url');
      final edited = original.copyWith(
        label: 'new label',
        url: 'still-bad-url',
      );
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(() => _TestProfiles([original])),
          profileUpdaterProvider.overrideWithValue((profile, _, _) async {
            expect(profile, edited);
            throw StateError('download failed');
          }),
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
      expect(profile, original);
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
      expect(container.read(profilesProvider).single, original);

      firstResponse.complete(original.copyWith(label: 'stale'));
      expect(await first, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      expect(container.read(profilesProvider).single, original);

      secondResponse.complete(replacement.copyWith(label: 'current'));
      expect(await second, isTrue);
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
      'waits for a canceled replace update to settle before deletion',
      () async {
        final updateStarted = Completer<void>();
        final releaseUpdate = Completer<void>();
        final events = <String>[];
        final profile = Profile.normal(label: 'old', url: 'remote-url');
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => null),
            profilesProvider.overrideWith(
              () => _TestProfiles([
                profile,
              ], onDelete: (_) async => events.add('delete')),
            ),
            profileUpdaterProvider.overrideWithValue((_, guard, _) async {
              updateStarted.complete();
              await releaseUpdate.future;
              expect(guard(), isFalse);
              events.add('update-settled');
              throw const ProfileUpdateCancelled();
            }),
            profileEffectCleanerProvider.overrideWithValue((_) async {
              events.add('cache');
            }),
            profileFileCleanerProvider.overrideWithValue((_) async {
              events.add('file');
            }),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(profilesActionProvider.notifier);

        final update = notifier.updateProfile(
          profile.copyWith(url: 'replacement-url'),
          replaceProfile: true,
        );
        await updateStarted.future;
        final deletion = notifier.deleteProfile(profile.id);
        await Future<void>.delayed(Duration.zero);

        expect(events, isEmpty);
        expect(container.read(profilesProvider), [profile]);

        releaseUpdate.complete();
        expect(await update, isFalse);
        await deletion;

        expect(events, ['update-settled', 'delete', 'cache', 'file']);
        expect(container.read(profilesProvider), isEmpty);
      },
    );

    test('a queued deletion does not block switching to its profile', () async {
      final updateStarted = Completer<void>();
      final releaseUpdate = Completer<void>();
      final events = <String>[];
      final first = Profile.normal(label: 'first', url: 'remote');
      final second = Profile.normal(label: 'second');
      late ProviderContainer container;
      container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => first.id),
          profilesProvider.overrideWith(
            () => _TestProfiles([
              first,
              second,
            ], onDelete: (id) async => events.add('delete-$id')),
          ),
          profileUpdaterProvider.overrideWithValue((_, guard, _) async {
            updateStarted.complete();
            await releaseUpdate.future;
            expect(guard(), isFalse);
            events.add('update');
            throw const ProfileUpdateCancelled();
          }),
          profileSwitchApplierProvider.overrideWithValue(() async {
            events.add('apply-${container.read(currentProfileIdProvider)}');
          }),
          isStartProvider.overrideWithValue(false),
          profileEffectCleanerProvider.overrideWithValue((id) async {
            events.add('cache-$id');
          }),
          profileFileCleanerProvider.overrideWithValue((id) async {
            events.add('file-$id');
          }),
        ],
      );
      addTearDown(container.dispose);
      final currentProfileSubscription = container.listen(
        currentProfileIdProvider,
        (_, _) {},
      );
      addTearDown(currentProfileSubscription.close);
      final notifier = container.read(profilesActionProvider.notifier);

      final update = notifier.updateProfile(first);
      await updateStarted.future;
      final deleteFirst = notifier.deleteProfile(first.id);
      final deleteSecond = notifier.deleteProfile(second.id);
      releaseUpdate.complete();

      expect(await update, isFalse);
      await Future.wait([deleteFirst, deleteSecond]);

      expect(events, [
        'update',
        'apply-${second.id}',
        'delete-${first.id}',
        'cache-${first.id}',
        'file-${first.id}',
        'delete-${second.id}',
        'cache-${second.id}',
        'file-${second.id}',
      ]);
      expect(container.read(profilesProvider), isEmpty);
      expect(container.read(currentProfileIdProvider), isNull);
    });

    test('rejects self-deletion from an active profile update', () async {
      final profile = Profile.normal(label: 'old', url: 'remote-url');
      late ProfilesAction notifier;
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(() => _TestProfiles([profile])),
          profileUpdaterProvider.overrideWithValue((source, _, _) async {
            await expectLater(
              notifier.deleteProfile(source.id),
              throwsStateError,
            );
            return source;
          }),
        ],
      );
      addTearDown(container.dispose);
      notifier = container.read(profilesActionProvider.notifier);

      expect(await notifier.updateProfile(profile), isTrue);
      expect(container.read(profilesProvider), [profile]);
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
          isStartProvider.overrideWithValue(true),
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

      expect(events, ['stop', 'delete', 'clean', 'file']);
      expect(container.read(profilesProvider), isEmpty);
      expect(container.read(currentProfileIdProvider), isNull);
    });

    test('deletes the last stopped profile without stopping again', () async {
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
          isStartProvider.overrideWithValue(false),
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

      expect(events, ['delete', 'clean', 'file']);
      expect(container.read(profilesProvider), isEmpty);
      expect(container.read(currentProfileIdProvider), isNull);
    });

    test('stops a pending start before deleting the last profile', () async {
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
          isStartProvider.overrideWithValue(false),
          isStartingProvider.overrideWithValue(true),
          profileStatusUpdaterProvider.overrideWithValue((wantStart) async {
            expect(wantStart, isFalse);
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

      expect(events, ['stop', 'delete', 'clean', 'file']);
      expect(container.read(profilesProvider), isEmpty);
      expect(container.read(currentProfileIdProvider), isNull);
    });

    test('shares an in-flight deletion for the same profile', () async {
      final deleteStarted = Completer<void>();
      final releaseDelete = Completer<void>();
      final events = <String>[];
      final profile = Profile.normal(label: 'only');
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(
            () => _TestProfiles(
              [profile],
              onDelete: (_) async {
                events.add('delete');
                deleteStarted.complete();
                await releaseDelete.future;
              },
            ),
          ),
          profileEffectCleanerProvider.overrideWithValue((_) async {
            events.add('cache');
          }),
          profileFileCleanerProvider.overrideWithValue((_) async {
            events.add('file');
          }),
          profileUpdaterProvider.overrideWithValue((_, _, _) async {
            throw StateError('update must not start during deletion');
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(profilesActionProvider.notifier);

      final first = notifier.deleteProfile(profile.id);
      await deleteStarted.future;
      final second = notifier.deleteProfile(profile.id);
      expect(await notifier.updateProfile(profile), isFalse);
      releaseDelete.complete();
      await Future.wait([first, second]);

      expect(events, ['delete', 'cache', 'file']);
      expect(container.read(profilesProvider), isEmpty);
    });

    test(
      'serializes different deletions before checking the last profile',
      () async {
        final firstDeleteStarted = Completer<void>();
        final releaseFirstDelete = Completer<void>();
        final events = <String>[];
        final firstProfile = Profile.normal(label: 'first');
        final secondProfile = Profile.normal(label: 'second');
        late ProviderContainer container;
        container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild(
              (_, _) => firstProfile.id,
            ),
            profilesProvider.overrideWith(
              () => _TestProfiles(
                [firstProfile, secondProfile],
                onDelete: (id) async {
                  events.add('delete-$id');
                  if (id == firstProfile.id) {
                    firstDeleteStarted.complete();
                    await releaseFirstDelete.future;
                  }
                },
              ),
            ),
            isStartProvider.overrideWithValue(true),
            profileSwitchApplierProvider.overrideWithValue(() async {
              events.add('apply-${container.read(currentProfileIdProvider)}');
            }),
            profileStatusUpdaterProvider.overrideWithValue((wantStart) async {
              expect(wantStart, isFalse);
              events.add('stop');
              return true;
            }),
            profileEffectCleanerProvider.overrideWithValue((id) async {
              events.add('cache-$id');
            }),
            profileFileCleanerProvider.overrideWithValue((id) async {
              events.add('file-$id');
            }),
          ],
        );
        addTearDown(container.dispose);
        final currentProfileSubscription = container.listen(
          currentProfileIdProvider,
          (_, _) {},
        );
        addTearDown(currentProfileSubscription.close);
        final notifier = container.read(profilesActionProvider.notifier);

        final first = notifier.deleteProfile(firstProfile.id);
        await firstDeleteStarted.future;
        final second = notifier.deleteProfile(secondProfile.id);
        await Future<void>.delayed(Duration.zero);
        expect(events, [
          'apply-${secondProfile.id}',
          'delete-${firstProfile.id}',
        ]);

        releaseFirstDelete.complete();
        await Future.wait([first, second]);

        expect(events, [
          'apply-${secondProfile.id}',
          'delete-${firstProfile.id}',
          'cache-${firstProfile.id}',
          'file-${firstProfile.id}',
          'stop',
          'delete-${secondProfile.id}',
          'cache-${secondProfile.id}',
          'file-${secondProfile.id}',
        ]);
        expect(container.read(profilesProvider), isEmpty);
        expect(container.read(currentProfileIdProvider), isNull);
      },
    );

    test('keeps the last running profile when stop fails', () async {
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
          isStartProvider.overrideWithValue(true),
          profileStatusUpdaterProvider.overrideWithValue((_) async {
            events.add('stop');
            return false;
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

      expect(events, ['stop']);
      expect(container.read(profilesProvider), [profile]);
      expect(container.read(currentProfileIdProvider), profile.id);
    });

    test('restores running state when database deletion fails', () async {
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
          isStartProvider.overrideWithValue(true),
          profileStatusUpdaterProvider.overrideWithValue((wantStart) async {
            events.add(wantStart ? 'restart' : 'stop');
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

      expect(events, ['stop', 'delete', 'restart']);
      expect(container.read(profilesProvider), [profile]);
      expect(container.read(currentProfileIdProvider), profile.id);
    });

    test('reports database failure when running state restore fails', () async {
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
          isStartProvider.overrideWithValue(true),
          profileStatusUpdaterProvider.overrideWithValue((wantStart) async {
            events.add(wantStart ? 'restart' : 'stop');
            return !wantStart;
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
        throwsA(
          isA<ProfileOperationException>().having(
            (error) => error.rollbackErrors.join(' '),
            'rollback errors',
            contains('Status updater returned false'),
          ),
        ),
      );

      expect(events, ['stop', 'delete', 'restart']);
      expect(container.read(profilesProvider), [profile]);
      expect(container.read(currentProfileIdProvider), profile.id);
    });

    test(
      'provider cache failure does not block confirmed metadata deletion',
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
            isStartProvider.overrideWithValue(true),
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

        await container
            .read(profilesActionProvider.notifier)
            .deleteProfile(profile.id);

        expect(events, ['stop', 'delete', 'cache', 'file']);
        expect(container.read(profilesProvider), isEmpty);
        expect(container.read(currentProfileIdProvider), isNull);
      },
    );

    test(
      'profile file cleanup failure does not block deletion and can be retried',
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
            isStartProvider.overrideWithValue(true),
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

        await container
            .read(profilesActionProvider.notifier)
            .deleteProfile(profile.id);
        expect(container.read(profilesProvider), isEmpty);
        expect(container.read(currentProfileIdProvider), isNull);

        await container
            .read(profilesActionProvider.notifier)
            .deleteProfile(profile.id);

        expect(events, [
          'stop',
          'delete',
          'cache',
          'file-1',
          'delete',
          'cache',
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
