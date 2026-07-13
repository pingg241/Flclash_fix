import 'dart:async';

import 'package:fl_clash/common/common.dart';

class Debouncer {
  final Map<dynamic, Timer?> _operations = {};
  final Map<dynamic, Completer<dynamic>> _completers = {};

  void call(
    dynamic tag,
    Function func, {
    List<dynamic>? args,
    Duration? duration,
  }) {
    unawaited(
      callAsync<dynamic>(
        tag,
        func,
        args: args,
        duration: duration,
        propagateErrors: false,
      ),
    );
  }

  Future<T?> callAsync<T>(
    dynamic tag,
    Function func, {
    List<dynamic>? args,
    Duration? duration,
    bool propagateErrors = true,
  }) {
    cancel(tag);
    final completer = Completer<T?>();
    _completers[tag] = completer;
    _operations[tag] = Timer(
      duration ?? const Duration(milliseconds: 600),
      () async {
        try {
          final value = await Future<dynamic>.sync(
            () => Function.apply(func, args),
          );
          if (!completer.isCompleted) {
            completer.complete(value as T?);
          }
        } catch (error, stackTrace) {
          if (completer.isCompleted) {
            return;
          }
          if (propagateErrors) {
            completer.completeError(error, stackTrace);
          } else {
            commonPrint.log('Debounced operation failed: $error\n$stackTrace');
            completer.complete();
          }
        } finally {
          if (identical(_completers[tag], completer)) {
            _operations.remove(tag)?.cancel();
            _completers.remove(tag);
          }
        }
      },
    );
    return completer.future;
  }

  void cancel(dynamic tag) {
    _operations.remove(tag)?.cancel();
    final completer = _completers.remove(tag);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}

class Throttler {
  final Map<dynamic, Timer?> _operations = {};
  final Map<dynamic, Completer<void>> _completers = {};

  bool call(
    dynamic tag,
    Function func, {
    List<dynamic>? args,
    Duration duration = const Duration(milliseconds: 600),
    bool fire = false,
  }) {
    if (_operations[tag] != null) {
      return true;
    }
    unawaited(
      _run(
        tag,
        func,
        args: args,
        duration: duration,
        fire: fire,
        propagateErrors: false,
      ),
    );
    return false;
  }

  Future<bool> callAsync(
    dynamic tag,
    Function func, {
    List<dynamic>? args,
    Duration duration = const Duration(milliseconds: 600),
    bool fire = false,
  }) async {
    if (_operations[tag] != null) {
      return true;
    }
    await _run(
      tag,
      func,
      args: args,
      duration: duration,
      fire: fire,
      propagateErrors: true,
    );
    return false;
  }

  Future<void> _run(
    dynamic tag,
    Function func, {
    required List<dynamic>? args,
    required Duration duration,
    required bool fire,
    required bool propagateErrors,
  }) async {
    if (fire) {
      late final Timer timer;
      timer = Timer(duration, () {
        if (identical(_operations[tag], timer)) {
          _operations.remove(tag);
        }
      });
      _operations[tag] = timer;
      await _invoke(func, args, propagateErrors);
    } else {
      final completer = Completer<void>();
      _completers[tag] = completer;
      late final Timer timer;
      timer = Timer(duration, () {
        unawaited(
          _invoke(func, args, propagateErrors)
              .then(
                (_) {
                  if (!completer.isCompleted) {
                    completer.complete();
                  }
                },
                onError: (Object error, StackTrace stackTrace) {
                  if (!completer.isCompleted) {
                    completer.completeError(error, stackTrace);
                  }
                },
              )
              .whenComplete(() {
                if (identical(_operations[tag], timer)) {
                  _operations.remove(tag);
                }
              }),
        );
      });
      _operations[tag] = timer;
      try {
        await completer.future;
      } finally {
        if (identical(_completers[tag], completer)) {
          _completers.remove(tag);
        }
      }
    }
  }

  Future<void> _invoke(
    Function func,
    List<dynamic>? args,
    bool propagateErrors,
  ) async {
    try {
      await Future<dynamic>.sync(() => Function.apply(func, args));
    } catch (error, stackTrace) {
      if (propagateErrors) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      commonPrint.log('Throttled operation failed: $error\n$stackTrace');
    }
  }

  void cancel(dynamic tag) {
    _operations.remove(tag)?.cancel();
    final completer = _completers.remove(tag);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}

class AsyncPeriodicTask {
  final Duration interval;
  final FutureOr<void> Function() task;
  final void Function(Object error, StackTrace stackTrace)? onError;

  Timer? _timer;
  bool _isRunning = false;
  int _generation = 0;

  AsyncPeriodicTask({required this.interval, required this.task, this.onError});

  bool get isRunning => _isRunning;

  void start() {
    if (_isRunning) {
      return;
    }
    _isRunning = true;
    _generation++;
    _schedule(_generation);
  }

  void stop() {
    _isRunning = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  void _schedule(int generation) {
    if (!_isRunning || generation != _generation) {
      return;
    }
    _timer = Timer(interval, () => _run(generation));
  }

  Future<void> _run(int generation) async {
    try {
      await task();
    } catch (error, stackTrace) {
      final handler = onError;
      if (handler != null) {
        try {
          handler(error, stackTrace);
        } catch (handlerError, handlerStackTrace) {
          commonPrint.log(
            'Periodic task error handler failed: '
            '$handlerError\n$handlerStackTrace',
          );
        }
      } else {
        commonPrint.log('Periodic task failed: $error\n$stackTrace');
      }
    } finally {
      _schedule(generation);
    }
  }
}

Future<T> retry<T>({
  required Future<T> Function() task,
  int maxAttempts = 3,
  required bool Function(T res) retryIf,
  Duration delay = midDuration,
}) async {
  int attempts = 0;
  while (attempts < maxAttempts) {
    final res = await task();
    attempts++;
    if (!retryIf(res) || attempts >= maxAttempts) {
      return res;
    }
    await Future.delayed(delay);
  }
  throw 'retry error';
}

final debouncer = Debouncer();

final throttler = Throttler();
