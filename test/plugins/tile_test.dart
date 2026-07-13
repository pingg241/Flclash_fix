import 'dart:async';

import 'package:fl_clash/plugins/tile.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class TestTileListener with TileListener {
  Completer<void>? startCompleter;
  Object? startError;
  int startCalls = 0;

  @override
  Future<void> onStart() async {
    startCalls++;
    final error = startError;
    if (error != null) {
      throw error;
    }
    await startCompleter?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tile = Tile.instance;
  late TestTileListener listener;

  setUp(() {
    listener = TestTileListener();
    tile.addListener(listener);
  });

  tearDown(() {
    tile.removeListener(listener);
  });

  test('start waits for the listener operation to finish', () async {
    final completer = Completer<void>();
    listener.startCompleter = completer;

    var completed = false;
    final call = tile
        .handleMethodCall(const MethodCall('start'))
        .whenComplete(() => completed = true);
    await Future<void>.delayed(Duration.zero);

    expect(listener.startCalls, 1);
    expect(completed, isFalse);

    completer.complete();
    await call;
    expect(completed, isTrue);
  });

  test('listener exceptions are returned to the native caller', () async {
    listener.startError = StateError('start failed');

    await expectLater(
      tile.handleMethodCall(const MethodCall('start')),
      throwsStateError,
    );
  });

  test('repeated calls each wait for their listener operation', () async {
    final completer = Completer<void>();
    listener.startCompleter = completer;

    final first = tile.handleMethodCall(const MethodCall('start'));
    final second = tile.handleMethodCall(const MethodCall('start'));
    await Future<void>.delayed(Duration.zero);

    expect(listener.startCalls, 2);
    completer.complete();
    await Future.wait([first, second]);
  });

  test('unknown methods fail instead of reporting success', () async {
    await expectLater(
      tile.handleMethodCall(const MethodCall('unknown')),
      throwsA(isA<MissingPluginException>()),
    );
  });
}
