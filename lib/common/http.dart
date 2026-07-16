import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String safeHttpEndpoint(Uri url) {
  if (!url.hasScheme || url.host.isEmpty) return '<invalid-url>';
  final host = url.host.contains(':') ? '[${url.host}]' : url.host;
  final port = url.hasPort ? ':${url.port}' : '';
  return '${url.scheme.toLowerCase()}://$host$port';
}

bool _isLoopback(Uri url) {
  final host = url.host.toLowerCase();
  return host == localhost || host == 'localhost' || host == '::1';
}

class FlClashHttpOverrides extends HttpOverrides {
  static bool shouldUseLocalProxy({
    required Uri url,
    required CoreStatus coreStatus,
    required bool isStart,
    required bool isStarting,
    required bool suspend,
  }) {
    return !_isLoopback(url) &&
        coreStatus == CoreStatus.connected &&
        isStart &&
        !isStarting &&
        !suspend;
  }

  static bool usesLocalProxy(Uri url) {
    if (_isLoopback(url)) return false;
    final ref = globalState.container;
    return shouldUseLocalProxy(
      url: url,
      coreStatus: ref.read(coreStatusProvider),
      isStart: ref.read(isStartProvider),
      isStarting: ref.read(isStartingProvider),
      suspend: ref.read(suspendProvider),
    );
  }

  static String handleFindProxy(Uri url) {
    if (_isLoopback(url)) return 'DIRECT';
    final ref = globalState.container;
    final coreStatus = ref.read(coreStatusProvider);
    final isStart = ref.read(isStartProvider);
    final isStarting = ref.read(isStartingProvider);
    final suspend = ref.read(suspendProvider);
    final useLocalProxy = shouldUseLocalProxy(
      url: url,
      coreStatus: coreStatus,
      isStart: isStart,
      isStarting: isStarting,
      suspend: suspend,
    );
    commonPrint.log(
      'find ${safeHttpEndpoint(url)} proxy: core=${coreStatus.name} '
      'start=$isStart starting=$isStarting suspend=$suspend',
    );
    if (!useLocalProxy) return 'DIRECT';
    final mixedPort = ref.read(
      patchClashConfigProvider.select((state) => state.mixedPort),
    );
    return 'PROXY $localhost:$mixedPort';
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = handleFindProxy;
    return client;
  }
}
