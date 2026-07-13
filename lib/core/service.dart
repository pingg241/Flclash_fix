import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/core.dart';
import 'package:flutter/foundation.dart';

import 'interface.dart';
import 'transport.dart';

@visibleForTesting
Future<void> dispatchCoreResult({
  required ActionResult result,
  required Map<String, Completer> pendingResults,
  required Future<dynamic> Function(ActionResult result) parseResult,
  required FutureOr<void> Function(CoreEvent event) sendEvent,
}) async {
  final id = result.id;
  final completer = id == null ? null : pendingResults[id];
  try {
    final data = await parseResult(result);
    if (id?.isEmpty == true || result.method == ActionMethod.message) {
      await sendEvent(CoreEvent.fromJson(result.data));
    }
    if (completer != null && !completer.isCompleted) {
      completer.complete(data);
    }
  } catch (error, stackTrace) {
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
    rethrow;
  } finally {
    if (id != null) {
      pendingResults.remove(id);
    }
  }
}

@visibleForTesting
Future<({bool killAccepted, bool exited})> terminateCoreProcess({
  required FutureOr<bool> Function() terminate,
  required Future<int> exitCode,
  Duration timeout = const Duration(seconds: 5),
}) async {
  bool killAccepted;
  try {
    killAccepted = await terminate();
  } catch (_) {
    killAccepted = false;
  }
  try {
    await exitCode.timeout(timeout);
    return (killAccepted: killAccepted, exited: true);
  } on TimeoutException {
    return (killAccepted: killAccepted, exited: false);
  }
}

@visibleForTesting
Future<bool> waitForCoreProcessExit({
  required Future<int> exitCode,
  Duration timeout = const Duration(seconds: 5),
}) async {
  try {
    await exitCode.timeout(timeout);
    return true;
  } on TimeoutException {
    return false;
  }
}

class CoreProcessShutdownResult {
  final bool graceful;
  final bool exited;
  final bool disconnectConfirmed;
  final bool? terminationAccepted;

  const CoreProcessShutdownResult({
    required this.graceful,
    required this.exited,
    required this.disconnectConfirmed,
    required this.terminationAccepted,
  });

  bool get confirmed => exited && disconnectConfirmed;
}

@visibleForTesting
Future<CoreProcessShutdownResult> stopCoreProcess({
  required FutureOr<bool> Function() gracefulShutdown,
  required FutureOr<bool> Function() terminate,
  required Future<int> exitCode,
  required bool wasConnected,
  required Future<void> disconnected,
  Duration exitTimeout = const Duration(seconds: 5),
  Duration disconnectTimeout = const Duration(seconds: 5),
  void Function(Object error, StackTrace stackTrace)? onGracefulError,
}) async {
  var graceful = false;
  if (wasConnected) {
    try {
      graceful = await gracefulShutdown();
    } catch (error, stackTrace) {
      onGracefulError?.call(error, stackTrace);
    }
  }

  var exited =
      graceful &&
      await waitForCoreProcessExit(exitCode: exitCode, timeout: exitTimeout);
  bool? terminationAccepted;
  if (!exited) {
    final termination = await terminateCoreProcess(
      terminate: terminate,
      exitCode: exitCode,
      timeout: exitTimeout,
    );
    terminationAccepted = termination.killAccepted;
    exited = termination.exited;
  }
  if (!exited) {
    return CoreProcessShutdownResult(
      graceful: graceful,
      exited: false,
      disconnectConfirmed: false,
      terminationAccepted: terminationAccepted,
    );
  }

  var disconnectConfirmed = !wasConnected;
  if (wasConnected) {
    try {
      await disconnected.timeout(disconnectTimeout);
      disconnectConfirmed = true;
    } on TimeoutException {
      disconnectConfirmed = false;
    }
  }
  return CoreProcessShutdownResult(
    graceful: graceful,
    exited: true,
    disconnectConfirmed: disconnectConfirmed,
    terminationAccepted: terminationAccepted,
  );
}

