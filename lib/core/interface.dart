import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';

enum CoreInvocationFailure { unavailable, timeout, disconnected, noResponse }

class CoreInvocationException implements Exception {
  final ActionMethod method;
  final CoreInvocationFailure failure;
  final String message;
  final Object? cause;

  const CoreInvocationException({
    required this.method,
    required this.failure,
    required this.message,
    this.cause,
  });

  @override
  String toString() => 'CoreInvocationException(${method.name}): $message';
}

mixin CoreInterface {
  Future<bool> init(InitParams params);

  Future<String> preload();

  Future<bool> shutdown(bool isUser);

  Future<bool> get isInit;

  Future<bool> forceGc();

  Future<String> validateConfig(String path);

  Future<Result> getConfig(String path);

  Future<String> asyncTestDelay(String url, String proxyName);

  Future<String> updateConfig(UpdateParams updateParams);

  Future<String> setupConfig(SetupParams setupParams);

  Future<ProxiesData> getProxies();

  Future<String> changeProxy(ChangeProxyParams changeProxyParams);

  Future<bool> startListener();

  Future<bool> stopListener();

  /// Structured list or legacy JSON string of providers.
  FutureOr<dynamic> getExternalProviders();

  /// Structured provider map or legacy JSON string.
  FutureOr<dynamic> getExternalProvider(String externalProviderName);

  Future<String> updateGeoData(String type);

  Future<String> sideLoadExternalProvider({
    required String providerName,
    required String data,
  });

  Future<String> updateExternalProvider(String providerName);

  /// Structured `{up,down}` map or legacy JSON string.
  FutureOr<dynamic> getTraffic(bool onlyStatisticsProxy);

  /// Structured `{up,down}` map or legacy JSON string.
  FutureOr<dynamic> getTotalTraffic(bool onlyStatisticsProxy);

  /// Structured `{now,total}` map or legacy JSON string.
  FutureOr<dynamic> getTrafficSnapshot(bool onlyStatisticsProxy);

  FutureOr<String> getCountryCode(String ip);

  FutureOr<String> getMemory();

  Future<void> resetTraffic();

  Future<void> startLog();

  Future<void> stopLog();

  Future<bool> crash();

  /// Structured connections snapshot or legacy JSON string.
  FutureOr<dynamic> getConnections();

  FutureOr<bool> closeConnection(String id);

  FutureOr<String> deleteFile(String path);

  FutureOr<bool> closeConnections();

  FutureOr<bool> resetConnections();

  Future<String> prepareTunHelper();

  Future<String> releaseTunHelper();
}

abstract class CoreHandlerInterface with CoreInterface {
  Completer get completer;

  FutureOr<bool> destroy();

