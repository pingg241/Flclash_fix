import 'dart:async';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('$packageName/service');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = Service();

  tearDown(() {
    service.lifecycleTimeout = const Duration(seconds: 30);
    service.lifecycleCancellationTimeout = const Duration(seconds: 30);
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('shutdown treats a missing native result as failure', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);

    expect(await service.shutdown(), isFalse);
  });

  test('init rejects a missing native result', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);

    await expectLater(service.init(), throwsStateError);
  });

  test('start timeout waits for matching native cancellation', () async {
    service.lifecycleTimeout = const Duration(milliseconds: 10);
    String? startOperationId;
    String? cancelledOperationId;
    messenger.setMockMethodCallHandler(channel, (call) {
      final arguments = call.arguments as Map<Object?, Object?>?;
      if (call.method == 'start') {
        startOperationId = arguments?['operationId'] as String?;
        return Completer<bool>().future;
      }
      if (call.method == 'cancelStart') {
        cancelledOperationId = arguments?['operationId'] as String?;
        return Future<bool>.value(true);
      }
      return Future<Object?>.value();
    });

    await expectLater(service.start(), throwsA(isA<TimeoutException>()));
    expect(startOperationId, isNotEmpty);
    expect(cancelledOperationId, startOperationId);
  });

  test('start timeout rejects an unconfirmed cancellation', () async {
    service.lifecycleTimeout = const Duration(milliseconds: 10);
    messenger.setMockMethodCallHandler(channel, (call) {
      if (call.method == 'start') {
        return Completer<bool>().future;
      }
      return Future<bool>.value(false);
    });

    await expectLater(service.start(), throwsStateError);
  });

  test('native lifecycle exceptions are propagated', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'start-failed');
    });

    await expectLater(
      service.start(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'start-failed',
        ),
      ),
    );
  });
}
