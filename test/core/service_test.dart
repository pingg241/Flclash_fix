import 'dart:async';

import 'package:fl_clash/core/service.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:test/test.dart';

void main() {
  test('process exit is authoritative when kill reports false', () async {
    final result = await terminateCoreProcess(
      terminate: () => false,
      exitCode: Future<int>.value(0),
    );

    expect(result.killAccepted, isFalse);
    expect(result.exited, isTrue);
  });

  test('process termination reports timeout without claiming exit', () async {
    final result = await terminateCoreProcess(
      terminate: () => true,
      exitCode: Completer<int>().future,
      timeout: const Duration(milliseconds: 10),
    );

    expect(result.killAccepted, isTrue);
    expect(result.exited, isFalse);
  });

  test('process exit wait never reports a timeout as success', () async {
    expect(
      await waitForCoreProcessExit(
        exitCode: Completer<int>().future,
        timeout: const Duration(milliseconds: 10),
      ),
      isFalse,
    );
    expect(
      await waitForCoreProcessExit(exitCode: Future<int>.value(0)),
      isTrue,
    );
  });

  test(
    'graceful rejection succeeds after confirmed fallback shutdown',
    () async {
      final result = await stopCoreProcess(
        gracefulShutdown: () async => false,
        terminate: () async => true,
        exitCode: Future<int>.value(0),
        wasConnected: true,
        disconnected: Future<void>.value(),
        exitTimeout: const Duration(milliseconds: 10),
        disconnectTimeout: const Duration(milliseconds: 10),
      );

      expect(result.graceful, isFalse);
      expect(result.exited, isTrue);
      expect(result.disconnectConfirmed, isTrue);
      expect(result.confirmed, isTrue);
    },
  );

  test('failed fallback never claims that the core exited', () async {
    final result = await stopCoreProcess(
      gracefulShutdown: () async => false,
      terminate: () async => false,
      exitCode: Completer<int>().future,
      wasConnected: true,
      disconnected: Future<void>.value(),
      exitTimeout: const Duration(milliseconds: 10),
      disconnectTimeout: const Duration(milliseconds: 10),
    );

    expect(result.terminationAccepted, isFalse);
    expect(result.exited, isFalse);
    expect(result.confirmed, isFalse);
  });

  test(
    'disconnect timeout prevents shutdown confirmation after exit',
    () async {
      final result = await stopCoreProcess(
        gracefulShutdown: () async => false,
        terminate: () async => true,
        exitCode: Future<int>.value(0),
        wasConnected: true,
        disconnected: Completer<void>().future,
        exitTimeout: const Duration(milliseconds: 10),
        disconnectTimeout: const Duration(milliseconds: 10),
      );

      expect(result.exited, isTrue);
      expect(result.disconnectConfirmed, isFalse);
      expect(result.confirmed, isFalse);
    },
  );

  test('helper rejection fails shutdown immediately', () async {
    final stopped = await stopHelperCore(
      stop: () async => false,
      wasConnected: true,
      disconnected: Completer<void>().future,
    );

    expect(stopped, isFalse);
  });

  test('helper shutdown requires a real disconnect when connected', () async {
    final stopped = await stopHelperCore(
      stop: () async => true,
      wasConnected: true,
      disconnected: Completer<void>().future,
      timeout: const Duration(milliseconds: 10),
    );

    expect(stopped, isFalse);
  });

  test('helper shutdown succeeds after confirmed disconnect', () async {
    final stopped = await stopHelperCore(
      stop: () async => true,
      wasConnected: true,
      disconnected: Future<void>.value(),
    );

    expect(stopped, isTrue);
  });

  test(
    'pending requests are cleared exactly once across repeated cleanup',
    () async {
      final completer = Completer<String?>();
      final pending = <String, Completer>{'getConfig#request': completer};
      final expectation = expectLater(
        completer.future,
        throwsA(
          isA<CoreInvocationException>().having(
            (error) => error.failure,
            'failure',
            CoreInvocationFailure.disconnected,
          ),
        ),
      );

      clearPendingCoreResults(pending);
      clearPendingCoreResults(pending);

      await expectation;
      expect(pending, isEmpty);
    },
  );

  test('response timeout fails and removes the pending request', () async {
    const id = 'setupConfig#request';
    final completer = Completer<String?>();
    final pending = <String, Completer>{id: completer};

    await expectLater(
      waitForCoreResult<String>(
        id: id,
        method: ActionMethod.setupConfig,
        completer: completer,
        pendingResults: pending,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(
        isA<CoreInvocationException>().having(
          (error) => error.failure,
          'failure',
          CoreInvocationFailure.timeout,
        ),
      ),
    );
    expect(pending, isEmpty);
  });

  test('successful responses complete and remove pending requests', () async {
    final completer = Completer<String>();
    final pending = <String, Completer>{'request': completer};

    await dispatchCoreResult(
      result: const ActionResult(
        id: 'request',
        method: ActionMethod.getMemory,
        data: '42',
      ),
      pendingResults: pending,
      parseResult: (result) async => result.data,
      sendEvent: (_) {},
    );

    expect(await completer.future, '42');
    expect(pending, isEmpty);
  });

  test('response parsing errors fail and remove pending requests', () async {
    final completer = Completer<String>();
    final pending = <String, Completer>{'request': completer};
    final pendingExpectation = expectLater(completer.future, throwsStateError);

    final dispatchExpectation = expectLater(
      dispatchCoreResult(
        result: const ActionResult(
          id: 'request',
          method: ActionMethod.getMemory,
          data: 'invalid',
        ),
        pendingResults: pending,
        parseResult: (_) => throw StateError('invalid response'),
        sendEvent: (_) {},
      ),
      throwsStateError,
    );

    await Future.wait([pendingExpectation, dispatchExpectation]);
    expect(pending, isEmpty);
  });

  test('event dispatch errors do not leave a request pending', () async {
    final completer = Completer<String>();
    final pending = <String, Completer>{'request': completer};
    final pendingExpectation = expectLater(completer.future, throwsStateError);

    final dispatchExpectation = expectLater(
      dispatchCoreResult(
        result: const ActionResult(
          id: 'request',
          method: ActionMethod.message,
          data: {'type': 'log'},
        ),
        pendingResults: pending,
        parseResult: (_) async => 'ok',
        sendEvent: (_) => throw StateError('event failed'),
      ),
      throwsStateError,
    );

    await Future.wait([pendingExpectation, dispatchExpectation]);
    expect(pending, isEmpty);
  });
}