  Future<T> _invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
  }) async {
    try {
      await completer.future.timeout(const Duration(seconds: 10));
    } catch (error, stackTrace) {
      commonPrint.log(
        'Invoke pre ${method.name} failed: $error',
        logLevel: LogLevel.error,
      );
      Error.throwWithStackTrace(
        CoreInvocationException(
          method: method,
          failure: error is TimeoutException
              ? CoreInvocationFailure.timeout
              : CoreInvocationFailure.unavailable,
          message: error is TimeoutException
              ? 'core connection timed out'
              : 'core connection is unavailable',
          cause: error,
        ),
        stackTrace,
      );
    }
    final result = await utils.handleWatch<T?>(
      onStart: () {
        if (kDebugMode) {
          commonPrint.log('Invoke ${method.name} ${DateTime.now()} $data');
        }
      },
      function: () async {
        return invoke<T>(method: method, data: data, timeout: timeout);
      },
      onEnd: (data, elapsedMilliseconds) {
        if (kDebugMode) {
          commonPrint.log('Invoke ${method.name} ${elapsedMilliseconds}ms');
        }
      },
    );
    if (result == null) {
      throw CoreInvocationException(
        method: method,
        failure: CoreInvocationFailure.noResponse,
        message: 'core returned no response',
      );
    }
    return result;
  }

  Future<T?> invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
  });

  Future<T> parasResult<T>(ActionResult result) async {
    return switch (result.method) {
      ActionMethod.getConfig => result.toResult as T,
      _ => result.data as T,
    };
  }

  @override
  Future<bool> init(InitParams params) async {
    return _invoke<bool>(
      method: ActionMethod.initClash,
      data: json.encode(params),
    );
  }

  @override
  Future<bool> shutdown(bool isUser);

  @override
  Future<bool> get isInit async {
    return _invoke<bool>(method: ActionMethod.getIsInit);
  }

  @override
  Future<bool> forceGc() async {
    return _invoke<bool>(method: ActionMethod.forceGc);
  }

  @override
  Future<String> validateConfig(String path) async {
    return _invoke<String>(method: ActionMethod.validateConfig, data: path);
  }

  @override
  Future<String> updateConfig(UpdateParams updateParams) async {
    return _invoke<String>(
      method: ActionMethod.updateConfig,
      data: json.encode(updateParams),
    );
  }

  @override
  Future<Result> getConfig(String path) async {
    return _invoke<Result>(method: ActionMethod.getConfig, data: path);
  }

  @override
  Future<String> setupConfig(SetupParams setupParams) async {
    return _invoke<String>(
      method: ActionMethod.setupConfig,
      data: json.encode(setupParams),
    );
  }

  @override
  Future<bool> crash() async {
    return _invoke<bool>(method: ActionMethod.crash);
  }

  @override
  Future<ProxiesData> getProxies() async {
    final data = await _invoke<Map<String, dynamic>>(
      method: ActionMethod.getProxies,
    );
    return ProxiesData.fromJson(data);
  }

  @override
  Future<String> changeProxy(ChangeProxyParams changeProxyParams) async {
    return _invoke<String>(
      method: ActionMethod.changeProxy,
      data: json.encode(changeProxyParams),
    );
  }

  @override
  Future<dynamic> getExternalProviders() async {
    return _invoke<dynamic>(method: ActionMethod.getExternalProviders);
  }

  @override
  Future<dynamic> getExternalProvider(String externalProviderName) async {
    return _invoke<dynamic>(
      method: ActionMethod.getExternalProvider,
      data: externalProviderName,
    );
  }

  @override
  Future<String> updateGeoData(String type) async {
    return _invoke<String>(method: ActionMethod.updateGeoData, data: type);
  }

  @override
  Future<String> sideLoadExternalProvider({
    required String providerName,
    required String data,
  }) async {
    return _invoke<String>(
      method: ActionMethod.sideLoadExternalProvider,
      data: json.encode({'providerName': providerName, 'data': data}),
    );
  }

  @override
  Future<String> updateExternalProvider(String providerName) async {
    return _invoke<String>(
      method: ActionMethod.updateExternalProvider,
      data: providerName,
    );
  }

  @override
  Future<dynamic> getConnections() async {
    return _invoke<dynamic>(method: ActionMethod.getConnections);
  }

  @override
  Future<bool> closeConnections() async {
    return _invoke<bool>(method: ActionMethod.closeConnections);
  }

  @override
  Future<bool> resetConnections() async {
    return _invoke<bool>(method: ActionMethod.resetConnections);
  }

  @override
  Future<bool> closeConnection(String id) async {
    return _invoke<bool>(method: ActionMethod.closeConnection, data: id);
  }

  @override
  Future<dynamic> getTotalTraffic(bool onlyStatisticsProxy) async {
    return _invoke<dynamic>(
      method: ActionMethod.getTotalTraffic,
      data: onlyStatisticsProxy,
    );
  }

  @override
  Future<dynamic> getTraffic(bool onlyStatisticsProxy) async {
    return _invoke<dynamic>(
      method: ActionMethod.getTraffic,
      data: onlyStatisticsProxy,
    );
  }

  @override
  Future<dynamic> getTrafficSnapshot(bool onlyStatisticsProxy) async {
    return _invoke<dynamic>(
      method: ActionMethod.getTrafficSnapshot,
      data: onlyStatisticsProxy,
    );
  }

  @override
  Future<String> deleteFile(String path) async {
    return _invoke<String>(method: ActionMethod.deleteFile, data: path);
  }

  @override
  Future<void> resetTraffic() async {
    await _invoke<dynamic>(method: ActionMethod.resetTraffic);
  }

  @override
  Future<void> startLog() async {
    await _invoke<dynamic>(method: ActionMethod.startLog);
  }

  @override
  Future<void> stopLog() async {
    await _invoke<dynamic>(method: ActionMethod.stopLog);
  }

  @override
  Future<bool> startListener() async {
    return _invoke<bool>(method: ActionMethod.startListener);
  }

  @override
  Future<bool> stopListener() async {
    return _invoke<bool>(method: ActionMethod.stopListener);
  }

  @override
  Future<String> asyncTestDelay(String url, String proxyName) async {
    final delayParams = {
      'proxy-name': proxyName,
      'timeout': httpTimeoutDuration.inMilliseconds,
      'test-url': url,
    };
    return _invoke<String>(
      method: ActionMethod.asyncTestDelay,
      data: json.encode(delayParams),
      timeout: const Duration(seconds: 6),
    );
  }

  @override
  Future<String> getCountryCode(String ip) async {
    return _invoke<String>(method: ActionMethod.getCountryCode, data: ip);
  }

  @override
  Future<String> getMemory() async {
    return _invoke<String>(method: ActionMethod.getMemory);
  }

  @override
  Future<String> prepareTunHelper() async {
    return _invoke<String>(method: ActionMethod.prepareTunHelper);
  }

  @override
  Future<String> releaseTunHelper() async {
    return _invoke<String>(method: ActionMethod.releaseTunHelper);
  }
}
