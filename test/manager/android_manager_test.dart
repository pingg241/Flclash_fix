import 'dart:async';

import 'package:fl_clash/manager/android_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rapid shared-state changes coalesce to the latest value', () async {
    final synced = <String>[];
    final coordinator = SharedStateSyncCoordinator<String>(
      sync: (state) async {
        synced.add(state);
        return '';
      },
      onError: (_, _) {},
    );

    coordinator.update('first');
    coordinator.update('second');
    coordinator.update('latest');
    await coordinator.settle();

    expect(synced, ['latest']);
    await coordinator.dispose();
  });

  test(
    'an in-flight old sync finishes before the latest sync starts',
    () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final synced = <String>[];
      var active = 0;
      var maxActive = 0;
      final coordinator = SharedStateSyncCoordinator<String>(
        sync: (state) async {
          active++;
          if (active > maxActive) {
            maxActive = active;
          }
          try {
            if (state == 'old') {
              firstStarted.complete();
              await releaseFirst.future;
            }
            synced.add(state);
            return '';
          } finally {
            active--;
          }
        },
        onError: (_, _) {},
      );

      coordinator.update('old');
      await firstStarted.future;
      coordinator.update('latest');
      releaseFirst.complete();
      await coordinator.settle();

      expect(synced, ['old', 'latest']);
      expect(maxActive, 1);
      await coordinator.dispose();
    },
  );

  test('sync errors are reported and a later state can recover', () async {
    final errors = <Object>[];
    final synced = <String>[];
    final coordinator = SharedStateSyncCoordinator<String>(
      sync: (state) async {
        if (state == 'bad') {
          return 'native sync rejected the state';
        }
        synced.add(state);
        return '';
      },
      onError: (error, _) => errors.add(error),
    );

    coordinator.update('bad');
    await coordinator.settle();
    coordinator.update('good');
    await coordinator.settle();

    expect(errors.single, isA<StateError>());
    expect(synced, ['good']);
    await coordinator.dispose();
  });

  test('dispose blocks new syncs and waits for the active sync', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final synced = <String>[];
    final coordinator = SharedStateSyncCoordinator<String>(
      sync: (state) async {
        started.complete();
        await release.future;
        synced.add(state);
        return '';
      },
      onError: (_, _) {},
    );

    coordinator.update('active');
    await started.future;
    final dispose = coordinator.dispose();
    coordinator.update('ignored');
    release.complete();
    await dispose;

    expect(synced, ['active']);
  });
}
