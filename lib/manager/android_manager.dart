import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@visibleForTesting
class SharedStateSyncCoordinator<T> {
  final Future<String> Function(T state) sync;
  final void Function(Object error, StackTrace stackTrace) onError;

  T? _latest;
  int _generation = 0;
  int _appliedGeneration = -1;
  int? _blockedGeneration;
  Future<void>? _worker;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  SharedStateSyncCoordinator({required this.sync, required this.onError});

  void update(T state) {
    if (_disposed) {
      return;
    }
    _latest = state;
    _generation++;
    _blockedGeneration = null;
    _ensureWorker();
  }

  void _ensureWorker() {
    if (_disposed ||
        _worker != null ||
        _appliedGeneration == _generation ||
        _blockedGeneration == _generation) {
      return;
    }
    late final Future<void> worker;
    worker = Future<void>.microtask(_drain).whenComplete(() {
      if (!identical(_worker, worker)) {
        return;
      }
      _worker = null;
      _ensureWorker();
    });
    _worker = worker;
  }

  Future<void> _drain() async {
    while (!_disposed && _appliedGeneration != _generation) {
      final generation = _generation;
      final state = _latest as T;
      try {
        final message = await sync(state);
        if (message.isNotEmpty) {
          throw StateError(message);
        }
        if (_disposed) {
          return;
        }
        if (generation != _generation) {
          continue;
        }
        _appliedGeneration = generation;
      } catch (error, stackTrace) {
        _report(error, stackTrace);
        if (generation == _generation) {
          _blockedGeneration = generation;
          return;
        }
      }
    }
  }

  Future<void> settle() async {
    while (true) {
      final worker = _worker;
      if (worker == null) {
        return;
      }
      await worker;
    }
  }

  Future<void> dispose() {
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    _disposed = true;
    _generation++;
    await _worker;
  }

  void _report(Object error, StackTrace stackTrace) {
    try {
      onError(error, stackTrace);
    } catch (handlerError, handlerStackTrace) {
      commonPrint.log(
        'Shared-state sync error handler failed: '
        '$handlerError\n$handlerStackTrace',
        logLevel: LogLevel.error,
      );
    }
  }
}

class AndroidManager extends ConsumerStatefulWidget {
  final Widget child;

  const AndroidManager({super.key, required this.child});

  @override
  ConsumerState<AndroidManager> createState() => _AndroidContainerState();
}

class _AndroidContainerState extends ConsumerState<AndroidManager>
    with ServiceListener {
  late final SharedStateSyncCoordinator<SharedState> _stateSync;

  @override
  void initState() {
    super.initState();
    _stateSync = SharedStateSyncCoordinator<SharedState>(
      sync: (state) async {
        final currentService = service;
        if (currentService == null) {
          throw StateError('Android core service is unavailable');
        }
        return currentService.syncState(state);
      },
      onError: (error, stackTrace) {
        commonPrint.log(
          'Failed to sync Android shared state: $error\n$stackTrace',
          logLevel: LogLevel.warning,
        );
        globalState.showNotifier(error.toString());
      },
    );
    ref.listenManual(appSettingProvider.select((state) => state.hidden), (
      prev,
      next,
    ) {
      app?.updateExcludeFromRecents(next);
    }, fireImmediately: true);
    ref.listenManual(sharedStateProvider, (prev, next) {
      if (prev != next) {
        debouncer.call(FunctionTag.saveSharedFile, () async {
          await ref.read(sharedStatePersisterProvider)(next);
        }, duration: const Duration(seconds: 1));
        if (prev?.needSyncSharedState != next.needSyncSharedState) {
          _stateSync.update(next.needSyncSharedState);
        }
      }
    });
    service?.addListener(this);
  }

  @override
  void dispose() {
    service?.removeListener(this);
    unawaited(_stateSync.dispose());
    super.dispose();
  }

  @override
  void onServiceEvent(CoreEvent event) {
    coreEventManager.sendEvent(event);
    super.onServiceEvent(event);
  }

  @override
  void onServiceCrash(String message) {
    coreEventManager.sendEvent(
      CoreEvent(type: CoreEventType.crash, data: message),
    );
    super.onServiceCrash(message);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
