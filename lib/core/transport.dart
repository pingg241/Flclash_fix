import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:rust_api/rust_api.dart';

const _typeReady = 0x00;
const _typeConnected = 0x01;
const _typeDisconnected = 0x02;
const _typeData = 0x03;
const _typeError = 0x04;
const _ackBatchSize = 32;
const _ackFlushDelay = Duration(milliseconds: 2);
const _ackRetryMinDelay = Duration(milliseconds: 10);
const _ackRetryMaxDelay = Duration(seconds: 1);

typedef CoreTransportFactory = CoreTransport Function();
typedef CoreTransportCreated =
    FutureOr<void> Function(CoreTransportSession session);

abstract interface class CoreTransport {
  String get address;

  String get token;

  Completer<void> get connectionCompleter;

  bool get isConnected;

  Stream<CoreTransportData> get dataStream;

  set onDisconnect(void Function()? callback);

  Future<void> init();

  Future<void> waitForConnection();

  Future<void> send(String message);

  void disconnected();

  Future<void> close();
}

class CoreTransportData {
  final Uint8List bytes;
  final Future<void> Function() _acknowledge;
  bool _acknowledged = false;

  CoreTransportData(this.bytes, this._acknowledge);

  Future<void> acknowledge() {
    if (_acknowledged) {
      return Future.value();
    }
    _acknowledged = true;
    return _acknowledge();
  }
}

class CoreTransportSession {
  final int generation;
  final CoreTransport transport;

  const CoreTransportSession({
    required this.generation,
    required this.transport,
  });
}

/// Owns the single global Rust IPC server and replaces it by generation.
class CoreTransportLifecycle {
  final CoreTransportFactory createTransport;
  final CoreTransportCreated? onCreate;
  final Duration readyTimeout;

  int _generation = 0;
  CoreTransportSession? _candidate;
  CoreTransportSession? _active;
  Future<CoreTransportSession>? _readyFuture;
  Future<void>? _resetFuture;

  CoreTransportLifecycle({
    required this.createTransport,
    this.onCreate,
    this.readyTimeout = const Duration(seconds: 10),
  });

  CoreTransportSession? get current => _active ?? _candidate;

  bool isCurrent(CoreTransportSession session) {
    final current = this.current;
    return current != null &&
        current.generation == session.generation &&
        identical(current.transport, session.transport);
  }

  Future<CoreTransportSession> ensureReady() {
    final resetFuture = _resetFuture;
    if (resetFuture != null) {
      return resetFuture.then((_) => ensureReady());
    }
    final active = _active;
    if (active != null) {
      return Future.value(active);
    }
    final readyFuture = _readyFuture;
    if (readyFuture != null) {
      return readyFuture;
    }

    final session = CoreTransportSession(
      generation: ++_generation,
      transport: createTransport(),
    );
    _candidate = session;
    late final Future<CoreTransportSession> future;
    future = _initialize(session).whenComplete(() {
      if (identical(_readyFuture, future)) {
        _readyFuture = null;
      }
    });
    _readyFuture = future;
    return future;
  }

