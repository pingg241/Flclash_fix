import 'dart:async';

import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:test/test.dart';

class _NullCoreHandler extends CoreHandlerInterface {
  final Completer<void> _connected = Completer<void>()..complete();

  @override
  Completer<void> get completer => _connected;

  @override
  FutureOr<bool> destroy() => true;

  @override
  Future<T?> invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
  }) async => null;

  @override
  Future<String> preload() async => '';

  @override
  Future<bool> shutdown(bool isUser) async => true;
}

void main() {
  late _NullCoreHandler core;

  setUp(() {
    core = _NullCoreHandler();
  });

  final criticalCalls = <String, Future<Object?> Function(_NullCoreHandler)>{
    'validateConfig': (core) => core.validateConfig('/profile.yaml'),
    'getConfig': (core) => core.getConfig('/profile.yaml'),
    'setupConfig': (core) => core.setupConfig(
      const SetupParams(selectedMap: {}, testUrl: 'https://example.com'),
    ),
    'changeProxy': (core) => core.changeProxy(
      const ChangeProxyParams(groupName: 'group', proxyName: 'proxy'),
    ),
    'updateGeoData': (core) => core.updateGeoData('MMDB'),
    'sideLoadExternalProvider': (core) => core.sideLoadExternalProvider(
      providerName: 'provider',
      data: 'proxies: []',
    ),
    'updateExternalProvider': (core) => core.updateExternalProvider('provider'),
    'deleteFile': (core) => core.deleteFile('/profile.yaml'),
  };

  for (final entry in criticalCalls.entries) {
    test('${entry.key} rejects a missing core response', () async {
      await expectLater(
        entry.value(core),
        throwsA(
          isA<CoreInvocationException>().having(
            (error) => error.failure,
            'failure',
            CoreInvocationFailure.noResponse,
          ),
        ),
      );
    });
  }

  test('connection failures are exposed instead of mapped to false', () async {
    final disconnected = _DisconnectedCoreHandler();

    await expectLater(
      disconnected.isInit,
      throwsA(
        isA<CoreInvocationException>().having(
          (error) => error.failure,
          'failure',
          CoreInvocationFailure.unavailable,
        ),
      ),
    );
  });

  for (final method in <String, Future<void> Function(_NullCoreHandler)>{
    'resetTraffic': (core) => core.resetTraffic(),
    'startLog': (core) => core.startLog(),
    'stopLog': (core) => core.stopLog(),
  }.entries) {
    test('${method.key} exposes a missing core response', () async {
      await expectLater(
        method.value(core),
        throwsA(
          isA<CoreInvocationException>().having(
            (error) => error.failure,
            'failure',
            CoreInvocationFailure.noResponse,
          ),
        ),
      );
    });
  }

  for (final entry in <String, Future<Object?> Function(_ErrorCoreHandler)>{
    'updateGeoData': (core) => core.updateGeoData('MMDB'),
    'sideLoadExternalProvider': (core) => core.sideLoadExternalProvider(
      providerName: 'provider',
      data: 'proxies: []',
    ),
    'prepareTunHelper': (core) => core.prepareTunHelper(),
    'releaseTunHelper': (core) => core.releaseTunHelper(),
  }.entries) {
    test('${entry.key} propagates remote core errors', () async {
      await expectLater(
        entry.value(_ErrorCoreHandler()),
        throwsA(
          isA<CoreInvocationException>()
              .having(
                (error) => error.failure,
                'failure',
                CoreInvocationFailure.remoteError,
              )
              .having((error) => error.message, 'message', 'core rejected'),
        ),
      );
    });
  }

  test('getConfig preserves Result error compatibility', () async {
    final result = await _ErrorCoreHandler().getConfig('/profile.yaml');

    expect(result.isError, isTrue);
    expect(result.message, 'core rejected');
  });
}

class _DisconnectedCoreHandler extends _NullCoreHandler {
  final Completer<void> _disconnected = Completer<void>()
    ..completeError(StateError('disconnected'));

  @override
  Completer<void> get completer => _disconnected;
}

class _ErrorCoreHandler extends _NullCoreHandler {
  @override
  Future<T?> invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
  }) {
    return parasResult<T>(
      ActionResult(
        method: method,
        data: 'core rejected',
        code: ResultType.error,
      ),
    );
  }
}