@visibleForTesting
Future<bool> stopHelperCore({
  required Future<bool> Function() stop,
  required bool wasConnected,
  required Future<void> disconnected,
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (!await stop()) {
    return false;
  }
  if (!wasConnected) {
    return true;
  }
  try {
    await disconnected.timeout(timeout);
    return true;
  } on TimeoutException {
    return false;
  }
}

@visibleForTesting
void clearPendingCoreResults(Map<String, Completer> pendingResults) {
  for (final entry in pendingResults.entries) {
    final methodName = entry.key.split('#').first;
    final method = ActionMethod.values.firstWhere(
      (candidate) => candidate.name == methodName,
      orElse: () => ActionMethod.message,
    );
    final completer = entry.value;
    if (!completer.isCompleted) {
      completer.completeError(
        CoreInvocationException(
          method: method,
          failure: CoreInvocationFailure.disconnected,
          message: 'core disconnected before responding',
        ),
      );
    }
  }
  pendingResults.clear();
}

@visibleForTesting
Future<T?> waitForCoreResult<T>({
  required String id,
  required ActionMethod method,
  required Completer<T?> completer,
  required Map<String, Completer> pendingResults,
  required Duration timeout,
}) {
  return completer.future.timeout(
    timeout,
    onTimeout: () {
      pendingResults.remove(id);
      throw CoreInvocationException(
        method: method,
        failure: CoreInvocationFailure.timeout,
        message: 'core response timed out after $timeout',
      );
    },
  );
}

class CoreService extends CoreHandlerInterface {
  static CoreService? _instance;

  late final CoreTransportLifecycle _transportLifecycle;

  Completer<bool> _shutdownCompleter = Completer();
  final Completer<void> _idleConnectionCompleter = Completer<void>();

  final Map<String, Completer> _callbackCompleterMap = {};

  StreamSubscription<CoreTransportData>? _dataSubscription;
  CoreProcessHandle? _process;
  Future<void>? _startFuture;
  Future<bool>? _shutdownFuture;
  bool _isShuttingDown = false;

  factory CoreService() {
    _instance ??= CoreService._internal();
    return _instance!;
  }

  CoreService._internal() {
    _transportLifecycle = CoreTransportLifecycle(
      createTransport: _createTransport,
      onCreate: _attachTransport,
    );
  }

  CoreTransport _createTransport() {
    final token = base64Url.encode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    return IPCCoreTransport(
      address: system.isWindows ? windowsPipeName : unixSocketPath,
      token: token,
    );
  }

  Future<void> handleResult(ActionResult result) async {
    await dispatchCoreResult(
      result: result,
      pendingResults: _callbackCompleterMap,
      parseResult: parasResult,
      sendEvent: coreEventManager.sendEvent,
    );
  }

  Future<void> _attachTransport(CoreTransportSession session) async {
    await _dataSubscription?.cancel();
    session.transport.onDisconnect = () {
      unawaited(_handleTransportDisconnect(session));
    };
    var processingTail = Future<void>.value();
    _dataSubscription = session.transport.dataStream.listen(
      (event) {
        processingTail = processingTail.then((_) async {
          try {
            if (!_transportLifecycle.isCurrent(session)) {
              return;
            }
            final data = utf8.decode(event.bytes);
            final dataJson = await data.trim().commonToJSON<dynamic>();
            await handleResult(ActionResult.fromJson(dataJson));
          } catch (e) {
            commonPrint.log(
              'Failed to parse transport data: $e',
              logLevel: LogLevel.error,
            );
          } finally {
            await event.acknowledge();
          }
        });
      },
      onError: (error) {
        commonPrint.log(
          'Transport data stream error: $error',
          logLevel: LogLevel.error,
        );
      },
    );
  }

  Future<void> _handleTransportDisconnect(CoreTransportSession session) async {
    if (!_transportLifecycle.isCurrent(session)) {
      return;
    }
    _clearCompleter();
    if (!_shutdownCompleter.isCompleted) {
      _shutdownCompleter.complete(true);
    }
    if (_isShuttingDown) {
      return;
    }
    _handleInvokeCrashEvent();
    unawaited(_cleanupExitedProcess());
    try {
      await _discardTransport(expected: session);
    } catch (error) {
      commonPrint.log(
        'Failed to discard disconnected IPC transport: $error',
        logLevel: LogLevel.error,
      );
    }
  }

  Future<void> _cleanupExitedProcess() async {
    final process = _process;
    if (process == null ||
        !await waitForCoreProcessExit(exitCode: process.exitCode)) {
      return;
    }
    if (identical(_process, process)) {
      _process = null;
    }
    await process.cleanup();
  }

  Future<void> _discardTransport({CoreTransportSession? expected}) async {
    if (expected != null && !_transportLifecycle.isCurrent(expected)) {
      return;
    }
    final subscription = _dataSubscription;
    _dataSubscription = null;
    Object? cancelError;
    StackTrace? cancelStackTrace;
    try {
      await subscription?.cancel();
    } catch (error, stackTrace) {
      cancelError = error;
      cancelStackTrace = stackTrace;
    }
    await _transportLifecycle.reset(expected: expected);
    if (cancelError != null) {
      Error.throwWithStackTrace(cancelError, cancelStackTrace!);
    }
  }

  void _handleInvokeCrashEvent() {
    coreEventManager.sendEvent(
      const CoreEvent(type: CoreEventType.crash, data: 'core done'),
    );
  }

  Future<void> start() {
    final shutdownFuture = _shutdownFuture;
    if (shutdownFuture != null) {
      return shutdownFuture.then((stopped) {
        if (!stopped) {
          throw StateError('core shutdown did not complete');
        }
        return start();
      });
    }
    final startFuture = _startFuture;
    if (startFuture != null) {
      return startFuture;
    }
    if (_transportLifecycle.current?.transport.isConnected == true) {
      return Future.value();
    }
    final future = _start();
    _startFuture = future;
    return future.whenComplete(() {
      if (identical(_startFuture, future)) {
        _startFuture = null;
      }
    });
  }

  Future<void> _start() async {
    final session = await _transportLifecycle.ensureReady();
    if (session.transport.isConnected) {
      return;
    }
    CoreProcessHandle? process;
    var helperStarted = false;
    try {
      final homeDir = await appPath.homeDirPath;
      final arguments = [session.transport.address, homeDir];
      if (system.isWindows && await system.checkIsAdmin()) {
        helperStarted = await request.startCoreByHelper(
          args: arguments,
          ipcToken: session.transport.token,
        );
        if (!helperStarted) {
          throw StateError('privileged helper failed to start core');
        }
        await _waitForConnection(session);
        return;
      }

      process = await system.startCoreProcess(
        arguments: arguments,
        environment: {'FLCLASH_IPC_TOKEN': session.transport.token},
      );
      _process = process;
      process.stdout.listen((_) {});
      process.stderr.listen((data) {
        final error = utf8.decode(data, allowMalformed: true).trim();
        if (error.isNotEmpty) {
          commonPrint.log(error, logLevel: LogLevel.warning);
        }
      });

      var connected = false;
      final exited = process.exitCode.then<void>((code) {
        if (!connected) {
          throw StateError('core exited before IPC ready (code $code)');
        }
      });
      await Future.any<void>([
        _waitForConnection(session).then((_) {
          connected = true;
        }),
        exited,
      ]);
      if (!session.transport.isConnected ||
          !_transportLifecycle.isCurrent(session)) {
        throw StateError('core disconnected while startup was completing');
      }
    } catch (error, stackTrace) {
      Object? cleanupError;
      try {
        await _cleanupFailedStart(
          process: process,
          helperStarted: helperStarted,
        );
      } catch (caught) {
        cleanupError = caught;
      }
      try {
        await _discardTransport(expected: session);
      } catch (caught) {
        cleanupError ??= caught;
      }
      if (cleanupError != null) {
        throw StateError(
          'core startup failed: $error; cleanup failed: $cleanupError',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _cleanupFailedStart({
    required CoreProcessHandle? process,
    required bool helperStarted,
  }) async {
    if (process != null) {
      final termination = await terminateCoreProcess(
        terminate: process.terminate,
        exitCode: process.exitCode,
      );
      if (termination.exited) {
        if (identical(_process, process)) {
          _process = null;
        }
        await process.cleanup();
        return;
      }
      throw StateError('core failed to exit after startup failure');
    }
    if (helperStarted && !await request.stopCoreByHelper()) {
      throw StateError('privileged helper failed to stop core after startup');
    }
  }

  Future<void> _waitForConnection(CoreTransportSession session) async {
    try {
      await session.transport.waitForConnection().timeout(
        const Duration(seconds: 10),
      );
      if (!session.transport.isConnected ||
          !_transportLifecycle.isCurrent(session)) {
        throw StateError('IPC connection generation was invalidated');
      }
    } on TimeoutException {
      throw TimeoutException('core IPC authentication timed out');
    }
  }

  @override
  FutureOr<bool> destroy() async {
    return shutdown(false);
  }

  Future<void> sendMessage(String message) async {
    final session = _transportLifecycle.current;
    if (session == null) {
      throw StateError('IPC server is not initialized');
    }
    await session.transport.waitForConnection().timeout(
      const Duration(seconds: 10),
    );
    if (!_transportLifecycle.isCurrent(session) ||
        !session.transport.isConnected) {
      throw StateError('IPC connection is no longer active');
    }
    await session.transport.send(message);
  }

  @override
  Future<bool> shutdown(bool isUser) {
    final shutdownFuture = _shutdownFuture;
    if (shutdownFuture != null) {
      return shutdownFuture;
    }
    final future = _shutdown();
    _shutdownFuture = future;
    return future.whenComplete(() {
      if (identical(_shutdownFuture, future)) {
        _shutdownFuture = null;
      }
    });
  }

  Future<bool> _shutdown() async {
    _isShuttingDown = true;
    _shutdownCompleter = Completer();
    try {
      final startFuture = _startFuture;
      if (startFuture != null) {
        try {
          await startFuture;
        } catch (_) {}
      }
      final session = _transportLifecycle.current;
      final process = _process;
      final wasConnected = session?.transport.isConnected == true;
      var shutdownConfirmed = true;
      if (process != null) {
        final result = await stopCoreProcess(
          gracefulShutdown: () async =>
              await invoke<bool>(
                method: ActionMethod.shutdown,
                timeout: const Duration(seconds: 5),
              ) ==
              true,
          terminate: process.terminate,
          exitCode: process.exitCode,
          wasConnected: wasConnected,
          disconnected: _shutdownCompleter.future,
          onGracefulError: (error, _) {
            commonPrint.log(
              'Graceful core shutdown failed: $error',
              logLevel: LogLevel.warning,
            );
          },
        );
        if (wasConnected && !result.graceful) {
          commonPrint.log(
            'Graceful core shutdown was not confirmed; fallback termination was used',
            logLevel: LogLevel.warning,
          );
        }
        if (result.terminationAccepted == false) {
          commonPrint.log(
            'Core process rejected privileged termination',
            logLevel: LogLevel.warning,
          );
        }
        if (!result.exited) {
          return false;
        }
        shutdownConfirmed = result.confirmed;
      } else if (system.isWindows) {
        if (!await request.stopCoreByHelper()) {
          return false;
        }
        if (wasConnected &&
            !await _waitForShutdownDisconnect(_shutdownCompleter.future)) {
          shutdownConfirmed = false;
        }
      } else if (wasConnected) {
        shutdownConfirmed = false;
      }
      await process?.cleanup();
      _process = null;
      _clearCompleter();
      await _discardTransport(expected: session);
      if (!_shutdownCompleter.isCompleted) {
        _shutdownCompleter.complete(true);
      }
      return shutdownConfirmed;
    } finally {
      _isShuttingDown = false;
    }
  }

  Future<bool> _waitForShutdownDisconnect(Future<void> disconnected) async {
    try {
      await disconnected.timeout(const Duration(seconds: 5));
      return true;
    } on TimeoutException {
      return false;
    }
  }

  void _clearCompleter() {
    clearPendingCoreResults(_callbackCompleterMap);
  }

  @override
  Future<String> preload() async {
    try {
      await start();
      return '';
    } catch (e) {
      commonPrint.log('Failed to start core: $e', logLevel: LogLevel.error);
      _handleInvokeCrashEvent();
      return e.toString();
    }
  }

  @override
  Future<T?> invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
  }) async {
    final id = '${method.name}#${utils.id}';
    final completer = Completer<T?>();
    _callbackCompleterMap[id] = completer;
    try {
      await sendMessage(
        json.encode(Action(id: id, method: method, data: data)),
      );
    } catch (error, stackTrace) {
      _callbackCompleterMap.remove(id);
      Error.throwWithStackTrace(
        CoreInvocationException(
          method: method,
          failure: error is TimeoutException
              ? CoreInvocationFailure.timeout
              : CoreInvocationFailure.disconnected,
          message: error is TimeoutException
              ? 'core IPC send timed out'
              : 'core IPC connection is unavailable',
          cause: error,
        ),
        stackTrace,
      );
    }
    return waitForCoreResult<T>(
      id: id,
      method: method,
      completer: completer,
      pendingResults: _callbackCompleterMap,
      timeout: timeout ?? const Duration(minutes: 3),
    );
  }

  @override
  Completer get completer =>
      _transportLifecycle.current?.transport.connectionCompleter ??
      _idleConnectionCompleter;
}

final coreService = system.isDesktop ? CoreService() : null;
