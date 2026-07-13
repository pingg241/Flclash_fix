import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'proxy_method_channel.dart';

abstract class ProxyPlatform extends PlatformInterface {
  /// Constructs a ProxyPlatform.
  ProxyPlatform() : super(token: _token);

  static final Object _token = Object();

  static ProxyPlatform _instance = MethodChannelProxy();

  /// The default instance of [ProxyPlatform] to use.
  ///
  /// Defaults to [MethodChannelProxy].
  static ProxyPlatform get instance => _instance;

  static set instance(ProxyPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> startProxy(int port, List<String> bypassDomain) {
    throw UnimplementedError('startProxy() has not been implemented.');
  }

  Future<void> stopProxy() {
    throw UnimplementedError('stopProxy() has not been implemented.');
  }

  Future<Map<String, Object?>> captureProxy() {
    throw UnimplementedError('captureProxy() has not been implemented.');
  }

  Future<void> restoreProxy(Map<String, Object?> snapshot) {
    throw UnimplementedError('restoreProxy() has not been implemented.');
  }
}
