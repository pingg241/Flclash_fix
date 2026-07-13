import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:wifi_ssid/wifi_ssid.dart';

class ConnectivityManager extends StatefulWidget {
  final FutureOr<void> Function(List<ConnectivityResult> results)?
  onConnectivityChanged;
  final Widget child;

  const ConnectivityManager({
    super.key,
    this.onConnectivityChanged,
    required this.child,
  });

  @override
  State<ConnectivityManager> createState() => _ConnectivityManagerState();
}

class _ConnectivityManagerState extends State<ConnectivityManager> {
  late final StreamSubscription<List<ConnectivityResult>> _subscription;
  int _connectivityGeneration = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _subscription = Connectivity().onConnectivityChanged.listen(
      _handleConnectivityChanged,
      onError: (Object error, StackTrace stackTrace) {
        commonPrint.log(
          'Connectivity stream failed: $error\n$stackTrace',
          logLevel: LogLevel.warning,
        );
      },
    );
  }

  void _handleConnectivityChanged(List<ConnectivityResult> results) {
    if (_disposed) {
      return;
    }
    final generation = ++_connectivityGeneration;
    globalState.container.read(currentSSIDProvider.notifier).value = null;
    if (results.contains(ConnectivityResult.wifi)) {
      unawaited(_updateSsid(generation));
    }
    final callback = widget.onConnectivityChanged;
    if (callback != null) {
      unawaited(
        Future<void>.sync(() => callback(results)).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          commonPrint.log(
            'Connectivity callback failed: $error\n$stackTrace',
            logLevel: LogLevel.warning,
          );
        }),
      );
    }
  }

  Future<void> _updateSsid(int generation) async {
    try {
      final ssid = await WifiSsidManager.instance.getSsid();
      if (_disposed || !mounted || generation != _connectivityGeneration) {
        return;
      }
      globalState.container.read(currentSSIDProvider.notifier).value = ssid;
      commonPrint.log('Wi-fi SSID: $ssid', logLevel: LogLevel.info);
    } catch (error, stackTrace) {
      if (_disposed || generation != _connectivityGeneration) {
        return;
      }
      commonPrint.log(
        'Failed to read Wi-fi SSID: $error\n$stackTrace',
        logLevel: LogLevel.warning,
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _connectivityGeneration++;
    unawaited(
      _subscription.cancel().catchError((Object error, StackTrace stackTrace) {
        commonPrint.log(
          'Failed to cancel connectivity subscription: '
          '$error\n$stackTrace',
          logLevel: LogLevel.warning,
        );
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