  Future<CoreTransportSession> _initialize(CoreTransportSession session) async {
    try {
      await onCreate?.call(session);
      await session.transport.init().timeout(readyTimeout);
      if (!isCurrent(session)) {
        throw StateError('IPC transport generation was invalidated');
      }
      _candidate = null;
      _active = session;
      return session;
    } catch (error, stackTrace) {
      if (isCurrent(session)) {
        _candidate = null;
        try {
          await session.transport.close();
        } catch (closeError) {
          commonPrint.log(
            'Failed to close rejected IPC transport: $closeError',
            logLevel: LogLevel.error,
          );
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> reset({CoreTransportSession? expected}) {
    final resetFuture = _resetFuture;
    if (resetFuture != null) {
      return resetFuture;
    }
    if (expected != null && !isCurrent(expected)) {
      return Future.value();
    }

    final candidate = _candidate;
    final active = _active;
    final readyFuture = _readyFuture;
    _generation++;
    _candidate = null;
    _active = null;
    _readyFuture = null;

    late final Future<void> future;
    future = _reset(candidate, active, readyFuture).whenComplete(() {
      if (identical(_resetFuture, future)) {
        _resetFuture = null;
      }
    });
    _resetFuture = future;
    return future;
  }

  Future<void> _reset(
    CoreTransportSession? candidate,
    CoreTransportSession? active,
    Future<CoreTransportSession>? readyFuture,
  ) async {
    Object? closeError;
    StackTrace? closeStackTrace;
    final transports = <CoreTransport>[];
    if (candidate != null) {
      transports.add(candidate.transport);
    }
    if (active != null &&
        !transports.any((item) => identical(item, active.transport))) {
      transports.add(active.transport);
    }
    for (final transport in transports) {
      try {
        await transport.close();
      } catch (error, stackTrace) {
        closeError ??= error;
        closeStackTrace ??= stackTrace;
      }
    }
    if (readyFuture != null) {
      try {
        await readyFuture;
      } catch (_) {}
    }
    if (closeError != null) {
      Error.throwWithStackTrace(closeError, closeStackTrace!);
    }
  }
}

class IPCCoreTransport implements CoreTransport {
  @override
  final String address;
  @override
  final String token;

  final Stream<Uint8List> Function({
    required String name,
    required String token,
  })
  _restartServer;
  final Future<void> Function() _stopServer;
  final Future<void> Function(List<int> data) _sendMessage;
  final Future<void> Function(int generation, int throughSequence)
  _acknowledgeEvents;
  late final _EventAcknowledger _eventAcknowledger;
  final StreamController<CoreTransportData> _dataController =
      StreamController<CoreTransportData>.broadcast();

  StreamSubscription<Uint8List>? _subscription;
  Completer<void> _connectionCompleter = _errorHandledCompleter();
  Completer<void> _connectionFailureCompleter = _errorHandledCompleter();
  final Completer<void> _readyCompleter = _errorHandledCompleter();
  final Completer<void> _closedCompleter = _errorHandledCompleter();
  void Function()? _onDisconnect;
  bool _initialized = false;
  bool _isReady = false;
  bool _isConnected = false;
  bool _closed = false;

  IPCCoreTransport({
    required this.address,
    required this.token,
    Stream<Uint8List> Function({required String name, required String token})?
    restartServer,
    Future<void> Function()? stopServer,
    Future<void> Function(List<int> data)? sendMessage,
    Future<void> Function(int generation, int throughSequence)?
    acknowledgeEvents,
  }) : _restartServer = restartServer ?? restartIpcServer,
       _stopServer = stopServer ?? stopIpcServer,
       _sendMessage = sendMessage ?? ((data) => sendIpcMessage(data: data)),
       _acknowledgeEvents =
           acknowledgeEvents ??
           ((generation, throughSequence) => acknowledgeIpcEvents(
             generation: BigInt.from(generation),
             throughSequence: BigInt.from(throughSequence),
           )) {
    _eventAcknowledger = _EventAcknowledger(_acknowledgeEvents);
  }

  @override
  Completer<void> get connectionCompleter => _connectionCompleter;

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<CoreTransportData> get dataStream => _dataController.stream;

  Future<void> get closed => _closedCompleter.future;

  @override
  set onDisconnect(void Function()? callback) {
    _onDisconnect = callback;
  }

  @override
  Future<void> init() async {
    if (_initialized) {
      return _readyCompleter.future;
    }
    if (_closed) {
      throw StateError('IPC transport is closed');
    }
    _initialized = true;
    try {
      final stream = _restartServer(name: address, token: token);
      _subscription = stream.listen(
        _handleFrame,
        onError: _handleStreamError,
        onDone: _handleStreamDone,
        cancelOnError: false,
      );
      await _readyCompleter.future;
    } catch (error, stackTrace) {
      _completeReadyError(error, stackTrace);
      commonPrint.log(
        'Failed to start IPC server: $error',
        logLevel: LogLevel.error,
      );
      rethrow;
    }
  }

  void _handleFrame(Uint8List data) {
    if (_closed || data.isEmpty) {
      return;
    }
    final type = data[0];
    final payload = data.length > 1 ? data.sublist(1) : Uint8List(0);
    switch (type) {
      case _typeReady:
        commonPrint.log('IPC Ready');
        _isReady = true;
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.complete();
        }
        break;
      case _typeConnected:
        if (!_isReady) {
          _completeReadyError(
            StateError('IPC connected before server became ready'),
            StackTrace.current,
          );
          break;
        }
        commonPrint.log('IPC Connected');
        _isConnected = true;
        if (!_connectionCompleter.isCompleted) {
          _connectionCompleter.complete();
        }
        break;
      case _typeDisconnected:
        commonPrint.log('IPC Disconnected');
        _markDisconnected();
        break;
      case _typeData:
        if (payload.length < 16) {
          _handleServerError(
            StateError('IPC data frame is missing flow-control metadata'),
            StackTrace.current,
          );
          break;
        }
        final metadata = ByteData.sublistView(payload, 0, 16);
        final generation = metadata.getUint64(0, Endian.little);
        final sequence = metadata.getUint64(8, Endian.little);
        if (_isConnected && !_dataController.isClosed) {
          _dataController.add(
            CoreTransportData(
              payload.sublist(16),
              () => _eventAcknowledger.acknowledge(generation, sequence),
            ),
          );
        }
        break;
      case _typeError:
        final message = utf8.decode(payload, allowMalformed: true);
        final error = StateError('IPC server error: $message');
        commonPrint.log(error.toString(), logLevel: LogLevel.error);
        _handleServerError(error, StackTrace.current);
        break;
      default:
        commonPrint.log(
          'IPC unknown frame type: $type',
          logLevel: LogLevel.warning,
        );
    }
  }

  void _handleServerError(Object error, StackTrace stackTrace) {
    if (!_isReady) {
      _completeReadyError(error, stackTrace);
      return;
    }
    if (!_isConnected && !_connectionFailureCompleter.isCompleted) {
      _connectionFailureCompleter.completeError(error, stackTrace);
    }
    if (!_dataController.isClosed) {
      _dataController.addError(error, stackTrace);
    }
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    if (_closed) {
      return;
    }
    commonPrint.log('IPC stream error: $error', logLevel: LogLevel.error);
    _handleServerError(error, stackTrace);
    _finishStream(error, stackTrace);
  }

  void _handleStreamDone() {
    if (_closed) {
      return;
    }
    final error = StateError('IPC server event stream closed');
    _handleServerError(error, StackTrace.current);
    _finishStream(error, StackTrace.current);
  }

  void _finishStream(Object error, StackTrace stackTrace) {
    final wasConnected = _isConnected;
    _closed = true;
    _isConnected = false;
    _completeReadyError(error, stackTrace);
    if (!_connectionFailureCompleter.isCompleted) {
      _connectionFailureCompleter.completeError(error, stackTrace);
    }
    if (!_closedCompleter.isCompleted) {
      _closedCompleter.completeError(error, stackTrace);
    }
    if (wasConnected) {
      _onDisconnect?.call();
    }
  }

  void _completeReadyError(Object error, StackTrace stackTrace) {
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(error, stackTrace);
    }
  }

  void _markDisconnected() {
    final wasConnected = _isConnected;
    if (!wasConnected) {
      return;
    }
    _isConnected = false;
    _connectionCompleter = _errorHandledCompleter();
    _connectionFailureCompleter = _errorHandledCompleter();
    _onDisconnect?.call();
  }

  @override
  Future<void> waitForConnection() {
    if (_isConnected) {
      return Future.value();
    }
    return Future.any([
      _connectionCompleter.future,
      _connectionFailureCompleter.future,
    ]);
  }

  @override
  Future<void> send(String message) async {
    if (!_isConnected) {
      throw StateError('IPC client is not connected');
    }
    await _sendMessage(utf8.encode(message));
  }

  @override
  void disconnected() {
    _markDisconnected();
  }

  @override
  Future<void> close() async {
    if (_closed && _subscription == null) {
      return;
    }
    _closed = true;
    _isConnected = false;
    final closedError = StateError('IPC transport closed');
    _completeReadyError(closedError, StackTrace.current);
    if (!_connectionFailureCompleter.isCompleted) {
      _connectionFailureCompleter.completeError(
        closedError,
        StackTrace.current,
      );
    }
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _eventAcknowledger.close();
      await _stopServer();
      if (!_closedCompleter.isCompleted) {
        _closedCompleter.complete();
      }
    } catch (error, stackTrace) {
      if (!_closedCompleter.isCompleted) {
        _closedCompleter.completeError(error, stackTrace);
      }
      rethrow;
    } finally {
      if (!_dataController.isClosed) {
        await _dataController.close();
      }
    }
  }
}

class _EventAcknowledger {
  final Future<void> Function(int generation, int throughSequence) _send;
  int? _generation;
  int _pendingSequence = 0;
  int _sentSequence = 0;
  Timer? _timer;
  Future<void>? _worker;
  Future<void>? _closeFuture;
  Duration? _retryDelay;
  int _retryAttempt = 0;
  bool _closing = false;
  bool _closed = false;

