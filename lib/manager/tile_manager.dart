import 'dart:async';

import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/tile.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@visibleForTesting
Future<void> performTileTransition({
  required bool target,
  required Future<bool> Function() update,
  required bool Function() readCurrent,
  required Future<void> Function() showTip,
}) async {
  final updated = await update();
  if (!updated || readCurrent() != target) {
    throw StateError('tile transition to $target was not confirmed');
  }
  await showTip();
}

class TileManager extends ConsumerStatefulWidget {
  final Widget child;

  const TileManager({super.key, required this.child});

  @override
  ConsumerState<TileManager> createState() => _TileContainerState();
}

class _TileContainerState extends ConsumerState<TileManager> with TileListener {
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  bool get isStart => ref.read(isStartProvider);

  @override
  Future<void> onStart() async {
    if (isStart && coreController.isCompleted) {
      return;
    }
    await performTileTransition(
      target: true,
      update: () => ref.read(setupActionProvider.notifier).updateStatus(true),
      readCurrent: () {
        if (!mounted) {
          throw StateError('tile manager was disposed during start');
        }
        return isStart;
      },
      showTip: () => _showTip(currentAppLocalizations.startVpn),
    );
    await super.onStart();
  }

  @override
  Future<void> onStop() async {
    if (!isStart) {
      return;
    }
    await performTileTransition(
      target: false,
      update: () => ref.read(setupActionProvider.notifier).updateStatus(false),
      readCurrent: () {
        if (!mounted) {
          throw StateError('tile manager was disposed during stop');
        }
        return isStart;
      },
      showTip: () => _showTip(currentAppLocalizations.stopVpn),
    );
    await super.onStop();
  }

  Future<void> _showTip(String message) async {
    final request = app?.tip(message);
    if (request == null) {
      return;
    }
    try {
      await request.timeout(const Duration(seconds: 2));
    } on Object catch (error) {
      commonPrint.log('Failed to show tile status: $error');
    }
  }

  @override
  void initState() {
    super.initState();
    tile?.addListener(this);
  }

  @override
  void dispose() {
    tile?.removeListener(this);
    super.dispose();
  }
}
