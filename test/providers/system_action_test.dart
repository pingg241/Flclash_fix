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

  test('accepted shutdown retries cleanup and exits after success', () async {
    var destroyCalls = 0;
    var exitCalls = 0;

    await completeExitAfterCoreShutdown(
      shutdownCore: () async => true,
      destroyCore: () async {
        destroyCalls++;
        if (destroyCalls < 3) {
          throw StateError('shutdown not confirmed');
        }
        return null;
      },
      exitApplication: () async => exitCalls++,
      retryDelay: Duration.zero,
    );

    expect(destroyCalls, 3);
    expect(exitCalls, 1);
  });

  test('exit is withheld when core shutdown is not accepted', () async {
    var destroyCalls = 0;
    var exitCalls = 0;

    await expectLater(
      completeExitAfterCoreShutdown(
        shutdownCore: () async => false,
        destroyCore: () async {
          destroyCalls++;
          return null;
        },
        exitApplication: () async => exitCalls++,
        retryDelay: Duration.zero,
      ),
      throwsStateError,
    );

    expect(destroyCalls, 0);
    expect(exitCalls, 0);
  });

  test('shutdown exception is propagated before cleanup or exit', () async {
    var destroyCalls = 0;
    var exitCalls = 0;

    await expectLater(
      completeExitAfterCoreShutdown(
        shutdownCore: () async => throw StateError('shutdown failed'),
        destroyCore: () async => destroyCalls++,
        exitApplication: () async => exitCalls++,
      ),
      throwsStateError,
    );

    expect(destroyCalls, 0);
    expect(exitCalls, 0);
  });

  test('cleanup false is reported but cannot block an accepted exit', () async {
    var exitCalls = 0;
    Object? reported;

    await completeExitAfterCoreShutdown(
      shutdownCore: () async => true,
      destroyCore: () async => false,
      exitApplication: () async => exitCalls++,
      onDestroyFailure: (error, _) => reported = error,
      maxDestroyAttempts: 2,
      retryDelay: Duration.zero,
    );

    expect(reported, isA<StateError>());
    expect(exitCalls, 1);
  });

  test('cleanup exception is reported but exits exactly once', () async {
    var exitCalls = 0;
    Object? reported;

    await completeExitAfterCoreShutdown(
      shutdownCore: () async => true,
      destroyCore: () async => throw StateError('cleanup failed'),
      exitApplication: () async => exitCalls++,
      onDestroyFailure: (error, _) => reported = error,
      maxDestroyAttempts: 2,
      retryDelay: Duration.zero,
    );

    expect(reported, isA<StateError>());
    expect(exitCalls, 1);
  });

  test('hung cleanup is bounded and exits exactly once', () async {
    var exitCalls = 0;
    Object? reported;
    final never = Completer<void>();
    final startedAt = DateTime.now();

    await completeExitAfterCoreShutdown(
      shutdownCore: () async => true,
      destroyCore: () => never.future,
      exitApplication: () async => exitCalls++,
      onDestroyFailure: (error, _) => reported = error,
      maxDestroyAttempts: 2,
      destroyTimeout: const Duration(milliseconds: 20),
      retryDelay: Duration.zero,
    );

    expect(
      DateTime.now().difference(startedAt),
      lessThan(const Duration(seconds: 1)),
    );
    expect(reported, isA<StateError>());
    expect(exitCalls, 1);
  });
}
