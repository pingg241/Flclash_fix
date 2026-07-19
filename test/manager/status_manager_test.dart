import 'package:fl_clash/manager/status_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('message action awaits success', () async {
    var completed = false;

    final result = await executeMessageAction(
      () async => completed = true,
      onError: (_, _) => fail('unexpected error'),
    );

    expect(result, isTrue);
    expect(completed, isTrue);
  });

  test('message action catches asynchronous errors', () async {
    Object? reported;

    final result = await executeMessageAction(
      () async => throw StateError('restart failed'),
      onError: (error, _) => reported = error,
    );

    expect(result, isFalse);
    expect(reported, isA<StateError>());
  });
}
