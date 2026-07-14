import 'dart:async';

import 'package:fl_clash/providers/actions/system_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('visible window is hidden and awaited', () async {
    final events = <String>[];

    await updateWindowVisibility(
      isVisible: () async => true,
      show: () async => events.add('show'),
      hide: () async {
        await Future<void>.delayed(Duration.zero);
        events.add('hide');
      },
    );

    expect(events, ['hide']);
  });

  test('hidden window is shown and failures propagate', () async {
    await expectLater(
      updateWindowVisibility(
        isVisible: () async => false,
        show: () => throw StateError('show failed'),
        hide: () async {},
      ),
      throwsStateError,
    );
  });

  test('exit retries core shutdown and exits only after success', () async {
    var destroyCalls = 0;
    var exitCalls = 0;

    await completeExitAfterCoreShutdown(
      destroyCore: () async {
        destroyCalls++;
        if (destroyCalls < 3) {
          throw StateError('shutdown not confirmed');
        }
      },
      exitApplication: () async => exitCalls++,
      retryDelay: Duration.zero,
    );

    expect(destroyCalls, 3);
    expect(exitCalls, 1);
  });

  test('exit is withheld when core shutdown remains unconfirmed', () async {
    var destroyCalls = 0;
    var exitCalls = 0;

    await expectLater(
      completeExitAfterCoreShutdown(
        destroyCore: () async {
          destroyCalls++;
          throw StateError('shutdown not confirmed');
        },
        exitApplication: () async => exitCalls++,
        retryDelay: Duration.zero,
      ),
      throwsStateError,
    );

    expect(destroyCalls, 3);
    expect(exitCalls, 0);
  });

  test('hung core shutdown is bounded and cannot trigger exit', () async {
    var exitCalls = 0;
    final never = Completer<void>();
    final startedAt = DateTime.now();

    await expectLater(
      completeExitAfterCoreShutdown(
        destroyCore: () => never.future,
        exitApplication: () async => exitCalls++,
        maxDestroyAttempts: 2,
        destroyTimeout: const Duration(milliseconds: 20),
        retryDelay: Duration.zero,
      ),
      throwsStateError,
    );

    expect(
      DateTime.now().difference(startedAt),
      lessThan(const Duration(seconds: 1)),
    );
    expect(exitCalls, 0);
  });
}