  _EventAcknowledger(this._send);

  Future<void> acknowledge(int generation, int sequence) {
    if (_closing || _closed) {
      return Future.value();
    }
    final currentGeneration = _generation;
    if (currentGeneration == null || generation > currentGeneration) {
      _generation = generation;
      _pendingSequence = 0;
      _sentSequence = 0;
      _retryAttempt = 0;
      _retryDelay = null;
      _timer?.cancel();
      _timer = null;
    } else if (generation < currentGeneration) {
      return Future.value();
    }
    if (sequence <= _pendingSequence) {
      return Future.value();
    }
    _pendingSequence = sequence;
    if (_pendingSequence - _sentSequence >= _ackBatchSize) {
      _timer?.cancel();
      _timer = null;
      _startWorker();
    } else if (_worker == null) {
      _schedule(_ackFlushDelay);
    }
    return Future.value();
  }

  void _schedule(Duration delay) {
    if (_closing || _closed || _timer != null) {
      return;
    }
    _timer = Timer(delay, () {
      _timer = null;
      _startWorker();
    });
  }

  void _startWorker() {
    _timer?.cancel();
    _timer = null;
    if (_closed || _worker != null) {
      return;
    }
    late final Future<void> worker;
    worker = _drain().whenComplete(() {
      if (!identical(_worker, worker)) {
        return;
      }
      _worker = null;
      if (_closing || _closed || _pendingSequence <= _sentSequence) {
        return;
      }
      final delay = _retryDelay ?? _ackFlushDelay;
      _retryDelay = null;
      _schedule(delay);
    });
    _worker = worker;
  }

