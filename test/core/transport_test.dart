import 'dart:async';
import 'dart:typed_data';

import 'package:fl_clash/core/transport.dart';
import 'package:test/test.dart';

void main() {
  test(
    'server bind failure completes init and a new generation recovers',
    () async {
      final failed = _FakeTransport(initError: StateError('bind failed'));
      final recovered = _FakeTransport();
      final transports = [failed, recovered];
      final lifecycle = CoreTransportLifecycle(
        createTransport: () => transports.removeAt(0),
        readyTimeout: const Duration(milliseconds: 100),
      );

      await expectLater(lifecycle.ensureReady(), throwsStateError);
      expect(failed.closeCount, 1);

      final session = await lifecycle.ensureReady();
      expect(session.transport, same(recovered));
      expect(lifecycle.isCurrent(session), isTrue);

      await lifecycle.reset();
    },
  );

  test(
    'late events from an old generation cannot affect the current one',
    () async {
      final first = _FakeTransport();
      final second = _FakeTransport();
      final transports = [first, second];
      final acceptedDisconnects = <int>[];
      late final CoreTransportLifecycle lifecycle;
      lifecycle = CoreTransportLifecycle(
        createTransport: () => transports.removeAt(0),
        onCreate: (session) {
          session.transport.onDisconnect = () {
            if (lifecycle.isCurrent(session)) {
              acceptedDisconnects.add(session.generation);
            }
          };
        },
      );

      final firstSession = await lifecycle.ensureReady();
      await lifecycle.reset(expected: firstSession);
      final secondSession = await lifecycle.ensureReady();

      first.triggerDisconnect();
      expect(acceptedDisconnects, isEmpty);
      second.triggerDisconnect();
      expect(acceptedDisconnects, [secondSession.generation]);

      await lifecycle.reset();
    },
  );

  test('concurrent starts and repeated stops remain single flight', () async {
    final transports = <_FakeTransport>[];
    final lifecycle = CoreTransportLifecycle(
      createTransport: () {
        final transport = _FakeTransport();
        transports.add(transport);
        return transport;
      },
    );

    final sessions = await Future.wait([
      lifecycle.ensureReady(),
      lifecycle.ensureReady(),
      lifecycle.ensureReady(),
    ]);
    expect(transports, hasLength(1));
    expect(sessions.every((item) => identical(item, sessions.first)), isTrue);

    await Future.wait([lifecycle.reset(), lifecycle.reset()]);
    expect(transports.single.closeCount, 1);

    final restarted = await lifecycle.ensureReady();
    expect(transports, hasLength(2));
    expect(restarted.generation, greaterThan(sessions.first.generation));
    await lifecycle.reset();
    await lifecycle.reset();
    expect(transports.last.closeCount, 1);
  });

  test('TYPE_ERROR fails readiness instead of leaving init pending', () async {
    final events = StreamController<Uint8List>(sync: true);
    var stopCount = 0;
    final transport = IPCCoreTransport(
      address: 'test-address',
      token: '0123456789abcdef0123456789abcdef',
      restartServer: ({required name, required token}) => events.stream,
      stopServer: () async {
        stopCount++;
      },
      sendMessage: (_) async {},
    );

    final initFuture = transport.init();
    events.add(Uint8List.fromList([0x04, ...'bind failed'.codeUnits]));

    await expectLater(initFuture, throwsStateError);
    await transport.close();
    await events.close();
    expect(stopCount, 1);
  });

  test('data is acknowledged only after consumer completion', () async {
    final events = StreamController<Uint8List>(sync: true);
    final acknowledgements = <(int, int)>[];
    final transport = IPCCoreTransport(
      address: 'test-address',
      token: '0123456789abcdef0123456789abcdef',
      restartServer: ({required name, required token}) => events.stream,
      stopServer: () async {},
      sendMessage: (_) async {},
      acknowledgeEvents: (generation, sequence) async {
        acknowledgements.add((generation, sequence));
      },
    );

    final initFuture = transport.init();
    events.add(Uint8List.fromList([0x00]));
    await initFuture;
    events.add(Uint8List.fromList([0x01]));

    final received = Completer<CoreTransportData>();
    final subscription = transport.dataStream.listen(received.complete);
    events.add(_dataFrame(generation: 7, sequence: 1, payload: [1, 2, 3]));
    final event = await received.future;
    expect(event.bytes, [1, 2, 3]);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(acknowledgements, isEmpty);

    await event.acknowledge();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(acknowledgements, [(7, 1)]);
    await event.acknowledge();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(acknowledgements, [(7, 1)]);

    await subscription.cancel();
    await transport.close();
    await events.close();
  });

  test('acknowledgements flush at the batch threshold', () async {
    final events = StreamController<Uint8List>(sync: true);
    final acknowledgements = <(int, int)>[];
    final transport = _ipcTransport(events, acknowledgements);

    final initFuture = transport.init();
    events.add(Uint8List.fromList([0x00]));
    await initFuture;
    events.add(Uint8List.fromList([0x01]));

    final received = <CoreTransportData>[];
    final receivedAll = Completer<void>();
    final subscription = transport.dataStream.listen((event) {
      received.add(event);
      if (received.length == 32) {
        receivedAll.complete();
      }
    });
    for (var sequence = 1; sequence <= 32; sequence++) {
      events.add(
        _dataFrame(generation: 9, sequence: sequence, payload: [sequence]),
      );
    }
    await receivedAll.future;
    for (final event in received) {
      await event.acknowledge();
    }
    await Future<void>.delayed(Duration.zero);

    expect(acknowledgements, [(9, 32)]);
    await subscription.cancel();
    await transport.close();
    await events.close();
  });

  test(
    'a failed final acknowledgement retries without another event',
    () async {
      final events = StreamController<Uint8List>(sync: true);
      final attempts = <(int, int)>[];
      final recovered = Completer<void>();
      final transport = IPCCoreTransport(
        address: 'test-address',
        token: '0123456789abcdef0123456789abcdef',
        restartServer: ({required name, required token}) => events.stream,
        stopServer: () async {},
        sendMessage: (_) async {},
        acknowledgeEvents: (generation, sequence) async {
          attempts.add((generation, sequence));
          if (attempts.length == 1) {
            throw StateError('temporary acknowledgement failure');
          }
          recovered.complete();
        },
      );

      final initFuture = transport.init();
      events.add(Uint8List.fromList([0x00]));
      await initFuture;
      events.add(Uint8List.fromList([0x01]));

      final received = Completer<CoreTransportData>();
      final subscription = transport.dataStream.listen(received.complete);
      events.add(_dataFrame(generation: 10, sequence: 1, payload: [1]));
      await (await received.future).acknowledge();
      await recovered.future.timeout(const Duration(seconds: 1));

      expect(attempts, [(10, 1), (10, 1)]);
      await subscription.cancel();
      await transport.close();
      await events.close();
    },
  );

  test(
    'acknowledgement retries stay serialized and merge newer events',
    () async {
      final events = StreamController<Uint8List>(sync: true);
      final attempts = <(int, int)>[];
      final firstAttemptStarted = Completer<void>();
      final releaseFirstAttempt = Completer<void>();
      final recovered = Completer<void>();
      var activeSends = 0;
      var maxActiveSends = 0;
      final transport = IPCCoreTransport(
        address: 'test-address',
        token: '0123456789abcdef0123456789abcdef',
        restartServer: ({required name, required token}) => events.stream,
        stopServer: () async {},
        sendMessage: (_) async {},
        acknowledgeEvents: (generation, sequence) async {
          activeSends++;
          if (activeSends > maxActiveSends) {
            maxActiveSends = activeSends;
          }
          attempts.add((generation, sequence));
          try {
            if (attempts.length == 1) {
              firstAttemptStarted.complete();
              await releaseFirstAttempt.future;
              throw StateError('temporary acknowledgement failure');
            }
            recovered.complete();
          } finally {
            activeSends--;
          }
        },
      );

      final initFuture = transport.init();
      events.add(Uint8List.fromList([0x00]));
      await initFuture;
      events.add(Uint8List.fromList([0x01]));

      final received = <CoreTransportData>[];
      final receivedAll = Completer<void>();
      final subscription = transport.dataStream.listen((event) {
        received.add(event);
        if (received.length == 2) {
          receivedAll.complete();
        }
      });
      events.add(_dataFrame(generation: 11, sequence: 1, payload: [1]));
      events.add(_dataFrame(generation: 11, sequence: 2, payload: [2]));
      await receivedAll.future;
      await received[0].acknowledge();
      await firstAttemptStarted.future.timeout(const Duration(seconds: 1));
      await received[1].acknowledge();
      releaseFirstAttempt.complete();
      await recovered.future.timeout(const Duration(seconds: 1));

      expect(attempts, [(11, 1), (11, 2)]);
      expect(maxActiveSends, 1);
      await subscription.cancel();
      await transport.close();
      await events.close();
    },
  );

  test(
    'close cancels timers and does not retry a failed final flush',
    () async {
      final events = StreamController<Uint8List>(sync: true);
      var attempts = 0;
      final transport = IPCCoreTransport(
        address: 'test-address',
        token: '0123456789abcdef0123456789abcdef',
        restartServer: ({required name, required token}) => events.stream,
        stopServer: () async {},
        sendMessage: (_) async {},
        acknowledgeEvents: (generation, sequence) async {
          attempts++;
          throw StateError('persistent acknowledgement failure');
        },
      );

      final initFuture = transport.init();
      events.add(Uint8List.fromList([0x00]));
      await initFuture;
      events.add(Uint8List.fromList([0x01]));

      final received = Completer<CoreTransportData>();
      final subscription = transport.dataStream.listen(received.complete);
      events.add(_dataFrame(generation: 12, sequence: 1, payload: [1]));
      await (await received.future).acknowledge();
      await transport.close();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(attempts, 1);
      await subscription.cancel();
      await events.close();
    },
  );

  test(
    'a new event generation supersedes an unsent old acknowledgement',
    () async {
      final events = StreamController<Uint8List>(sync: true);
      final acknowledgements = <(int, int)>[];
      final transport = _ipcTransport(events, acknowledgements);

      final initFuture = transport.init();
      events.add(Uint8List.fromList([0x00]));
      await initFuture;
      events.add(Uint8List.fromList([0x01]));

      final received = <CoreTransportData>[];
      final receivedAll = Completer<void>();
      final subscription = transport.dataStream.listen((event) {
        received.add(event);
        if (received.length == 2) {
          receivedAll.complete();
        }
      });
      events.add(_dataFrame(generation: 10, sequence: 1, payload: [1]));
      events.add(_dataFrame(generation: 11, sequence: 1, payload: [2]));
      await receivedAll.future;
      await received[0].acknowledge();
      await received[1].acknowledge();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(acknowledgements, [(11, 1)]);
      await subscription.cancel();
      await transport.close();
      await events.close();
    },
  );

  test('late acknowledgements from an older generation are ignored', () async {
    final events = StreamController<Uint8List>(sync: true);
    final acknowledgements = <(int, int)>[];
    final transport = _ipcTransport(events, acknowledgements);

    final initFuture = transport.init();
    events.add(Uint8List.fromList([0x00]));
    await initFuture;
    events.add(Uint8List.fromList([0x01]));

    final received = <CoreTransportData>[];
    final receivedAll = Completer<void>();
    final subscription = transport.dataStream.listen((event) {
      received.add(event);
      if (received.length == 2) {
        receivedAll.complete();
      }
    });
    events.add(_dataFrame(generation: 12, sequence: 1, payload: [1]));
    events.add(_dataFrame(generation: 13, sequence: 1, payload: [2]));
    await receivedAll.future;
    await received[1].acknowledge();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await received[0].acknowledge();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(acknowledgements, [(13, 1)]);
    await subscription.cancel();
    await transport.close();
    await events.close();
  });

  test('late acknowledgements are ignored after transport close', () async {
    final events = StreamController<Uint8List>(sync: true);
    final acknowledgements = <(int, int)>[];
    final transport = _ipcTransport(events, acknowledgements);

    final initFuture = transport.init();
    events.add(Uint8List.fromList([0x00]));
    await initFuture;
    events.add(Uint8List.fromList([0x01]));

    final received = Completer<CoreTransportData>();
    transport.dataStream.listen(received.complete);
    events.add(_dataFrame(generation: 12, sequence: 1, payload: [1]));
    final event = await received.future;

    await transport.close();
    await event.acknowledge();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(acknowledgements, isEmpty);
    await events.close();
  });
}

