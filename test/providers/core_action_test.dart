import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

class _FakeCoreLifecycleOperations implements CoreLifecycleOperations {
  @override
  bool isCompleted = false;
  String preloadResult = '';
  bool isInitResult = false;
  bool initResult = true;
  bool shutdownResult = true;
  bool completedAfterShutdown = false;
  Object? shutdownError;
  Object? preloadError;
  int preloadCalls = 0;
  int initCalls = 0;
  int shutdownCalls = 0;

  @override
  Future<bool> get isInit async => isInitResult;

  @override
  Future<bool> init(int version) async {
    initCalls++;
    return initResult;
  }

  @override
  Future<String> preload() async {
    preloadCalls++;
    final error = preloadError;
    if (error != null) {
      throw error;
    }
    return preloadResult;
  }

  @override
  Future<bool> shutdown(bool isUser) async {
    shutdownCalls++;
    isCompleted = completedAfterShutdown;
    final error = shutdownError;
    if (error != null) {
      throw error;
    }
    return shutdownResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeCoreLifecycleOperations operations;
  late ProviderContainer container;

  setUp(() {
    operations = _FakeCoreLifecycleOperations();
    container = ProviderContainer(
      overrides: [
        coreLifecycleOperationsProvider.overrideWithValue(operations),
      ],
    );
    container.read(versionProvider.notifier).value = 1;
    container.read(coreStatusProvider.notifier).value = CoreStatus.connected;
  });

  tearDown(() => container.dispose());

  test('shutdown false stops restart before reconnecting', () async {
    operations.shutdownResult = false;
    operations.completedAfterShutdown = true;

    await expectLater(
      container.read(coreActionProvider.notifier).ensureCoreConnected(),
      throwsStateError,
    );

    expect(operations.shutdownCalls, 1);
    expect(operations.preloadCalls, 0);
    expect(operations.initCalls, 0);
    expect(container.read(coreStatusProvider), CoreStatus.connected);
  });

  test('shutdown errors stop restart before reconnecting', () async {
    operations.shutdownError = StateError('shutdown failed');
    operations.completedAfterShutdown = true;

    await expectLater(
      container.read(coreActionProvider.notifier).ensureCoreConnected(),
      throwsStateError,
    );

    expect(operations.preloadCalls, 0);
    expect(operations.initCalls, 0);
    expect(container.read(coreStatusProvider), CoreStatus.connected);
  });

  test(
    'failed confirmation still reports a core that was cleaned up',
    () async {
      operations.shutdownResult = false;
      operations.completedAfterShutdown = false;

      await expectLater(
        container.read(coreActionProvider.notifier).ensureCoreConnected(),
        throwsStateError,
      );

      expect(operations.preloadCalls, 0);
      expect(container.read(coreStatusProvider), CoreStatus.disconnected);
    },
  );

  test('preload errors stop restart before initialization', () async {
    operations.preloadResult = 'preload failed';

    await expectLater(
      container.read(coreActionProvider.notifier).ensureCoreConnected(),
      throwsStateError,
    );

    expect(operations.preloadCalls, 1);
    expect(operations.initCalls, 0);
    expect(container.read(coreStatusProvider), CoreStatus.disconnected);
  });

  test('preload exceptions stop restart before initialization', () async {
    operations.preloadError = StateError('core disconnected');

    await expectLater(
      container.read(coreActionProvider.notifier).ensureCoreConnected(),
      throwsStateError,
    );

    expect(operations.preloadCalls, 1);
    expect(operations.initCalls, 0);
    expect(container.read(coreStatusProvider), CoreStatus.disconnected);
  });

  test('init false fails restart without reporting initialization', () async {
    operations.initResult = false;

    await expectLater(
      container.read(coreActionProvider.notifier).ensureCoreConnected(),
      throwsStateError,
    );

    expect(operations.preloadCalls, 1);
    expect(operations.initCalls, 1);
    expect(container.read(initProvider), isFalse);
  });

  test('confirmed shutdown reconnects and initializes once', () async {
    final restarted = await container
        .read(coreActionProvider.notifier)
        .ensureCoreConnected();

    expect(restarted, isTrue);
    expect(operations.shutdownCalls, 1);
    expect(operations.preloadCalls, 1);
    expect(operations.initCalls, 1);
    expect(container.read(coreStatusProvider), CoreStatus.connected);
  });
}
