import 'package:fl_clash/views/proxies/delay_test_controller.dart';
import 'package:fl_clash/views/proxies/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDelayTestProgress', () {
    test('hides idle target count', () {
      expect(
        formatDelayTestProgress(running: false, done: 0, total: 4),
        isNull,
      );
    });

    test('shows accurate progress while a delay test is running', () {
      expect(formatDelayTestProgress(running: true, done: 0, total: 4), '0/4');
      expect(formatDelayTestProgress(running: true, done: 3, total: 4), '3/4');
    });

    test('allocates enough width for totals above three digits', () {
      expect(delayTestProgressMeasureText(4), '000/000');
      expect(delayTestProgressMeasureText(999), '000/000');
      expect(delayTestProgressMeasureText(1000), '0000/0000');
      expect(delayTestProgressMeasureText(12345), '00000/00000');
    });

    test('keeps the full batch total while the first group is running', () {
      expect(
        aggregateDelayTestProgress(
          batchTotal: 20,
          completedBeforeGroup: 0,
          groupDone: 0,
        ),
        (done: 0, total: 20),
      );
      expect(
        aggregateDelayTestProgress(
          batchTotal: 20,
          completedBeforeGroup: 4,
          groupDone: 2,
        ),
        (done: 6, total: 20),
      );
    });
  });

  group('delay-test batch ownership', () {
    setUp(invalidateDelayTests);
    tearDown(invalidateDelayTests);

    test('an invalidated batch cannot release a newer batch lock', () {
      final oldGeneration = beginDelayTestBatch();
      expect(isDelayTestBusy, isTrue);

      invalidateDelayTests();
      final newGeneration = beginDelayTestBatch();
      expect(newGeneration, isNot(oldGeneration));
      expect(isDelayTestBusy, isTrue);

      endDelayTestBatch(oldGeneration);
      expect(isDelayTestBusy, isTrue);

      endDelayTestBatch(newGeneration);
      expect(isDelayTestBusy, isFalse);
    });
  });
}
