import 'dart:async';

import 'package:fl_clash/manager/hotkey_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a late old registration is removed before applying the latest set',
    () async {
      final active = <String>{};
      final oldStarted = Completer<void>();
      final releaseOld = Completer<void>();
      var unregisterCount = 0;
      final coordinator = HotKeyUpdateCoordinator<String>(
        unregisterAll: () async {
          unregisterCount++;
          active.clear();
        },
        register: (item) async {
          if (item == 'old') {
            oldStarted.complete();
            await releaseOld.future;
          }
          active.add(item);
        },
        onError: (_, _) {},
      );

      coordinator.update(['old']);
      await oldStarted.future;
      coordinator.update(['new']);
      releaseOld.complete();
      await coordinator.settle();

      expect(unregisterCount, 2);
      expect(active, {'new'});
      await coordinator.dispose();
    },
  );

  test('rapid updates coalesce to the latest configuration', () async {
    final registered = <String>[];
    final coordinator = HotKeyUpdateCoordinator<String>(
      unregisterAll: () async => registered.clear(),
      register: (item) async => registered.add(item),
      onError: (_, _) {},
    );

    coordinator.update(['first']);
    coordinator.update(['second']);
    coordinator.update(['third']);
    await coordinator.settle();

    expect(registered, ['third']);
    await coordinator.dispose();
  });

  test('a failed registration does not block a later configuration', () async {
    final active = <String>{};
    final errors = <Object>[];
    final coordinator = HotKeyUpdateCoordinator<String>(
      unregisterAll: () async => active.clear(),
      register: (item) async {
        if (item == 'bad') {
          throw StateError('register failed');
        }
        active.add(item);
      },
      onError: (error, _) => errors.add(error),
    );

    coordinator.update(['partial', 'bad']);
    await coordinator.settle();
    expect(active, isEmpty);
    coordinator.update(['good']);
    await coordinator.settle();

    expect(errors, hasLength(1));
    expect(active, {'good'});
    await coordinator.dispose();
  });

  test(
    'dispose waits for in-flight registration and removes all hotkeys',
    () async {
      final active = <String>{};
      final started = Completer<void>();
      final release = Completer<void>();
      final coordinator = HotKeyUpdateCoordinator<String>(
        unregisterAll: () async => active.clear(),
        register: (item) async {
          started.complete();
          await release.future;
          active.add(item);
        },
        onError: (_, _) {},
      );

      coordinator.update(['old']);
      await started.future;
      final dispose = coordinator.dispose();
      coordinator.update(['ignored']);
      release.complete();
      await dispose;

      expect(active, isEmpty);
    },
  );

  test('hotkey action errors are reported without escaping', () async {
    final errors = <Object>[];

    await expectLater(
      handleHotKeyActionSafely(
        action: () => throw StateError('start failed'),
        onError: (error, _) => errors.add(error),
      ),
      completes,
    );

    expect(errors, hasLength(1));
  });
}
