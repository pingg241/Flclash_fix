import 'dart:async';

import 'package:fl_clash/common/function.dart';
import 'package:test/test.dart';

void main() {
  group('Debouncer', () {
    test(
      'runs only the latest operation and completes the superseded call',
      () async {
        final debouncer = Debouncer();
        var value = 0;

        final first = debouncer.callAsync<int>(
          'tag',
          () => value = 1,
          duration: const Duration(milliseconds: 20),
        );
        final second = debouncer.callAsync<int>('tag', () async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return value = 2;
        }, duration: const Duration(milliseconds: 5));

        expect(await first, isNull);
        expect(await second, 2);
        expect(value, 2);
      },
    );

    test('awaits async operations and propagates their errors', () async {
      final debouncer = Debouncer();

      final future = debouncer.callAsync<void>('tag', () async {
        await Future<void>.delayed(Duration.zero);
        throw StateError('failed');
      }, duration: Duration.zero);

      await expectLater(future, throwsStateError);
    });
  });

  group('Throttler', () {
    test('callAsync waits for a trailing async operation', () async {
      final throttler = Throttler();
      final completed = Completer<void>();

      final future = throttler.callAsync('tag', () async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        completed.complete();
      }, duration: const Duration(milliseconds: 5));

      expect(completed.isCompleted, isFalse);
      expect(await future, isFalse);
      expect(completed.isCompleted, isTrue);
    });

    test('callAsync propagates async errors', () async {
      final throttler = Throttler();

      final future = throttler.callAsync(
        'tag',
        () async => throw StateError('failed'),
        duration: Duration.zero,
      );

      await expectLater(future, throwsStateError);
    });

    test('cancel completes a pending call without running it', () async {
      final throttler = Throttler();
      var called = false;
      final future = throttler.callAsync(
        'tag',
        () => called = true,
        duration: const Duration(seconds: 1),
      );

      throttler.cancel('tag');

      expect(await future, isFalse);
      expect(called, isFalse);
    });
  });

  group('AsyncPeriodicTask', () {
    test('continues after an error and stops without reviving', () async {
      final secondRun = Completer<void>();
      var attempts = 0;
      final task = AsyncPeriodicTask(
        interval: const Duration(milliseconds: 5),
        task: () {
          attempts++;
          if (attempts == 1) {
            throw StateError('first run failed');
          }
          secondRun.complete();
        },
        onError: (_, _) {},
      );

      task.start();
      await secondRun.future.timeout(const Duration(seconds: 1));
      task.stop();
      final attemptsAfterStop = attempts;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(attemptsAfterStop, 2);
      expect(attempts, attemptsAfterStop);
      expect(task.isRunning, isFalse);
    });

    test('stop during an in-flight task prevents rescheduling', () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var attempts = 0;
      final task = AsyncPeriodicTask(
        interval: const Duration(milliseconds: 5),
        task: () async {
          attempts++;
          started.complete();
          await release.future;
        },
      );

      task.start();
      await started.future.timeout(const Duration(seconds: 1));
      task.stop();
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(attempts, 1);
      expect(task.isRunning, isFalse);
    });
  });

  group('retry', () {
    test('returns immediately when first result does not need retry', () async {
      var attempts = 0;

      final result = await retry(
        task: () async {
          attempts++;
          return 'done';
        },
        retryIf: (res) => res != 'done',
        delay: Duration.zero,
      );

      expect(result, 'done');
      expect(attempts, 1);
    });

    test('retries until result no longer matches retry condition', () async {
      var attempts = 0;

      final result = await retry(
        task: () async {
          attempts++;
          return attempts < 3 ? 'pending' : 'done';
        },
        retryIf: (res) => res == 'pending',
        delay: Duration.zero,
        maxAttempts: 5,
      );

      expect(result, 'done');
      expect(attempts, 3);
    });

    test('returns last result when max attempts are exhausted', () async {
      var attempts = 0;

      final result = await retry(
        task: () async {
          attempts++;
          return false;
        },
        retryIf: (res) => res == false,
        delay: Duration.zero,
        maxAttempts: 3,
      );

      expect(result, false);
      expect(attempts, 3);
    });

    test('waits between retry attempts', () async {
      var attempts = 0;

      final future = retry(
        task: () async {
          attempts++;
          return attempts < 2 ? 'pending' : 'done';
        },
        retryIf: (res) => res == 'pending',
        delay: const Duration(milliseconds: 50),
        maxAttempts: 2,
      );

      await Future.delayed(const Duration(milliseconds: 10));
      expect(attempts, 1);

      final result = await future;

      expect(result, 'done');
      expect(attempts, 2);
    });
  });
}
