import 'dart:async';

import 'package:fl_clash/common/resource_limits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('collectBytesWithLimit', () {
    test('accepts input exactly at the limit', () async {
      final bytes = await collectBytesWithLimit(
        Stream.fromIterable([
          [1, 2],
          [3, 4],
        ]),
        maxBytes: 4,
        inputName: 'Test input',
      );

      expect(bytes, [1, 2, 3, 4]);
    });

    test('rejects chunked input as soon as it exceeds the limit', () async {
      var limitCallbackCalled = false;

      await expectLater(
        collectBytesWithLimit(
          Stream.fromIterable([
            [1, 2],
            [3, 4, 5],
          ]),
          maxBytes: 4,
          inputName: 'Test input',
          onLimitExceeded: () {
            limitCallbackCalled = true;
          },
        ),
        throwsA(isA<InputTooLargeException>()),
      );
      expect(limitCallbackCalled, true);
    });
  });
}
