import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract mixin class ServiceListener {
  void onServiceEvent(CoreEvent event) {}

  void onServiceCrash(String message) {}
}

class Service {
  static Service? _instance;
  late MethodChannel methodChannel;
  ReceivePort? receiver;
  Duration lifecycleTimeout = const Duration(seconds: 30);
  Duration lifecycleCancellationTimeout = const Duration(seconds: 30);
  int _lifecycleOperationSequence = 0;

  final ObserverList<ServiceListener> _listeners =
      ObserverList<ServiceListener>();

  factory Service() {
    _instance ??= Service._internal();
    return _instance!;
  }

  Service._internal() {
    methodChannel = const MethodChannel('$packageName/service');
    methodChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'event':
          final data = call.arguments as String? ?? '';
          final result = ActionResult.fromJson(json.decode(data));
          for (final listener in _listeners) {
            listener.onServiceEvent(CoreEvent.fromJson(result.data));
          }
          break;
        case 'crash':
          final message = call.arguments as String? ?? '';
          for (final listener in _listeners) {
            listener.onServiceCrash(message);
          }
          break;
        default:
          throw MissingPluginException();
      }
    });
  }

  Future<ActionResult?> invokeAction(Action action) async {
    final data = await methodChannel.invokeMethod<String>(
      'invokeAction',
      json.encode(action),
    );
    if (data == null) {
      return null;
    }
    final dataJson = await data.commonToJSON<dynamic>();
    return ActionResult.fromJson(dataJson);
  }

  Future<bool> start() async {
    final operationId = _nextLifecycleOperationId();
    try {
      return await _invokeLifecycle<bool>('start', {
            'operationId': operationId,
          }) ??
          false;
    } on TimeoutException catch (error, stackTrace) {
      final cancelled = await methodChannel
          .invokeMethod<bool>('cancelStart', {'operationId': operationId})
          .timeout(lifecycleCancellationTimeout);
      if (cancelled != true) {
        throw StateError(
          'Android service did not confirm cancellation for $operationId',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<bool> stop() async {
    return await _invokeLifecycle<bool>('stop') ?? false;
  }

  Future<String> init() {
    return _requireLifecycleResult<String>('init');
  }

  Future<String> syncState(SharedState state) {
    return _requireLifecycleResult<String>('syncState', json.encode(state));
  }

  Future<bool> shutdown() async {
    return await _invokeLifecycle<bool>('shutdown') ?? false;
  }

  Future<DateTime?> getRunTime() async {
    final ms = await _invokeLifecycle<int>('getRunTime') ?? 0;
    if (ms == 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<T?> _invokeLifecycle<T>(String method, [dynamic arguments]) {
    return methodChannel
        .invokeMethod<T>(method, arguments)
        .timeout(lifecycleTimeout);
  }

  String _nextLifecycleOperationId() {
    final sequence = _lifecycleOperationSequence++;
    return '${DateTime.now().microsecondsSinceEpoch}-$sequence';
  }

  Future<T> _requireLifecycleResult<T>(
    String method, [
    dynamic arguments,
  ]) async {
    final result = await _invokeLifecycle<T>(method, arguments);
    if (result == null) {
      throw StateError('Android service $method returned no result');
    }
    return result;
  }

  bool get hasListeners {
    return _listeners.isNotEmpty;
  }

  void addListener(ServiceListener listener) {
    _listeners.add(listener);
  }

  void removeListener(ServiceListener listener) {
    _listeners.remove(listener);
  }
}

Service? get service => system.isAndroid ? Service() : null;
