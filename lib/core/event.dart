import 'dart:async';
import 'dart:collection';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';

abstract mixin class CoreEventListener {
  FutureOr<void> onLog(Log log) {}

  FutureOr<void> onDelay(Delay delay) {}

  FutureOr<void> onRequest(TrackerInfo connection) {}

  FutureOr<void> onLoaded(String providerName) {}

  FutureOr<void> onCrash(String message) {}

  FutureOr<void> onGeoUpdate(
    String geoType,
    bool updating,
    bool skipped,
    String? error,
  ) {}
}

class CoreEventManager {
  final int maxPendingEvents;
  final int drainBatchSize;
  final Queue<CoreEvent> _pendingEvents = ListQueue<CoreEvent>();
  Completer<void>? _spaceAvailable;
  bool _drainScheduled = false;
  int _droppedEventCount = 0;

  CoreEventManager._() : maxPendingEvents = 256, drainBatchSize = 32;

  @visibleForTesting
  CoreEventManager.test({this.maxPendingEvents = 256, this.drainBatchSize = 32})
    : assert(maxPendingEvents > 0),
      assert(drainBatchSize > 0);

  static final CoreEventManager instance = CoreEventManager._();

  final ObserverList<CoreEventListener> _listeners =
      ObserverList<CoreEventListener>();

  bool get hasListeners {
    return _listeners.isNotEmpty;
  }

  @visibleForTesting
  int get pendingEventCount => _pendingEvents.length;

  @visibleForTesting
  int get droppedEventCount => _droppedEventCount;

  Future<void> sendEvent(CoreEvent event) async {
    if (_isHighFrequency(event.type)) {
      if (_pendingEvents.length >= maxPendingEvents &&
          !_dropOldestHighFrequency()) {
        _droppedEventCount++;
        return;
      }
    } else {
      while (_pendingEvents.length >= maxPendingEvents) {
        if (_dropOldestHighFrequency()) {
          break;
        }
        final spaceAvailable = _spaceAvailable ??= Completer<void>();
        await spaceAvailable.future;
      }
    }
    _pendingEvents.addLast(event);
    _scheduleDrain();
  }

  bool _dropOldestHighFrequency() {
    if (_pendingEvents.isEmpty) {
      return false;
    }
    final retained = ListQueue<CoreEvent>();
    var dropped = false;
    while (_pendingEvents.isNotEmpty) {
      final event = _pendingEvents.removeFirst();
      if (!dropped && _isHighFrequency(event.type)) {
        dropped = true;
        _droppedEventCount++;
        continue;
      }
      retained.addLast(event);
    }
    _pendingEvents.addAll(retained);
    return dropped;
  }

  bool _isHighFrequency(CoreEventType type) {
    return switch (type) {
      CoreEventType.log || CoreEventType.delay || CoreEventType.request => true,
      CoreEventType.loaded ||
      CoreEventType.crash ||
      CoreEventType.geoUpdate => false,
    };
  }

  void _scheduleDrain() {
    if (_drainScheduled) {
      return;
    }
    _drainScheduled = true;
    scheduleMicrotask(() async => _drain());
  }

  Future<void> _drain() async {
    var count = 0;
    while (_pendingEvents.isNotEmpty && count < drainBatchSize) {
      final event = _pendingEvents.removeFirst();
      _notifySpaceAvailable();
      await _dispatch(event);
      count++;
    }
    _drainScheduled = false;
    if (_pendingEvents.isNotEmpty) {
      _scheduleDrain();
    }
  }

  void _notifySpaceAvailable() {
    final spaceAvailable = _spaceAvailable;
    _spaceAvailable = null;
    if (spaceAvailable != null && !spaceAvailable.isCompleted) {
      spaceAvailable.complete();
    }
  }

  Future<void> _dispatch(CoreEvent event) async {
    for (final CoreEventListener listener in List<CoreEventListener>.of(
      _listeners,
    )) {
      try {
        switch (event.type) {
          case CoreEventType.log:
            await listener.onLog(Log.fromJson(event.data));
            break;
          case CoreEventType.delay:
            await listener.onDelay(Delay.fromJson(event.data));
            break;
          case CoreEventType.request:
            await listener.onRequest(TrackerInfo.fromJson(event.data));
            break;
          case CoreEventType.loaded:
            await listener.onLoaded(event.data);
            break;
          case CoreEventType.crash:
            await listener.onCrash(event.data);
            break;
          case CoreEventType.geoUpdate:
            final data = event.data as Map<String, dynamic>;
            await listener.onGeoUpdate(
              data['type'] as String,
              data['updating'] as bool,
              data['skipped'] as bool? ?? false,
              data['error'] as String?,
            );
            break;
        }
      } catch (_) {
        // Isolate listener failures so one bad handler cannot stop the rest.
      }
    }
  }

  void addListener(CoreEventListener listener) {
    _listeners.add(listener);
  }

  void removeListener(CoreEventListener listener) {
    _listeners.remove(listener);
  }
}

final coreEventManager = CoreEventManager.instance;
