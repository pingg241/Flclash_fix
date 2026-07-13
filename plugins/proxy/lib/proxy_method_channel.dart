import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'proxy_platform_interface.dart';

/// An implementation of [ProxyPlatform] that uses method channels.
class MethodChannelProxy extends ProxyPlatform {
  static const _operationTimeout = Duration(seconds: 10);

  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('proxy');

  MethodChannelProxy();

  @override
  Future<void> startProxy(int port, List<String> bypassDomain) async {
    final result = await methodChannel.invokeMethod<bool>('StartProxy', {
      'port': port,
      'bypassDomain': bypassDomain,
    }).timeout(_operationTimeout);
    if (result != true) {
      throw StateError('native system proxy start failed');
    }
  }

  @override
  Future<void> stopProxy() async {
    final result = await methodChannel
        .invokeMethod<bool>('StopProxy')
        .timeout(_operationTimeout);
    if (result != true) {
      throw StateError('native system proxy stop failed');
    }
  }

  @override
  Future<Map<String, Object?>> captureProxy() async {
    final result = await methodChannel
        .invokeMapMethod<String, Object?>('CaptureProxy')
        .timeout(_operationTimeout);
    if (result == null) {
      throw StateError('native system proxy capture failed');
    }
    return result;
  }

  @override
  Future<void> restoreProxy(Map<String, Object?> snapshot) async {
    final result = await methodChannel
        .invokeMethod<bool>('RestoreProxy', snapshot)
        .timeout(_operationTimeout);
    if (result != true) {
      throw StateError('native system proxy restore failed');
    }
  }
}
