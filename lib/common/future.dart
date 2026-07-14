import 'dart:async';
import 'dart:ui';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';

extension FutureExt<T> on Future<T> {
  Future<T> withTimeout({
    Duration? timeout,
    String? tag,
    VoidCallback? onLast,
    FutureOr<T> Function()? onTimeout,
  }) {
    final realTimeout = timeout ?? const Duration(minutes: 3);
    Timer(realTimeout + commonDuration, () {
      if (onLast != null) {
        onLast();
      }
    });
    return this.timeout(
      realTimeout,
      onTimeout: () {
        if (onTimeout != null) {
          return onTimeout();
        } else {
          throw TimeoutException('${tag ?? runtimeType} timeout');
        }
      },
    );
  }
}

extension CompleterExt<T> on Completer<T> {
  void safeCompleter(T value) {
    if (isCompleted) {
      return;
    }
    complete(value);
  }
}

Future<void> runAsyncSafely({
  required FutureOr<void> Function() operation,
  required void Function(Object error, StackTrace stackTrace) onError,
}) async {
  try {
    await operation();
  } catch (error, stackTrace) {
    try {
      onError(error, stackTrace);
    } catch (handlerError, handlerStackTrace) {
      commonPrint.log(
        'Async error handler failed: $handlerError\n$handlerStackTrace',
        logLevel: LogLevel.error,
      );
    }
  }
}