IPCCoreTransport _ipcTransport(
  StreamController<Uint8List> events,
  List<(int, int)> acknowledgements,
) {
  return IPCCoreTransport(
    address: 'test-address',
    token: '0123456789abcdef0123456789abcdef',
    restartServer: ({required name, required token}) => events.stream,
    stopServer: () async {},
    sendMessage: (_) async {},
    acknowledgeEvents: (generation, sequence) async {
      acknowledgements.add((generation, sequence));
    },
  );
}

Uint8List _dataFrame({
  required int generation,
  required int sequence,
  required List<int> payload,
}) {
  final metadata = ByteData(16)
    ..setUint64(0, generation, Endian.little)
    ..setUint64(8, sequence, Endian.little);
  return Uint8List.fromList([
    0x03,
    ...metadata.buffer.asUint8List(),
    ...payload,
  ]);
}

class _FakeTransport implements CoreTransport {
  @override
  final String address = 'test-address';
  @override
  final String token = '0123456789abcdef0123456789abcdef';

  final Object? initError;
  final Completer<void> _connectionCompleter = Completer<void>();
  void Function()? _onDisconnect;
  bool _connected = false;
  int closeCount = 0;

  _FakeTransport({this.initError});

  @override
  Completer<void> get connectionCompleter => _connectionCompleter;

  @override
  Stream<CoreTransportData> get dataStream =>
      const Stream<CoreTransportData>.empty();

  @override
  bool get isConnected => _connected;

  @override
  set onDisconnect(void Function()? callback) {
    _onDisconnect = callback;
  }

  @override
  Future<void> init() async {
    final error = initError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> waitForConnection() => _connectionCompleter.future;

  @override
  Future<void> send(String message) async {}

  @override
  void disconnected() {
    _connected = false;
  }

  void triggerDisconnect() {
    _connected = false;
    _onDisconnect?.call();
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}