  Future<void> _drain() async {
    while (!_closed) {
      final generation = _generation;
      final sequence = _pendingSequence;
      if (generation == null || sequence <= _sentSequence) {
        return;
      }
      try {
        await _send(generation, sequence);
      } catch (error, stackTrace) {
        commonPrint.log(
          'Failed to acknowledge IPC events: $error\n$stackTrace',
          logLevel: LogLevel.warning,
        );
        if (_closing || _closed) {
          return;
        }
        if (_generation != generation) {
          _retryAttempt = 0;
          continue;
        }
        _retryDelay = _nextRetryDelay();
        return;
      }
      if (_generation != generation) {
        _retryAttempt = 0;
        continue;
      }
      _sentSequence = sequence;
      _retryAttempt = 0;
      _retryDelay = null;
    }
  }

  Duration _nextRetryDelay() {
    const maxShift = 6;
    final shift = _retryAttempt > maxShift ? maxShift : _retryAttempt;
    _retryAttempt++;
    final milliseconds = _ackRetryMinDelay.inMilliseconds * (1 << shift);
    return Duration(
      milliseconds: milliseconds > _ackRetryMaxDelay.inMilliseconds
          ? _ackRetryMaxDelay.inMilliseconds
          : milliseconds,
    );
  }

  Future<void> close() {
    return _closeFuture ??= _close();
  }

  Future<void> _close() async {
    if (_closed) {
      return;
    }
    _closing = true;
    _retryDelay = null;
    _timer?.cancel();
    _timer = null;
    _startWorker();
    await _worker;
    _closed = true;
  }
}

Completer<void> _errorHandledCompleter() {
  final completer = Completer<void>();
  unawaited(completer.future.catchError((_) {}));
  return completer;
}
