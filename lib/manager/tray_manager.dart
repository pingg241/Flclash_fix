import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';

class TrayManager extends ConsumerStatefulWidget {
  final Widget child;

  const TrayManager({super.key, required this.child});

  @override
  ConsumerState<TrayManager> createState() => _TrayContainerState();
}

class _TrayContainerState extends ConsumerState<TrayManager> with TrayListener {
  void _runPlatformOperation(
    String label,
    FutureOr<void> Function() operation,
  ) {
    unawaited(
      runAsyncSafely(
        operation: operation,
        onError: (error, stackTrace) {
          commonPrint.log(
            '$label failed: $error\n$stackTrace',
            logLevel: LogLevel.warning,
          );
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    ref.listenManual(trayStateProvider, (prev, next) {
      if (prev != next) {
        _runPlatformOperation(
          'Tray update',
          ref.read(systemActionProvider.notifier).updateTray,
        );
      }
    });
    if (system.isMacOS) {
      ref.listenManual(trayTitleStateProvider, (prev, next) {
        if (prev != next) {
          _runPlatformOperation(
            'Tray title update',
            () => tray?.updateTrayTitle(
              showTrayTitle: next.showTrayTitle,
              traffic: next.traffic,
            ),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void onTrayIconRightMouseDown() {
    _runPlatformOperation('Tray menu popup', () {
      // ignore: deprecated_member_use
      return trayManager.popUpContextMenu(bringAppToFront: true);
    });
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    render?.active();
    super.onTrayMenuItemClick(menuItem);
  }

  @override
  void onTrayIconMouseDown() {
    _runPlatformOperation('Window show', () => window?.show());
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    super.dispose();
  }
}
