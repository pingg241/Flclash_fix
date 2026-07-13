import 'package:fl_clash/common/proxy.dart';
import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProxyManager extends ConsumerStatefulWidget {
  final Widget child;

  const ProxyManager({super.key, required this.child});

  @override
  ConsumerState createState() => _ProxyManagerState();
}

class _ProxyManagerState extends ConsumerState<ProxyManager> {
  Future<void> _pendingUpdate = Future.value();
  int _generation = 0;

  Future<void> _updateProxy(ProxyState proxyState, int generation) async {
    if (generation != _generation) {
      return;
    }
    final isStart = proxyState.isStart;
    final systemProxy = proxyState.systemProxy;
    final port = proxyState.port;
    // isStart is only true after setup+listener succeed, so system proxy is
    // not written to a dead mixed-port during Windows false-start windows.
    if (isStart && systemProxy) {
      await proxy?.startProxy(port, proxyState.bassDomain);
    } else {
      await proxy?.stopProxy();
    }
  }

  void _scheduleUpdateProxy(ProxyState proxyState) {
    final generation = ++_generation;
    _pendingUpdate = _pendingUpdate
        .then((_) => _updateProxy(proxyState, generation))
        .catchError((Object error) {
          commonPrint.log(
            'update system proxy failed: $error',
            logLevel: LogLevel.warning,
          );
          if (generation == _generation &&
              proxyState.isStart &&
              proxyState.systemProxy) {
            ref
                .read(networkSettingProvider.notifier)
                .update((state) => state.copyWith(systemProxy: false));
          }
        });
  }

  @override
  void initState() {
    super.initState();
    _pendingUpdate = (proxy?.recoverProxy() ?? Future.value()).catchError((
      Object error,
    ) {
      commonPrint.log(
        'recover system proxy failed: $error',
        logLevel: LogLevel.warning,
      );
    });
    ref.listenManual(proxyStateProvider, (prev, next) {
      if (prev != next) {
        _scheduleUpdateProxy(next);
      }
    });
    _scheduleUpdateProxy(ref.read(proxyStateProvider));
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
