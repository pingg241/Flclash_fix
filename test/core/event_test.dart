import 'dart:async';

import 'package:fl_clash/core/event.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:test/test.dart';

void main() {
  test('high-frequency flood stays within the configured memory bound', () {
    final manager = CoreEventManager.test(maxPendingEvents: 4);

    for (var index = 0; index < 1000; index++) {
      unawaited(manager.sendEvent(_logEvent('$index')));
    }

    expect(manager.pendingEventCount, 4);
    expect(manager.droppedEventCount, 996);
  });

  test('high-frequency overflow keeps the newest events', () async {
    final manager = CoreEventManager.test(maxPendingEvents: 3);
    final listener = _RecordingListener();
    manager.addListener(listener);

    final sends = [
      for (var index = 0; index < 5; index++)
        manager.sendEvent(_logEvent('$index')),
    ];
    await Future.wait(sends);
    await Future<void>.delayed(Duration.zero);

    expect(listener.logs, ['2', '3', '4']);
    expect(manager.droppedEventCount, 2);
  });

  test(
    'control events displace high-frequency events instead of dropping',
    () async {
      final manager = CoreEventManager.test(maxPendingEvents: 2);
      final listener = _RecordingListener();
      manager.addListener(listener);

      final sends = [
        manager.sendEvent(_logEvent('old')),
        manager.sendEvent(_logEvent('new')),
        manager.sendEvent(
          const CoreEvent(type: CoreEventType.crash, data: 'crash'),
        ),
      ];
      await Future.wait(sends);
      await Future<void>.delayed(Duration.zero);

      expect(listener.logs, ['new']);
      expect(listener.crashes, ['crash']);
      expect(manager.droppedEventCount, 1);
    },
  );

  test(
    'control-only overflow waits for bounded queue space and preserves order',
    () async {
      final manager = CoreEventManager.test(
        maxPendingEvents: 2,
        drainBatchSize: 1,
      );
      final listener = _RecordingListener();
      manager.addListener(listener);

      final first = manager.sendEvent(
        const CoreEvent(type: CoreEventType.crash, data: 'first'),
      );
      final second = manager.sendEvent(
        const CoreEvent(type: CoreEventType.crash, data: 'second'),
      );
      var thirdAccepted = false;
      final third = manager
          .sendEvent(const CoreEvent(type: CoreEventType.crash, data: 'third'))
          .then((_) => thirdAccepted = true);

      expect(manager.pendingEventCount, 2);
      expect(thirdAccepted, isFalse);

      await Future.wait([first, second, third]);
      await Future<void>.delayed(Duration.zero);

      expect(listener.crashes, ['first', 'second', 'third']);
      expect(manager.droppedEventCount, 0);
    },
  );

  test('async listeners are awaited and events remain serialized', () async {
    final manager = CoreEventManager.test();
    final releaseFirst = Completer<void>();
    final finished = Completer<void>();
    final calls = <String>[];
    manager.addListener(
      _AsyncCrashListener((message) async {
        calls.add('start:$message');
        if (message == 'first') {
          await releaseFirst.future;
        }
        calls.add('end:$message');
        if (message == 'second') {
          finished.complete();
        }
      }),
    );

    await manager.sendEvent(
      const CoreEvent(type: CoreEventType.crash, data: 'first'),
    );
    await manager.sendEvent(
      const CoreEvent(type: CoreEventType.crash, data: 'second'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['start:first']);

    releaseFirst.complete();
    await finished.future;
    expect(calls, ['start:first', 'end:first', 'start:second', 'end:second']);
  });

  test('async listener errors are isolated from later listeners', () async {
    final manager = CoreEventManager.test();
    final received = Completer<void>();
    manager.addListener(
      _AsyncCrashListener((_) async => throw StateError('listener failed')),
    );
    manager.addListener(
      _AsyncCrashListener((_) async {
        received.complete();
      }),
    );

    await manager.sendEvent(
      const CoreEvent(type: CoreEventType.crash, data: 'crash'),
    );

    await received.future;
  });
}

CoreEvent _logEvent(String payload) {
  return CoreEvent(
    type: CoreEventType.log,
    data: <String, dynamic>{'Payload': payload},
  );
}

class _RecordingListener with CoreEventListener {
  final List<String> logs = [];
  final List<String> crashes = [];

  @override
  void onLog(Log log) {
    logs.add(log.payload);
  }

  @override
  void onCrash(String message) {
    crashes.add(message);
  }
}

class _AsyncCrashListener with CoreEventListener {
  final Future<void> Function(String message) callback;

  _AsyncCrashListener(this.callback);

  @override
  Future<void> onCrash(String message) => callback(message);
}
