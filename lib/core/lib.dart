import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/core.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';

import 'interface.dart';

class CoreLib extends CoreHandlerInterface {
  static CoreLib? _instance;

  Completer<bool> _connectedCompleter = Completer();
  final Service? _service;

  CoreLib._internal() : _service = service;

  @visibleForTesting
  CoreLib.test(this._service, {bool connected = false}) {
    if (connected) {
      _connectedCompleter.complete(true);
    }
  }

  @override
  Future<String> preload() async {
    if (_connectedCompleter.isCompleted) {
      return 'core is connected';
    }
    final currentService = _service;
    if (currentService == null) {
      return 'Android core service is unavailable';
    }
    final res = await currentService.init();
    if (res.isNotEmpty) {
      return res;
    }
    final syncRes = await currentService.syncState(
      globalState.container.read(sharedStateProvider),
    );
    if (syncRes.isEmpty) {
      _connectedCompleter.complete(true);
    }
    return syncRes;
  }

  factory CoreLib() {
    _instance ??= CoreLib._internal();
    return _instance!;
  }

  @override
  FutureOr<bool> destroy() async {
    return true;
  }

  @override
  Future<bool> shutdown(_) async {
    final currentService = _service;
    if (!_connectedCompleter.isCompleted || currentService == null) {
      return false;
    }
    final stopped = await currentService.shutdown();
    if (stopped) {
      _connectedCompleter = Completer();
    }
    return stopped;
  }

  @override
  Future<bool> startListener() async {
    final coreOk = await super.startListener();
    if (coreOk == false) {
      return false;
    }
    try {
      final serviceOk = await _service?.start() ?? false;
      if (serviceOk) {
        return true;
      }
      await _rollbackStartedListener();
      return false;
    } catch (error, stackTrace) {
      await _rollbackStartedListener();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _rollbackStartedListener() async {
    try {
      final stopped = await super.stopListener();
      if (!stopped) {
        commonPrint.log(
          'Failed to compensate core listener after Android service failure',
          logLevel: LogLevel.error,
        );
      }
    } catch (error, stackTrace) {
      commonPrint.log(
        'Core listener compensation failed: $error\n$stackTrace',
        logLevel: LogLevel.error,
      );
    }
  }

  @override
  Future<bool> stopListener() async {
    final coreOk = await super.stopListener();
    if (!coreOk) {
      return false;
    }
    // The Go listener is already stopped. A native service failure must not
    // restore a fake running state.
    return await _service?.stop() ?? false;
  }

  @override
  Future<T?> invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
  }) async {
    final id = '${method.name}#${utils.id}';
    final request = _service?.invokeAction(
      Action(id: id, method: method, data: data),
    );
    if (request == null) {
      throw CoreInvocationException(
        method: method,
        failure: CoreInvocationFailure.unavailable,
        message: 'Android core service is unavailable',
      );
    }
    ActionResult? result;
    try {
      result = await request.timeout(timeout ?? const Duration(minutes: 3));
    } on TimeoutException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        CoreInvocationException(
          method: method,
          failure: CoreInvocationFailure.timeout,
          message: 'Android core response timed out',
          cause: error,
        ),
        stackTrace,
      );
    }
    if (result == null) {
      throw CoreInvocationException(
        method: method,
        failure: CoreInvocationFailure.noResponse,
        message: 'Android core returned no response',
      );
    }
    return parasResult<T>(result);
  }

  @override
  Completer get completer => _connectedCompleter;
}

CoreLib? get coreLib => system.isAndroid ? CoreLib() : null;
