import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

class _FakeSetupCoreOperations implements SetupCoreOperations {
  bool startResult = true;
  bool stopResult = true;
  Object? setupError;
  Object? stopError;
  int preloadCalls = 0;
  int resetCalls = 0;
  int stopCalls = 0;

  @override
  Future<void> resetTraffic() async => resetCalls++;

  @override
  Future<String> setupConfig({
    required SetupParams params,
    required SetupState setupState,
    FutureOr<void> Function()? preloadInvoke,
  }) async {
    final error = setupError;
    if (error != null) {
      throw error;
    }
    if (preloadInvoke != null) {
      preloadCalls++;
      await preloadInvoke();
    }
    return '';
  }

  @override
  Future<bool> startListener() async => startResult;

  @override
  Future<bool> stopListener() async {
    stopCalls++;
    final error = stopError;
    if (error != null) throw error;
    return stopResult;
  }
}

class _ConnectedCoreOperations implements CoreLifecycleOperations {
  @override
  bool get isCompleted => true;

  @override
  Future<bool> init(int version) async => true;

  @override
  Future<bool> get isInit async => true;

  @override
  Future<String> preload() async => '';

  @override
  Future<bool> shutdown(bool isUser) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSetupCoreOperations operations;
  late ProviderContainer container;

  setUp(() {
    operations = _FakeSetupCoreOperations();
    container = ProviderContainer(
      overrides: [
        setupCoreOperationsProvider.overrideWithValue(operations),
        coreLifecycleOperationsProvider.overrideWithValue(
          _ConnectedCoreOperations(),
        ),
        configFileWriterProvider.overrideWithValue((_) async {}),
      ],
    );
    container.read(initProvider.notifier).value = true;
  });

  tearDown(() => container.dispose());

  test('start listener false is propagated', () async {
    operations.startResult = false;

    await expectLater(
      requireSuccessfulListenerStart(operations.startListener),
      throwsStateError,
    );
  });

  test('core setup failure short-circuits listener startup', () async {
    operations.setupError = StateError('core disconnected');

    await expectLater(
      operations.setupConfig(
        params: const SetupParams(
          selectedMap: {},
          testUrl: 'https://example.com',
        ),
        setupState: const SetupState(
          profileId: null,
          profileLastUpdateDate: null,
          overwriteType: OverwriteType.standard,
          rules: [],
          proxyGroups: [],
          addedRules: [],
          script: null,
          overrideDns: false,
          dns: Dns(),
        ),
        preloadInvoke: () async {},
      ),
      throwsStateError,
    );

    expect(operations.preloadCalls, 0);
  });

  test('shared state persistence is awaited before service startup', () async {
    final persistStarted = Completer<void>();
    final releasePersist = Completer<void>();
    var persisted = false;
    const state = SharedState(
      stopTip: 'stop tip',
      startTip: 'start tip',
      currentProfileName: 'profile',
      stopText: 'stop',
      onlyStatisticsProxy: false,
      crashlytics: false,
    );

    final persistence = persistSharedStateBeforeService(
      state: state,
      persist: (_) async {
        persistStarted.complete();
        await releasePersist.future;
        persisted = true;
      },
    );
    await persistStarted.future;
    expect(persisted, isFalse);

    releasePersist.complete();
    await persistence;
    expect(persisted, isTrue);
  });

  test(
    'post-apply refresh failure does not roll back a committed core config',
    () async {
      var coreCommitted = false;
      Object? reportedError;
      coreCommitted = true;

      final refreshed = await runPostApplyRefresh(
        refresh: () => throw StateError('provider refresh failed'),
        tolerateFailure: true,
        reportFailure: (error, _) => reportedError = error,
      );

      expect(coreCommitted, isTrue);
      expect(refreshed, isFalse);
      expect(reportedError, isA<StateError>());
    },
  );

