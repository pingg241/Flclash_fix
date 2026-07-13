import 'dart:async';

import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/manager/app_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('suspend false result is propagated', () async {
    await expectLater(
      performSuspendTransition(
        suspend: true,
        startListener: () async => true,
        stopListener: () async => false,
      ),
      throwsStateError,
    );
  });

  test('resume false result is propagated', () async {
    await expectLater(
      performSuspendTransition(
        suspend: false,
        startListener: () async => false,
        stopListener: () async => true,
      ),
      throwsStateError,
    );
  });

  test('confirmed suspend completes successfully', () async {
    await performSuspendTransition(
      suspend: true,
      startListener: () async => false,
      stopListener: () async => true,
    );
  });

  test('resume queues behind an in-flight suspend transition', () async {
    final suspendStarted = Completer<void>();
    final releaseSuspend = Completer<void>();
    final transitions = <String>[];

    final suspend = performSerializedSuspendTransition(
      suspend: true,
      startListener: () async => true,
      stopListener: () async {
        transitions.add('suspend');
        suspendStarted.complete();
        await releaseSuspend.future;
        return true;
      },
    );
    await suspendStarted.future;

    final resume = performSerializedSuspendTransition(
      suspend: false,
      startListener: () async {
        transitions.add('resume');
        return true;
      },
      stopListener: () async => true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(transitions, ['suspend']);

    releaseSuspend.complete();
    await Future.wait([suspend, resume]);
    expect(transitions, ['suspend', 'resume']);
  });

  test('dispose restore is queued after an in-flight DNS enable', () async {
    final enableStarted = Completer<void>();
    final releaseEnable = Completer<void>();
    final updates = <bool>[];
    final coordinator = DnsUpdateCoordinator((restore) async {
      updates.add(restore);
      if (!restore) {
        enableStarted.complete();
        await releaseEnable.future;
      }
    });

    final enable = coordinator.update(false);
    await enableStarted.future;
    final dispose = restoreDnsOnDispose(coordinator.update);
    await Future<void>.delayed(Duration.zero);
    expect(updates, [false]);

    releaseEnable.complete();
    await Future.wait([enable, dispose]);
    expect(updates, [false, true]);
  });
}
