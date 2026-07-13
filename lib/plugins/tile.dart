import 'dart:async';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract mixin class TileListener {
  Future<void> onStart() async {}

  Future<void> onStop() async {}

  Future<void> onDetached() async {}
}

class Tile {
  final MethodChannel _channel = const MethodChannel('$packageName/tile');

  Tile._() {
    _channel.setMethodCallHandler(handleMethodCall);
  }

  static final Tile instance = Tile._();

  final ObserverList<TileListener> _listeners = ObserverList<TileListener>();

  @visibleForTesting
  Future<void> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'start':
        for (final TileListener listener in _listeners) {
          await listener.onStart();
        }
        return;
      case 'stop':
        for (final TileListener listener in _listeners) {
          await listener.onStop();
        }
        return;
      case 'detached':
        for (final TileListener listener in _listeners) {
          await listener.onDetached();
        }
        return;
      default:
        throw MissingPluginException('Unknown tile method ${call.method}');
    }
  }

  bool get hasListeners {
    return _listeners.isNotEmpty;
  }

  void addListener(TileListener listener) {
    _listeners.add(listener);
  }

  void removeListener(TileListener listener) {
    _listeners.remove(listener);
  }
}

final tile = system.isAndroid ? Tile.instance : null;