  test(
    'post-apply refresh retries before invalidating stale snapshots',
    () async {
      var attempts = 0;
      var invalidations = 0;
      final delays = <Duration>[];
      Object? reportedError;

      final refreshed = await runPostApplyRefresh(
        refresh: () {
          attempts++;
          throw StateError('provider refresh failed');
        },
        tolerateFailure: true,
        maxAttempts: 3,
        retryDelay: const Duration(milliseconds: 100),
        delay: (duration) async => delays.add(duration),
        onFinalFailure: () => invalidations++,
        reportFailure: (error, _) => reportedError = error,
      );

      expect(refreshed, isFalse);
      expect(attempts, 3);
      expect(delays, [
        const Duration(milliseconds: 100),
        const Duration(milliseconds: 100),
      ]);
      expect(invalidations, 1);
      expect(reportedError, isA<StateError>());
    },
  );

  test(
    'post-start IP check runs immediately only after proxy state is ready',
    () async {
      container.dispose();
      var calls = 0;
      var foreground = false;
      container = ProviderContainer(
        overrides: [
          initProvider.overrideWithBuild((_, _) => true),
          runTimeProvider.overrideWithBuild((_, _) => 1),
          coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
          ipCheckForegroundGateProvider.overrideWithValue(() => foreground),
          dashboardStateProvider.overrideWithValue(
            const DashboardState(
              dashboardWidgets: [DashboardWidget.networkDetection],
              contentWidth: 400,
            ),
          ),
          ipInfoLoaderProvider.overrideWithValue((_, _) async {
            calls++;
            expect(container.read(isStartProvider), isTrue);
            expect(container.read(isStartingProvider), isFalse);
            expect(container.read(coreStatusProvider), CoreStatus.connected);
            return Result.success(
              const IpInfo(ip: '1.1.1.1', countryCode: 'US'),
            );
          }),
        ],
      );

      container.read(postStartIpCheckTriggerProvider)();
      expect(calls, 0);
      expect(container.read(checkIpNumProvider), 1);

      foreground = true;
      container.read(setupActionProvider.notifier).tryCheckIp();
      expect(calls, 1);
      expect(container.read(checkIpNumProvider), 2);
      await Future<void>.delayed(Duration.zero);

      container.read(isStartingProvider.notifier).value = true;
      container.read(postStartIpCheckTriggerProvider)();
      expect(calls, 1);
      expect(container.read(checkIpNumProvider), 3);
    },
  );

  test(
    'stop listener false preserves running state and returns false',
    () async {
      container.dispose();
      var postStopChecks = 0;
      container = ProviderContainer(
        overrides: [
          setupCoreOperationsProvider.overrideWithValue(operations),
          postStopIpCheckTriggerProvider.overrideWithValue(
            () => postStopChecks++,
          ),
        ],
      );
      container.read(initProvider.notifier).value = true;
      const runTime = 1;
      container.read(runTimeProvider.notifier).value = runTime;
      operations.stopResult = false;

      final stopped = await container
          .read(setupActionProvider.notifier)
          .updateStatus(false);

      expect(stopped, isFalse);
      expect(operations.stopCalls, 1);
      expect(container.read(runTimeProvider), runTime);
      expect(operations.resetCalls, 0);
      expect(container.read(isStartingProvider), isFalse);
      expect(container.read(checkIpNumProvider), 0);
      expect(postStopChecks, 0);
    },
  );

  test(
    'confirmed suspended session stops locally without a second native stop',
    () async {
      container.dispose();
      container = ProviderContainer(
        overrides: [setupCoreOperationsProvider.overrideWithValue(operations)],
      );
      container.read(initProvider.notifier).value = true;
      container.read(runTimeProvider.notifier).value = 1;
      container.read(confirmedSuspendProvider.notifier).value = true;
      operations.stopResult = false;

      final stopped = await container
          .read(setupActionProvider.notifier)
          .updateStatus(false);

      expect(stopped, isTrue);
      expect(operations.stopCalls, 0);
      expect(operations.resetCalls, 1);
      expect(container.read(runTimeProvider), isNull);
      expect(container.read(confirmedSuspendProvider), isFalse);
      expect(container.read(isStartingProvider), isFalse);
    },
  );

