import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  test('proxy geo session gate covers start, pending, and suspend states', () {
    bool active({
      CoreStatus status = CoreStatus.connected,
      int? runTime = 1,
      bool isStarting = false,
      bool suspend = false,
    }) {
      final container = ProviderContainer(
        overrides: [
          coreStatusProvider.overrideWithBuild((_, _) => status),
          runTimeProvider.overrideWithBuild((_, _) => runTime),
          isStartingProvider.overrideWithBuild((_, _) => isStarting),
          confirmedSuspendProvider.overrideWithValue(suspend),
        ],
      );
      final result = container.read(proxyGeoSessionActiveProvider);
      container.dispose();
      return result;
    }

    expect(active(), isTrue);
    expect(active(status: CoreStatus.disconnected), isFalse);
    expect(active(runTime: null), isFalse);
    expect(active(isStarting: true), isFalse);
    expect(active(suspend: true), isFalse);
  });

  group('runtime proxy selections', () {
    test('uses runtime IDs and persists stable selection keys', () async {
      final profile = Profile.normal(label: 'profile');
      final snapshot = _snapshot(generation: 7, nowId: 'leaf-a');
      ChangeProxyParams? invoked;
      var exitCalls = 0;
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          profilesProvider.overrideWith(() => _TestProfiles([profile])),
          runtimeProxyChangeExecutorProvider.overrideWithValue((params) async {
            invoked = params;
            return '';
          }),
          proxyExitGeoLoaderProvider.overrideWithValue((params) async {
            exitCalls++;
            return _exitGeo(params, params.memberId, '198.51.100.1');
          }),
          proxyConnectionRefresherProvider.overrideWithValue(() async {}),
        ],
      );
      addTearDown(container.dispose);
      container.read(runtimeProxiesProvider.notifier).value = snapshot;
      container.read(groupsProvider.notifier).value = _groups(snapshot);

      await container
          .read(proxiesActionProvider.notifier)
          .changeProxyDebounce(
            'group',
            'leaf-b',
            groupId: 'group-id',
            memberId: 'leaf-b',
            generation: 7,
            duration: Duration.zero,
          );

      expect(
        invoked,
        const ChangeProxyParams(
          groupId: 'group-id',
          memberId: 'leaf-b',
          generation: 7,
        ),
      );
      final saved = container.read(profilesProvider).single;
      expect(saved.selectedMap['group'], 'leaf-b');
      expect(saved.selectedStableMap['group-key'], 'leaf-b-key');
      expect(
        container.read(runtimeProxiesProvider).groupById('group-id')?.nowId,
        'leaf-b',
      );
      expect(exitCalls, 0, reason: 'disconnected cores must not probe exits');
    });

    test('does not guess when duplicate member names are ambiguous', () async {
      final profile = Profile.normal(label: 'profile');
      final snapshot = _snapshot(
        generation: 7,
        nowId: 'leaf-a',
        duplicateNames: true,
      );
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          profilesProvider.overrideWith(() => _TestProfiles([profile])),
          runtimeProxyChangeExecutorProvider.overrideWithValue((_) async {
            calls++;
            return '';
          }),
          proxyConnectionRefresherProvider.overrideWithValue(() async {}),
        ],
      );
      addTearDown(container.dispose);
      container.read(runtimeProxiesProvider.notifier).value = snapshot;

      await expectLater(
        container
            .read(proxiesActionProvider.notifier)
            .changeProxyDebounce('group', 'duplicate', duration: Duration.zero),
        throwsStateError,
      );
      expect(calls, 0);
    });

    test('rejects a UI intent captured from an older generation', () async {
      final profile = Profile.normal(label: 'profile');
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          profilesProvider.overrideWith(() => _TestProfiles([profile])),
          runtimeProxyChangeExecutorProvider.overrideWithValue((_) async {
            fail('stale selections must not reach the core');
          }),
          proxyConnectionRefresherProvider.overrideWithValue(() async {}),
        ],
      );
      addTearDown(container.dispose);
      container.read(runtimeProxiesProvider.notifier).value = _snapshot(
        generation: 18,
        nowId: 'leaf-a',
      );

      await expectLater(
        container
            .read(proxiesActionProvider.notifier)
            .changeProxyDebounce(
              'group',
              'leaf-b',
              groupId: 'group-id',
              memberId: 'leaf-b',
              generation: 17,
              duration: Duration.zero,
            ),
        throwsStateError,
      );
    });
  });

  group('runtime snapshot ownership', () {
    test('an older group load cannot overwrite a newer snapshot', () async {
      final first = Completer<ProxiesData>();
      final second = Completer<ProxiesData>();
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(() => _TestProfiles(const [])),
          proxiesSnapshotLoaderProvider.overrideWithValue(() {
            return calls++ == 0 ? first.future : second.future;
          }),
          proxyGroupsBuilderProvider.overrideWithValue(_buildGroups),
          proxyServerGeoLoaderProvider.overrideWithValue(_emptyServerGeos),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(proxiesActionProvider.notifier);

      final oldLoad = notifier.updateGroups();
      final newLoad = notifier.updateGroups();
      second.complete(_snapshot(generation: 2, nowId: 'leaf-b'));
      await newLoad;
      first.complete(_snapshot(generation: 1, nowId: 'leaf-a'));
      await oldLoad;

      expect(container.read(runtimeProxiesProvider).generation, 2);
      expect(
        container.read(runtimeProxiesProvider).groups.single.nowId,
        'leaf-b',
      );
    });

    test(
      'restores a uniquely matched stable selection with duplicate names once',
      () async {
        final profile = Profile.normal(
          label: 'profile',
        ).copyWith(selectedStableMap: {'group-key': 'leaf-b-key'});
        var selectedId = 'leaf-a';
        var restoreCalls = 0;
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            profilesProvider.overrideWith(() => _TestProfiles([profile])),
            proxiesSnapshotLoaderProvider.overrideWithValue(
              () async => _snapshot(
                generation: 9,
                nowId: selectedId,
                duplicateNames: true,
              ),
            ),
            proxyGroupsBuilderProvider.overrideWithValue(_buildGroups),
            runtimeProxyChangeExecutorProvider.overrideWithValue((
              params,
            ) async {
              restoreCalls++;
              selectedId = params.memberId!;
              return '';
            }),
            proxyServerGeoLoaderProvider.overrideWithValue(_emptyServerGeos),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(proxiesActionProvider.notifier);

        await notifier.updateGroups();
        await notifier.updateGroups();

        expect(restoreCalls, 1);
        expect(
          container.read(runtimeProxiesProvider).groups.single.nowId,
          'leaf-b',
        );
      },
    );
  });

  group('proxy geo ownership', () {
    test('server geo covers 1000 leaves in bounded explicit batches', () async {
      final snapshot = _largeSnapshot(1000);
      final requests = <ProxyServerGeoParams>[];
      final completed = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(() => _TestProfiles(const [])),
          proxiesSnapshotLoaderProvider.overrideWithValue(() async => snapshot),
          proxyGroupsBuilderProvider.overrideWithValue(_buildGroups),
          proxyServerGeoLoaderProvider.overrideWithValue((params) async {
            requests.add(params);
            final members = {
              for (final memberId in params.memberIds)
                memberId: ProxyServerGeo(
                  memberId: memberId,
                  serverHost: '$memberId.example',
                  source: 'dns',
                  status: 'ok',
                  addresses: const [
                    ProxyGeoAddress(ip: '203.0.113.1', countryCode: 'US'),
                  ],
                ),
            };
            if (requests.length == 2 && !completed.isCompleted) {
              completed.complete();
            }
            return ProxyServerGeos(
              generation: params.generation,
              requestId: params.requestId,
              members: members,
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(proxiesActionProvider.notifier).updateGroups();
      await completed.future;
      await Future<void>.delayed(Duration.zero);

      expect(requests, hasLength(2));
      expect(requests.every((request) => !request.all), isTrue);
      expect(requests.map((request) => request.memberIds.length), [512, 488]);
      expect(
        requests.expand((request) => request.memberIds).toSet(),
        hasLength(1000),
      );
      final state = container.read(proxyGeoDataSourceProvider);
      expect(state.serverByMemberId, hasLength(1000));
      expect(state.serverLoadingMemberIds, isEmpty);
      expect(state.staleServerMemberIds, isEmpty);
    });

    test('a new server request stops the remaining old batches', () async {
      var generation = 1;
      final oldSecondBatch = Completer<ProxyServerGeos>();
      final oldSecondStarted = Completer<void>();
      final newBatchesCompleted = Completer<void>();
      final requests = <ProxyServerGeoParams>[];
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(() => _TestProfiles(const [])),
          proxiesSnapshotLoaderProvider.overrideWithValue(
            () async => _largeSnapshot(1200, generation: generation),
          ),
          proxyGroupsBuilderProvider.overrideWithValue(_buildGroups),
          proxyServerGeoLoaderProvider.overrideWithValue((params) {
            requests.add(params);
            final generationRequests = requests
                .where((request) => request.generation == params.generation)
                .length;
            if (params.generation == 1 && generationRequests == 2) {
              oldSecondStarted.complete();
              return oldSecondBatch.future;
            }
            if (params.generation == 2 && generationRequests == 3) {
              newBatchesCompleted.complete();
            }
            return Future.value(_successfulServerBatch(params));
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(proxiesActionProvider.notifier);

      await notifier.updateGroups();
      await oldSecondStarted.future;
      generation = 2;
      await notifier.updateGroups();
      await newBatchesCompleted.future;
      oldSecondBatch.complete(
        _successfulServerBatch(
          requests.where((request) => request.generation == 1).last,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        requests.where((request) => request.generation == 1),
        hasLength(2),
      );
      expect(
        requests.where((request) => request.generation == 2),
        hasLength(3),
      );
      expect(container.read(proxyGeoDataSourceProvider).generation, 2);
    });

    test(
      'disconnect clears server loading and rejects the late response',
      () async {
        final snapshot = _snapshot(generation: 3, nowId: 'leaf-a');
        final requestStarted = Completer<ProxyServerGeoParams>();
        final response = Completer<ProxyServerGeos>();
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => null),
            profilesProvider.overrideWith(() => _TestProfiles(const [])),
            coreStatusProvider.overrideWithBuild(
              (_, _) => CoreStatus.connected,
            ),
            proxiesSnapshotLoaderProvider.overrideWithValue(
              () async => snapshot,
            ),
            proxyGroupsBuilderProvider.overrideWithValue(_buildGroups),
            proxyServerGeoLoaderProvider.overrideWithValue((params) {
              requestStarted.complete(params);
              return response.future;
            }),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(proxiesActionProvider.notifier);

        await notifier.updateGroups();
        final request = await requestStarted.future;
        expect(
          container.read(proxyGeoDataSourceProvider).serverLoadingMemberIds,
          {'leaf-a', 'leaf-b'},
        );

        container.read(coreStatusProvider.notifier).value =
            CoreStatus.disconnected;
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(proxyGeoDataSourceProvider).serverLoadingMemberIds,
          isEmpty,
        );

        response.complete(_successfulServerBatch(request));
        await Future<void>.delayed(Duration.zero);
        final state = container.read(proxyGeoDataSourceProvider);
        expect(state.serverByMemberId, isEmpty);
        expect(state.serverLoadingMemberIds, isEmpty);
      },
    );

    test('transient server geo retries only after five minutes', () async {
      final snapshot = _largeSnapshot(1);
      var now = DateTime.utc(2026, 1, 1);
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(() => _TestProfiles(const [])),
          proxyGeoClockProvider.overrideWithValue(() => now),
          proxiesSnapshotLoaderProvider.overrideWithValue(() async => snapshot),
          proxyGroupsBuilderProvider.overrideWithValue(_buildGroups),
          proxyServerGeoLoaderProvider.overrideWithValue((params) async {
            calls++;
            final memberId = params.memberIds.single;
            return ProxyServerGeos(
              generation: params.generation,
              requestId: params.requestId,
              members: {
                memberId: ProxyServerGeo(
                  memberId: memberId,
                  serverHost: '$memberId.example',
                  source: 'dns',
                  status: calls == 1 ? 'resolve-error' : 'ok',
                  addresses: calls == 1
                      ? const []
                      : const [
                          ProxyGeoAddress(ip: '203.0.113.9', countryCode: 'JP'),
                        ],
                ),
              },
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(proxiesActionProvider.notifier);

      await notifier.updateGroups();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(
        container.read(proxyGeoDataSourceProvider).staleServerMemberIds,
        contains('leaf-0000'),
      );

      now = now.add(const Duration(minutes: 4, seconds: 59));
      await notifier.updateGroups();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);

      now = now.add(const Duration(seconds: 1));
      await notifier.updateGroups();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      final state = container.read(proxyGeoDataSourceProvider);
      expect(state.staleServerMemberIds, isNot(contains('leaf-0000')));
      expect(
        state.serverByMemberId['leaf-0000']?.primaryAddress?.countryCode,
        'JP',
      );
    });

    test('an old server response cannot overwrite a new generation', () async {
      var snapshotGeneration = 1;
      final requests = <ProxyServerGeoParams>[];
      final responses = <Completer<ProxyServerGeos>>[];
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(() => _TestProfiles(const [])),
          proxiesSnapshotLoaderProvider.overrideWithValue(
            () async =>
                _snapshot(generation: snapshotGeneration, nowId: 'leaf-a'),
          ),
          proxyGroupsBuilderProvider.overrideWithValue(_buildGroups),
          proxyServerGeoLoaderProvider.overrideWithValue((params) {
            requests.add(params);
            final response = Completer<ProxyServerGeos>();
            responses.add(response);
            return response.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(proxiesActionProvider.notifier);

      await notifier.updateGroups();
      snapshotGeneration = 2;
      await notifier.updateGroups();
      expect(requests, hasLength(2));

      responses[1].complete(
        _serverGeos(requests[1], ip: '203.0.113.2', countryCode: 'JP'),
      );
      await Future<void>.delayed(Duration.zero);
      responses[0].complete(
        _serverGeos(requests[0], ip: '203.0.113.1', countryCode: 'US'),
      );
      await Future<void>.delayed(Duration.zero);

      final state = container.read(proxyGeoDataSourceProvider);
      expect(state.generation, 2);
      expect(
        state.serverByMemberId['leaf-a']?.primaryAddress?.countryCode,
        'JP',
      );
    });

    test(
      'MMDB revision invalidates state and rejects the old response',
      () async {
        final snapshot = _snapshot(generation: 4, nowId: 'leaf-a');
        final requests = <ProxyServerGeoParams>[];
        final responses = <Completer<ProxyServerGeos>>[];
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => null),
            profilesProvider.overrideWith(() => _TestProfiles(const [])),
            proxiesSnapshotLoaderProvider.overrideWithValue(
              () async => snapshot,
            ),
            proxyGroupsBuilderProvider.overrideWithValue(_buildGroups),
            proxyServerGeoLoaderProvider.overrideWithValue((params) {
              requests.add(params);
              final response = Completer<ProxyServerGeos>();
              responses.add(response);
              return response.future;
            }),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(proxiesActionProvider.notifier);

        await notifier.updateGroups();
        expect(requests, hasLength(1));
        container.read(geoDatabaseRevisionProvider.notifier).bump();
        await Future<void>.delayed(Duration.zero);
        expect(requests, hasLength(2));
        expect(
          container.read(proxyGeoDataSourceProvider).geoDatabaseRevision,
          1,
        );

        responses[0].complete(
          _serverGeos(requests[0], ip: '203.0.113.1', countryCode: 'US'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(proxyGeoDataSourceProvider).serverByMemberId['leaf-a'],
          isNull,
        );

        responses[1].complete(
          _serverGeos(requests[1], ip: '203.0.113.2', countryCode: 'JP'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          container
              .read(proxyGeoDataSourceProvider)
              .serverByMemberId['leaf-a']
              ?.primaryAddress
              ?.countryCode,
          'JP',
        );
      },
    );

    test(
      'MMDB revision rejects an old exit and reprobes the active leaf',
      () async {
        final profile = Profile.normal(
          label: 'profile',
        ).copyWith(currentGroupName: 'group');
        final snapshot = _snapshot(generation: 8, nowId: 'leaf-a');
        final requests = <ProbeProxyExitParams>[];
        final responses = <Completer<ProxyExitGeo>>[];
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            profilesProvider.overrideWith(() => _TestProfiles([profile])),
            coreStatusProvider.overrideWithBuild(
              (_, _) => CoreStatus.connected,
            ),
            runTimeProvider.overrideWithBuild((_, _) => 1),
            proxiesSnapshotLoaderProvider.overrideWithValue(
              () async => snapshot,
            ),
            proxyGroupsBuilderProvider.overrideWithValue(_buildGroups),
            proxyServerGeoLoaderProvider.overrideWithValue(_emptyServerGeos),
            proxyExitGeoLoaderProvider.overrideWithValue((params) {
              requests.add(params);
              final response = Completer<ProxyExitGeo>();
              responses.add(response);
              return response.future;
            }),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(proxiesActionProvider.notifier);

        await notifier.updateGroups();
        await Future<void>.delayed(Duration.zero);
        expect(requests, hasLength(1));

        container.read(geoDatabaseRevisionProvider.notifier).bump();
        await Future<void>.delayed(Duration.zero);
        expect(requests, hasLength(2));

        responses[0].complete(
          _exitGeo(
            requests[0],
            'leaf-a',
            '198.51.100.1',
          ).copyWith(countryCode: 'US'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(proxyGeoDataSourceProvider).exitByMemberId['leaf-a'],
          isNull,
        );

        responses[1].complete(
          _exitGeo(
            requests[1],
            'leaf-a',
            '198.51.100.1',
          ).copyWith(countryCode: 'JP'),
        );
        await Future<void>.delayed(Duration.zero);
        final state = container.read(proxyGeoDataSourceProvider);
        expect(state.activeExitLeafId, 'leaf-a');
        expect(state.exitByMemberId['leaf-a']?.countryCode, 'JP');
      },
    );

    test('partial MMDB results do not enter the 24 hour cache', () async {
      var generation = 5;
      var serverCalls = 0;
      final secondResponse = Completer<ProxyServerGeos>();
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(() => _TestProfiles(const [])),
          proxiesSnapshotLoaderProvider.overrideWithValue(
            () async => _snapshot(generation: generation, nowId: 'leaf-a'),
          ),
          proxyGroupsBuilderProvider.overrideWithValue(_buildGroups),
          proxyServerGeoLoaderProvider.overrideWithValue((params) {
            serverCalls++;
            if (serverCalls == 1) {
              return Future.value(
                _serverGeos(params, ip: '203.0.113.1', countryCode: ''),
              );
            }
            return secondResponse.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(proxiesActionProvider.notifier);

      await notifier.updateGroups();
      await Future<void>.delayed(Duration.zero);
      expect(
        container
            .read(proxyGeoDataSourceProvider)
            .serverByMemberId['leaf-a']
            ?.primaryAddress
            ?.countryCode,
        isEmpty,
      );

      generation = 6;
      await notifier.updateGroups();
      expect(serverCalls, 2);
      expect(
        container.read(proxyGeoDataSourceProvider).serverByMemberId['leaf-a'],
        isNull,
        reason: 'partial data must not be seeded into a new generation',
      );
      secondResponse.complete(
        _serverGeos(
          const ProxyServerGeoParams(generation: 6),
          ip: '203.0.113.2',
          countryCode: 'JP',
        ),
      );
    });

    test('rapid switching discards the previous exit response', () async {
      final profile = Profile.normal(label: 'profile');
      final snapshot = _snapshot(generation: 11, nowId: 'leaf-a');
      final requests = <ProbeProxyExitParams>[];
      final responses = <Completer<ProxyExitGeo>>[];
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          profilesProvider.overrideWith(() => _TestProfiles([profile])),
          coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
          runTimeProvider.overrideWithBuild((_, _) => 1),
          runtimeProxyChangeExecutorProvider.overrideWithValue((_) async => ''),
          proxyConnectionRefresherProvider.overrideWithValue(() async {}),
          proxyExitGeoLoaderProvider.overrideWithValue((params) {
            requests.add(params);
            final response = Completer<ProxyExitGeo>();
            responses.add(response);
            return response.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(runtimeProxiesProvider.notifier).value = snapshot;
      container.read(groupsProvider.notifier).value = _groups(snapshot);
      final notifier = container.read(proxiesActionProvider.notifier);

      await notifier.changeProxyDebounce(
        'group',
        'leaf-a',
        groupId: 'group-id',
        memberId: 'leaf-a',
        generation: 11,
        duration: Duration.zero,
      );
      await notifier.changeProxyDebounce(
        'group',
        'leaf-b',
        groupId: 'group-id',
        memberId: 'leaf-b',
        generation: 11,
        duration: Duration.zero,
      );
      expect(requests, hasLength(2));

      responses[1].complete(_exitGeo(requests[1], 'leaf-b', '198.51.100.2'));
      await Future<void>.delayed(Duration.zero);
      responses[0].complete(_exitGeo(requests[0], 'leaf-a', '198.51.100.1'));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(proxyGeoDataSourceProvider);
      expect(state.activeExitLeafId, 'leaf-b');
      expect(state.exitByMemberId['leaf-b']?.ip, '198.51.100.2');
      expect(state.exitByMemberId['leaf-a'], isNull);

      container.read(runTimeProvider.notifier).value = null;
      await Future<void>.delayed(Duration.zero);
      final stopped = container.read(proxyGeoDataSourceProvider);
      expect(stopped.activeExitLeafId, isNull);
      expect(stopped.staleExitMemberIds, contains('leaf-b'));

      container.read(runTimeProvider.notifier).value = 2;
      await Future<void>.delayed(Duration.zero);
      expect(requests, hasLength(3));
      responses[2].complete(_exitGeo(requests[2], 'leaf-b', '198.51.100.3'));
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(proxyGeoDataSourceProvider).activeExitLeafId,
        'leaf-b',
      );
    });

    test('exit probe exception clears loading and allows retry', () async {
      var calls = 0;
      final container = _exitProbeTestContainer((params) async {
        calls++;
        if (calls == 1) throw StateError('remote action failed');
        return _exitGeo(params, 'leaf-b', '198.51.100.2');
      });
      addTearDown(container.dispose);

      await _selectTestLeaf(container, 'leaf-b');
      final failed = await _waitForProxyGeoState(
        container,
        (state) =>
            state.exitLoadingMemberIds.isEmpty &&
            state.exitErrorsByMemberId.containsKey('leaf-b'),
      );
      expect(failed.staleExitMemberIds, contains('leaf-b'));
      expect(failed.exitError, isNotNull);

      await _selectTestLeaf(container, 'leaf-b');
      final recovered = await _waitForProxyGeoState(
        container,
        (state) => state.exitByMemberId['leaf-b']?.ip == '198.51.100.2',
      );
      expect(recovered.exitLoadingMemberIds, isEmpty);
      expect(recovered.exitErrorsByMemberId['leaf-b'], isNull);
      expect(recovered.staleExitMemberIds, isNot(contains('leaf-b')));
    });

    test('stale exit response clears loading and allows retry', () async {
      var calls = 0;
      final container = _exitProbeTestContainer((params) async {
        calls++;
        final response = _exitGeo(params, 'leaf-b', '198.51.100.2');
        return calls == 1 ? response.copyWith(stale: true) : response;
      });
      addTearDown(container.dispose);

      await _selectTestLeaf(container, 'leaf-b');
      final stale = await _waitForProxyGeoState(
        container,
        (state) =>
            state.exitLoadingMemberIds.isEmpty &&
            state.staleExitMemberIds.contains('leaf-b'),
      );
      expect(stale.exitByMemberId['leaf-b'], isNull);

      await _selectTestLeaf(container, 'leaf-b');
      final recovered = await _waitForProxyGeoState(
        container,
        (state) => state.exitByMemberId['leaf-b']?.ip == '198.51.100.2',
      );
      expect(recovered.exitLoadingMemberIds, isEmpty);
      expect(recovered.staleExitMemberIds, isNot(contains('leaf-b')));
    });

    test('exit watchdog clears a hung action and allows retry', () async {
      var calls = 0;
      final blocked = Completer<ProxyExitGeo>();
      final container = _exitProbeTestContainer((params) {
        calls++;
        return calls == 1
            ? blocked.future
            : Future.value(_exitGeo(params, 'leaf-b', '198.51.100.2'));
      }, timeout: const Duration(milliseconds: 20));
      addTearDown(container.dispose);

      await _selectTestLeaf(container, 'leaf-b');
      final timedOut = await _waitForProxyGeoState(
        container,
        (state) =>
            state.exitLoadingMemberIds.isEmpty &&
            state.exitErrorsByMemberId.containsKey('leaf-b'),
      );
      expect(timedOut.staleExitMemberIds, contains('leaf-b'));

      await _selectTestLeaf(container, 'leaf-b');
      final recovered = await _waitForProxyGeoState(
        container,
        (state) => state.exitByMemberId['leaf-b']?.ip == '198.51.100.2',
      );
      expect(recovered.exitLoadingMemberIds, isEmpty);
      expect(calls, 2);
      blocked.complete(
        _exitGeo(
          const ProbeProxyExitParams(
            generation: 11,
            groupId: 'group-id',
            memberId: 'leaf-b',
          ),
          'leaf-b',
          '198.51.100.9',
        ),
      );
    });

    test('same-generation refresh preserves one pending exit action', () async {
      var loadedSnapshot = _snapshot(generation: 11, nowId: 'leaf-a');
      final requests = <ProbeProxyExitParams>[];
      final response = Completer<ProxyExitGeo>();
      final container = _exitProbeTestContainer((params) {
        requests.add(params);
        return response.future;
      }, snapshotLoader: () async => loadedSnapshot);
      addTearDown(container.dispose);
      final notifier = container.read(proxiesActionProvider.notifier);

      await _selectTestLeaf(container, 'leaf-b');
      loadedSnapshot = container.read(runtimeProxiesProvider);
      container.read(runTimeProvider.notifier).value = 2;
      await Future<void>.delayed(Duration.zero);
      expect(requests, hasLength(1), reason: 'runtime ticks are not restarts');
      await notifier.updateGroups();

      expect(requests, hasLength(1));
      expect(container.read(proxyGeoDataSourceProvider).exitLoadingMemberIds, {
        'leaf-b',
      });
      response.complete(_exitGeo(requests.single, 'leaf-b', '198.51.100.2'));
      final completed = await _waitForProxyGeoState(
        container,
        (state) => state.exitByMemberId['leaf-b']?.ip == '198.51.100.2',
      );
      expect(completed.exitLoadingMemberIds, isEmpty);
    });

    test('failed exit probe backs off automatic refreshes', () async {
      var now = DateTime.utc(2026, 7, 17);
      var calls = 0;
      var loadedSnapshot = _snapshot(generation: 11, nowId: 'leaf-a');
      final container = _exitProbeTestContainer(
        (_) async {
          calls++;
          throw StateError('endpoint unavailable');
        },
        clock: () => now,
        snapshotLoader: () async => loadedSnapshot,
      );
      addTearDown(container.dispose);
      final notifier = container.read(proxiesActionProvider.notifier);

      await _selectTestLeaf(container, 'leaf-b');
      loadedSnapshot = container.read(runtimeProxiesProvider);
      final failed = await _waitForProxyGeoState(
        container,
        (state) => state.exitErrorsByMemberId.containsKey('leaf-b'),
      );
      expect(failed.exitLoadingMemberIds, isEmpty);

      await notifier.updateGroups();
      await notifier.updateGroups();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(
        container.read(proxyGeoDataSourceProvider).exitLoadingMemberIds,
        isEmpty,
      );

      now = now.add(const Duration(seconds: 59));
      await notifier.updateGroups();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);

      now = now.add(const Duration(seconds: 1));
      await notifier.updateGroups();
      await _waitForProxyGeoState(
        container,
        (state) => calls == 2 && state.exitLoadingMemberIds.isEmpty,
      );
      expect(calls, 2);
    });

    test('same-generation nowId changes discard the old leaf path', () async {
      final profile = Profile.normal(label: 'profile');
      final snapshot = _nestedSnapshot(generation: 12, innerNowId: 'leaf-a');
      final requests = <ProbeProxyExitParams>[];
      final responses = <Completer<ProxyExitGeo>>[];
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          profilesProvider.overrideWith(() => _TestProfiles([profile])),
          coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
          runTimeProvider.overrideWithBuild((_, _) => 1),
          runtimeProxyChangeExecutorProvider.overrideWithValue((_) async => ''),
          proxyConnectionRefresherProvider.overrideWithValue(() async {}),
          proxyExitGeoLoaderProvider.overrideWithValue((params) {
            requests.add(params);
            final response = Completer<ProxyExitGeo>();
            responses.add(response);
            return response.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(runtimeProxiesProvider.notifier).value = snapshot;
      container.read(groupsProvider.notifier).value = [];
      final notifier = container.read(proxiesActionProvider.notifier);

      await notifier.changeProxyDebounce(
        'group',
        'inner',
        groupId: 'group-id',
        memberId: 'inner-id',
        generation: 12,
        duration: Duration.zero,
      );
      expect(requests, hasLength(1));

      container.read(runtimeProxiesProvider.notifier).value = snapshot.copyWith(
        groups: snapshot.groups
            .map(
              (group) => group.id == 'inner-id'
                  ? group.copyWith(nowId: 'leaf-b')
                  : group,
            )
            .toList(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(requests, hasLength(2));

      responses[0].complete(
        _exitGeo(
          requests[0],
          'leaf-a',
          '198.51.100.1',
        ).copyWith(pathIds: ['group-id', 'inner-id', 'leaf-a']),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(proxyGeoDataSourceProvider).exitByMemberId['leaf-a'],
        isNull,
      );

      responses[1].complete(
        _exitGeo(
          requests[1],
          'leaf-b',
          '198.51.100.2',
        ).copyWith(pathIds: ['group-id', 'inner-id', 'leaf-b']),
      );
      await Future<void>.delayed(Duration.zero);
      final state = container.read(proxyGeoDataSourceProvider);
      expect(state.activeExitLeafId, 'leaf-b');
      expect(state.exitByMemberId['leaf-b']?.ip, '198.51.100.2');
    });

    test('dynamic group nowId invalidates the previous active exit', () async {
      final profile = Profile.normal(
        label: 'profile',
      ).copyWith(currentGroupName: 'group');
      final snapshot = _nestedSnapshot(generation: 13, innerNowId: 'leaf-a');
      final requests = <ProbeProxyExitParams>[];
      final responses = <Completer<ProxyExitGeo>>[];
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          profilesProvider.overrideWith(() => _TestProfiles([profile])),
          coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
          runTimeProvider.overrideWithBuild((_, _) => 1),
          runtimeProxyChangeExecutorProvider.overrideWithValue((_) async => ''),
          proxyConnectionRefresherProvider.overrideWithValue(() async {}),
          proxyExitGeoLoaderProvider.overrideWithValue((params) {
            requests.add(params);
            final response = Completer<ProxyExitGeo>();
            responses.add(response);
            return response.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(proxiesActionProvider.notifier);

      container.read(runtimeProxiesProvider.notifier).value = snapshot;
      await notifier.changeProxyDebounce(
        'group',
        'inner',
        groupId: 'group-id',
        memberId: 'inner-id',
        generation: 13,
        duration: Duration.zero,
      );
      await Future<void>.delayed(Duration.zero);
      responses.single.complete(
        _exitGeo(
          requests.single,
          'leaf-a',
          '198.51.100.1',
        ).copyWith(pathIds: ['group-id', 'inner-id', 'leaf-a']),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(proxyGeoDataSourceProvider).activeExitLeafId,
        'leaf-a',
      );

      container.read(runtimeProxiesProvider.notifier).value = snapshot.copyWith(
        groups: snapshot.groups
            .map(
              (group) => group.id == 'inner-id'
                  ? group.copyWith(nowId: 'leaf-b')
                  : group,
            )
            .toList(),
      );
      await Future<void>.delayed(Duration.zero);

      final state = container.read(proxyGeoDataSourceProvider);
      expect(state.activeExitLeafId, 'leaf-b');
      expect(state.staleExitMemberIds, contains('leaf-a'));
      expect(requests, hasLength(2));
    });
  });
}

ProxiesData _largeSnapshot(int leafCount, {int generation = 100}) {
  final memberIds = List.generate(
    leafCount,
    (index) => 'leaf-${index.toString().padLeft(4, '0')}',
  );
  return ProxiesData(
    generation: generation,
    groups: [
      ProxyGroupSnapshot(
        id: 'group-id',
        name: 'group',
        type: 'Selector',
        nowId: memberIds.first,
        memberIds: memberIds,
      ),
    ],
    nodesById: {
      'group-id': const ProxyNodeSnapshot(
        id: 'group-id',
        stableKey: 'group-key',
        name: 'group',
        type: 'Selector',
      ),
      for (final memberId in memberIds)
        memberId: ProxyNodeSnapshot(
          id: memberId,
          stableKey: '$memberId-key',
          name: memberId,
          type: 'Vless',
        ),
    },
  );
}

ProxyServerGeos _successfulServerBatch(ProxyServerGeoParams params) {
  return ProxyServerGeos(
    generation: params.generation,
    requestId: params.requestId,
    members: {
      for (final memberId in params.memberIds)
        memberId: ProxyServerGeo(
          memberId: memberId,
          serverHost: '$memberId.example',
          source: 'dns',
          status: 'ok',
          addresses: const [
            ProxyGeoAddress(ip: '203.0.113.1', countryCode: 'US'),
          ],
        ),
    },
  );
}

ProxiesData _snapshot({
  required int generation,
  required String nowId,
  bool duplicateNames = false,
}) {
  final leafAName = duplicateNames ? 'duplicate' : 'leaf-a';
  final leafBName = duplicateNames ? 'duplicate' : 'leaf-b';
  return ProxiesData(
    proxies: const {
      'group': {'name': 'group', 'type': 'Selector'},
    },
    all: const ['group'],
    generation: generation,
    groups: [
      ProxyGroupSnapshot(
        id: 'group-id',
        name: 'group',
        type: 'Selector',
        nowId: nowId,
        memberIds: const ['leaf-a', 'leaf-b'],
      ),
    ],
    nodesById: {
      'group-id': const ProxyNodeSnapshot(
        id: 'group-id',
        stableKey: 'group-key',
        name: 'group',
        type: 'Selector',
      ),
      'leaf-a': ProxyNodeSnapshot(
        id: 'leaf-a',
        stableKey: 'leaf-a-key',
        name: leafAName,
        type: 'Vless',
      ),
      'leaf-b': ProxyNodeSnapshot(
        id: 'leaf-b',
        stableKey: 'leaf-b-key',
        name: leafBName,
        type: 'Vless',
      ),
    },
  );
}

ProxiesData _nestedSnapshot({
  required int generation,
  required String innerNowId,
}) {
  return ProxiesData(
    generation: generation,
    groups: [
      const ProxyGroupSnapshot(
        id: 'group-id',
        name: 'group',
        type: 'Selector',
        nowId: 'inner-id',
        memberIds: ['inner-id'],
      ),
      ProxyGroupSnapshot(
        id: 'inner-id',
        name: 'inner',
        type: 'URLTest',
        nowId: innerNowId,
        memberIds: const ['leaf-a', 'leaf-b'],
      ),
    ],
    nodesById: const {
      'group-id': ProxyNodeSnapshot(
        id: 'group-id',
        stableKey: 'group-key',
        name: 'group',
        type: 'Selector',
      ),
      'inner-id': ProxyNodeSnapshot(
        id: 'inner-id',
        stableKey: 'inner-key',
        name: 'inner',
        type: 'URLTest',
      ),
      'leaf-a': ProxyNodeSnapshot(
        id: 'leaf-a',
        stableKey: 'leaf-a-key',
        name: 'leaf-a',
        type: 'Vless',
      ),
      'leaf-b': ProxyNodeSnapshot(
        id: 'leaf-b',
        stableKey: 'leaf-b-key',
        name: 'leaf-b',
        type: 'Vless',
      ),
    },
  );
}

List<Group> _groups(ProxiesData snapshot) {
  final group = snapshot.groups.single;
  return [
    Group(
      type: GroupType.Selector,
      name: group.name,
      runtimeId: group.id,
      stableKey: snapshot.nodesById[group.id]!.stableKey,
      nowId: group.nowId,
      now: snapshot.nodesById[group.nowId]?.name,
      all: group.memberIds.map((id) {
        final node = snapshot.nodesById[id]!;
        return Proxy(
          name: node.name,
          type: node.type,
          runtimeId: node.id,
          stableKey: node.stableKey,
        );
      }).toList(),
    ),
  ];
}

Future<List<Group>> _buildGroups({
  required ProxiesData proxiesData,
  required ProxiesSortType sortType,
  required DelayMap delayMap,
  required Map<String, String> selectedMap,
  required String defaultTestUrl,
}) async {
  return _groups(proxiesData);
}

Future<ProxyServerGeos> _emptyServerGeos(ProxyServerGeoParams params) async {
  return ProxyServerGeos(
    generation: params.generation,
    requestId: params.requestId,
  );
}

ProxyServerGeos _serverGeos(
  ProxyServerGeoParams params, {
  required String ip,
  required String countryCode,
}) {
  return ProxyServerGeos(
    generation: params.generation,
    requestId: params.requestId,
    members: {
      'leaf-a': ProxyServerGeo(
        memberId: 'leaf-a',
        serverHost: 'server.example',
        source: 'dns',
        status: 'ok',
        addresses: [ProxyGeoAddress(ip: ip, countryCode: countryCode)],
      ),
    },
  );
}

ProxyExitGeo _exitGeo(ProbeProxyExitParams params, String leafId, String ip) {
  return ProxyExitGeo(
    generation: params.generation,
    requestId: params.requestId,
    leafId: leafId,
    ip: ip,
    countryCode: 'US',
  );
}

ProviderContainer _exitProbeTestContainer(
  ProxyExitGeoLoader loader, {
  Duration timeout = const Duration(seconds: 1),
  ProxiesSnapshotLoader? snapshotLoader,
  ProxyGeoClock? clock,
}) {
  final profile = Profile.normal(label: 'profile');
  final snapshot = _snapshot(generation: 11, nowId: 'leaf-a');
  final container = ProviderContainer(
    overrides: [
      currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
      profilesProvider.overrideWith(() => _TestProfiles([profile])),
      coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
      runTimeProvider.overrideWithBuild((_, _) => 1),
      runtimeProxyChangeExecutorProvider.overrideWithValue((_) async => ''),
      proxyConnectionRefresherProvider.overrideWithValue(() async {}),
      proxyExitGeoLoaderProvider.overrideWithValue(loader),
      proxyExitGeoTimeoutProvider.overrideWithValue(timeout),
      if (clock != null) proxyGeoClockProvider.overrideWithValue(clock),
      proxiesSnapshotLoaderProvider.overrideWithValue(
        snapshotLoader ?? () async => snapshot,
      ),
      proxyGroupsBuilderProvider.overrideWithValue(_buildGroups),
      proxyServerGeoLoaderProvider.overrideWithValue(_emptyServerGeos),
    ],
  );
  container.read(runtimeProxiesProvider.notifier).value = snapshot;
  container.read(groupsProvider.notifier).value = _groups(snapshot);
  return container;
}

Future<void> _selectTestLeaf(
  ProviderContainer container,
  String memberId,
) async {
  await container
      .read(proxiesActionProvider.notifier)
      .changeProxyDebounce(
        'group',
        memberId,
        groupId: 'group-id',
        memberId: memberId,
        generation: 11,
        duration: Duration.zero,
      );
}

Future<ProxyGeoState> _waitForProxyGeoState(
  ProviderContainer container,
  bool Function(ProxyGeoState state) matches,
) async {
  final completer = Completer<ProxyGeoState>();
  final subscription = container.listen<ProxyGeoState>(
    proxyGeoDataSourceProvider,
    (_, next) {
      if (matches(next) && !completer.isCompleted) {
        completer.complete(next);
      }
    },
    fireImmediately: true,
  );
  try {
    return await completer.future.timeout(const Duration(seconds: 2));
  } finally {
    subscription.close();
  }
}

class _TestProfiles extends Profiles {
  final List<Profile> initial;

  _TestProfiles(this.initial);

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
}
