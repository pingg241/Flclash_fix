import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/common.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

@visibleForTesting
class HotKeyUpdateCoordinator<T> {
  final Future<void> Function() unregisterAll;
  final Future<void> Function(T item) register;
  final void Function(Object error, StackTrace stackTrace) onError;

  List<T> _latest = const [];
  int _generation = 0;
  int _appliedGeneration = -1;
  int? _blockedGeneration;
  Future<void>? _worker;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  HotKeyUpdateCoordinator({
    required this.unregisterAll,
    required this.register,
    required this.onError,
  });

  void update(Iterable<T> items) {
    if (_disposed) {
      return;
    }
    _latest = List<T>.unmodifiable(items);
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
      final items = _latest;
      try {
        await unregisterAll();
        if (_disposed) {
          return;
        }
        if (generation != _generation) {
          continue;
        }
        for (final item in items) {
          await register(item);
          if (_disposed) {
            return;
          }
          if (generation != _generation) {
            break;
          }
        }
        if (generation != _generation) {
          continue;
        }
        _appliedGeneration = generation;
      } catch (error, stackTrace) {
        _report(error, stackTrace);
        if (generation == _generation) {
          _blockedGeneration = generation;
          try {
            await unregisterAll();
          } catch (cleanupError, cleanupStackTrace) {
            _report(cleanupError, cleanupStackTrace);
          }
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
    try {
      await unregisterAll();
    } catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }

  void _report(Object error, StackTrace stackTrace) {
    try {
      onError(error, stackTrace);
    } catch (handlerError, handlerStackTrace) {
      commonPrint.log(
        'Hotkey error handler failed: $handlerError\n$handlerStackTrace',
        logLevel: LogLevel.error,
      );
    }
  }
}

@visibleForTesting
Future<void> handleHotKeyActionSafely({
  required Future<void> Function() action,
  required void Function(Object error, StackTrace stackTrace) onError,
}) async {
  try {
    await action();
  } catch (error, stackTrace) {
    onError(error, stackTrace);
  }
}

class HotKeyManager extends ConsumerStatefulWidget {
  final Widget child;

  const HotKeyManager({super.key, required this.child});

  @override
  ConsumerState<HotKeyManager> createState() => _HotKeyManagerState();
}

class _HotKeyManagerState extends ConsumerState<HotKeyManager> {
  late final HotKeyUpdateCoordinator<HotKeyAction> _updates;

  @override
  void initState() {
    super.initState();
    _updates = HotKeyUpdateCoordinator<HotKeyAction>(
      unregisterAll: hotKeyManager.unregisterAll,
      register: _registerHotKey,
      onError: _reportHotKeyError,
    );
    ref.listenManual(hotKeyActionsProvider, (prev, next) {
      if (!hotKeyActionListEquality.equals(prev, next)) {
        _updates.update(_validHotKeyActions(next));
      }
    }, fireImmediately: true);
  }

  Iterable<HotKeyAction> _validHotKeyActions(List<HotKeyAction> hotKeyActions) {
    return hotKeyActions.where(
      (action) => action.key != null && action.modifiers.isNotEmpty,
    );
  }

  Future<void> _handleHotKeyAction(HotAction action) async {
    final ref = globalState.container;
    final commonAction = ref.read(commonActionProvider.notifier);
    final systemAction = ref.read(systemActionProvider.notifier);
    switch (action) {
      case HotAction.mode:
        commonAction.updateMode();
      case HotAction.start:
        await commonAction.updateStart();
      case HotAction.view:
        await systemAction.updateVisible();
      case HotAction.proxy:
        systemAction.updateSystemProxy();
      case HotAction.tun:
        systemAction.updateTun();
    }
  }

  Future<void> _registerHotKey(HotKeyAction hotKeyAction) {
    final modifiers = hotKeyAction.modifiers
        .map((item) => item.toHotKeyModifier())
        .toList();
    final hotKey = HotKey(
      key: PhysicalKeyboardKey(hotKeyAction.key!),
      modifiers: modifiers,
    );
    return hotKeyManager.register(
      hotKey,
      keyDownHandler: (_) {
        unawaited(
          handleHotKeyActionSafely(
            action: () => _handleHotKeyAction(hotKeyAction.action),
            onError: _reportHotKeyError,
          ),
        );
      },
    );
  }

  void _reportHotKeyError(Object error, StackTrace stackTrace) {
    commonPrint.log(
      'Hotkey operation failed: $error\n$stackTrace',
      logLevel: LogLevel.warning,
    );
    globalState.showNotifier(error.toString());
  }

  Shortcuts _buildCloseShortcuts(Widget child) {
    return Shortcuts(
      shortcuts: {
        utils.controlSingleActivator(LogicalKeyboardKey.keyW):
            const CloseWindowIntent(),
      },
      child: Actions(
        actions: {
          CloseWindowIntent: CallbackAction<CloseWindowIntent>(
            onInvoke: (_) {
              unawaited(
                handleHotKeyActionSafely(
                  action: () => globalState.container
                      .read(systemActionProvider.notifier)
                      .handleClose(false),
                  onError: _reportHotKeyError,
                ),
              );
              return null;
            },
          ),
          DoNothingIntent: CallbackAction<DoNothingIntent>(
            onInvoke: (_) => null,
          ),
        },
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildCloseShortcuts(widget.child);
  }

  @override
  void dispose() {
    unawaited(_updates.dispose());
    super.dispose();
  }
}
