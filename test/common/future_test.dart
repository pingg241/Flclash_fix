import 'dart:async';

import 'package:fl_clash/common/future.dart';
import 'package:test/test.dart';

void main() {
  test('withTimeout supports a nullable fallback result', () async {
    final result = await Completer<int?>().future.withTimeout(
      timeout: const Duration(milliseconds: 10),
      onTimeout: () => null,
    );

    expect(result, isNull);
  });

  test('withTimeout supports an asynchronous fallback', () async {
    final result = await Completer<int>().future.withTimeout(
      timeout: const Duration(milliseconds: 10),
      onTimeout: () async => 7,
    );

    expect(result, 7);
  });

  test('withTimeout throws when no fallback is provided', () async {
    await expectLater(
      Completer<int>().future.withTimeout(
        timeout: const Duration(milliseconds: 10),
        tag: 'pending request',
      ),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'message',
          contains('pending request timeout'),
        ),
      ),
    );
  });

  test('runAsyncSafely reports failures without rethrowing them', () async {
    final errors = <Object>[];

    await expectLater(
      runAsyncSafely(
        operation: () => throw StateError('failed'),
        onError: (error, _) => errors.add(error),
      ),
      completes,
    );

    expect(errors.single, isA<StateError>());
  });
}