  test('native stop exception preserves the running state', () async {
    container.dispose();
    container = ProviderContainer(
      overrides: [setupCoreOperationsProvider.overrideWithValue(operations)],
    );
    container.read(initProvider.notifier).value = true;
    container.read(runTimeProvider.notifier).value = 1;
    operations.stopError = StateError('native stop failed');

    await expectLater(
      container.read(setupActionProvider.notifier).updateStatus(false),
      throwsStateError,
    );

    expect(operations.stopCalls, 1);
    expect(operations.resetCalls, 0);
    expect(container.read(runTimeProvider), 1);
    expect(container.read(isStartingProvider), isFalse);
  });

  test(
    'successful stop refreshes the direct IP once after transition readiness',
    () async {
      container.dispose();
      final routes = <bool>[];
      container = ProviderContainer(
        overrides: [
          setupCoreOperationsProvider.overrideWithValue(operations),
          initProvider.overrideWithBuild((_, _) => true),
          runTimeProvider.overrideWithBuild((_, _) => 1),
          coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
          ipCheckForegroundGateProvider.overrideWithValue(() => true),
          dashboardStateProvider.overrideWithValue(
            const DashboardState(
              dashboardWidgets: [DashboardWidget.networkDetection],
              contentWidth: 400,
            ),
          ),
          ipInfoLoaderProvider.overrideWithValue((_, useLocalProxy) async {
            expect(container.read(isStartingProvider), isFalse);
            expect(container.read(isStartProvider), isFalse);
            routes.add(useLocalProxy);
            return Result.success(
              const IpInfo(ip: '1.1.1.1', countryCode: 'US'),
            );
          }),
        ],
      );
      final listener = container.listen(checkIpProvider, (previous, next) {
        if (previous != next && next.a && next.c) {
          container.read(networkDetectionProvider.notifier).startCheck();
        }
      });
      addTearDown(listener.close);

      final stopped = await container
          .read(setupActionProvider.notifier)
          .updateStatus(false);
      await Future<void>.delayed(Duration.zero);

      expect(stopped, isTrue);
      expect(container.read(checkIpNumProvider), 1);
      expect(routes, [false]);

      await Future<void>.delayed(
        commonDuration + const Duration(milliseconds: 50),
      );
      expect(routes, [false]);
    },
  );

  test(
    'background stop waits for resume before refreshing direct IP',
    () async {
      container.dispose();
      var foreground = false;
      final routes = <bool>[];
      container = ProviderContainer(
        overrides: [
          setupCoreOperationsProvider.overrideWithValue(operations),
          initProvider.overrideWithBuild((_, _) => true),
          runTimeProvider.overrideWithBuild((_, _) => 1),
          coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
          ipCheckForegroundGateProvider.overrideWithValue(() => foreground),
          dashboardStateProvider.overrideWithValue(
            const DashboardState(
              dashboardWidgets: [DashboardWidget.networkDetection],
              contentWidth: 400,
            ),
          ),
          ipInfoLoaderProvider.overrideWithValue((_, useLocalProxy) async {
            routes.add(useLocalProxy);
            return Result.success(
              const IpInfo(ip: '1.1.1.1', countryCode: 'US'),
            );
          }),
        ],
      );

      final stopped = await container
          .read(setupActionProvider.notifier)
          .updateStatus(false);
      await Future<void>.delayed(Duration.zero);

      expect(stopped, isTrue);
      expect(routes, isEmpty);

      foreground = true;
      container.read(setupActionProvider.notifier).tryCheckIp();
      await Future<void>.delayed(Duration.zero);

      expect(routes, [false]);
      expect(container.read(checkIpNumProvider), 2);
    },
  );
}
