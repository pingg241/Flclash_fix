import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

class _FakeSetupCoreOperations implements SetupCoreOperations {
  bool startResult = true;
  bool stopResult = true;
  Object? setupError;
  int preloadCalls = 0;
  int resetCalls = 0;

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
  Future<bool> stopListener() async => stopResult;
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
    'stop listener false preserves running state and returns false',
    () async {
      const runTime = 1;
      container.read(runTimeProvider.notifier).value = runTime;
      operations.stopResult = false;

      final stopped = await container
          .read(setupActionProvider.notifier)
          .updateStatus(false);

      expect(stopped, isFalse);
      expect(container.read(runTimeProvider), runTime);
      expect(operations.resetCalls, 0);
      expect(container.read(isStartingProvider), isFalse);
    },
  );
}
