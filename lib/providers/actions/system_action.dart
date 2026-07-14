import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part '../generated/actions/system_action.g.dart';

Future<void> updateWindowVisibility({
  required Future<bool> Function() isVisible,
  required Future<void> Function() show,
  required Future<void> Function() hide,
}) async {
  if (await isVisible()) {
    await hide();
  } else {
    await show();
  }
}

Future<void> completeExitAfterCoreShutdown({
  required Future<void> Function() destroyCore,
  required Future<void> Function() exitApplication,
  int maxDestroyAttempts = 3,
  Duration destroyTimeout = const Duration(seconds: 5),
  Duration retryDelay = const Duration(milliseconds: 100),
}) async {
  if (maxDestroyAttempts < 1) {
    throw ArgumentError.value(
      maxDestroyAttempts,
      'maxDestroyAttempts',
      'must be positive',
    );
  }
  Object? lastError;
  StackTrace? lastStackTrace;
  var destroyed = false;
  for (var attempt = 1; attempt <= maxDestroyAttempts; attempt++) {
    try {
      await destroyCore().timeout(destroyTimeout);
      destroyed = true;
      break;
    } catch (error, stackTrace) {
      lastError = error;
      lastStackTrace = stackTrace;
      if (attempt < maxDestroyAttempts && retryDelay > Duration.zero) {
        await Future<void>.delayed(retryDelay);
      }
    }
  }
  if (destroyed) {
    await exitApplication();
    return;
  }
  final failure = StateError(
    'Core shutdown failed after $maxDestroyAttempts attempts: $lastError',
  );
  Error.throwWithStackTrace(failure, lastStackTrace ?? StackTrace.current);
}

@Riverpod(keepAlive: true)
class SystemAction extends _$SystemAction {
  @override
  void build() {}

  Future<List<Package>> getPackages() async {
    if (ref.read(isMobileViewProvider)) {
      await Future.delayed(commonDuration);
    }
    if (ref.read(packagesProvider).isEmpty) {
      ref.read(packagesProvider.notifier).value =
          await app?.getPackages() ?? [];
    }
    return ref.read(packagesProvider);
  }

  Future<void> handleExit([bool needSave = true]) async {
    try {
      await Future.wait([
        if (needSave) ref.read(storeActionProvider.notifier).flushPreferences(),
        if (macOS != null) macOS!.updateDns(true),
        if (proxy != null) proxy!.stopProxy(),
        if (tray != null) tray!.destroy(),
      ]);
    } catch (error, stackTrace) {
      commonPrint.log(
        'Exit cleanup failed: $error\n$stackTrace',
        logLevel: LogLevel.warning,
      );
    }
    await completeExitAfterCoreShutdown(
      destroyCore: coreController.destroy,
      exitApplication: system.exit,
    );
    commonPrint.log('exit');
  }

  Future<void> handleClose([bool exit = true]) async {
    if (!system.isDesktop) {
      if (ref.read(backBlockProvider)) return;
    }
    if (ref.read(appSettingProvider).minimizeOnExit || !exit) {
      if (system.isDesktop) {
        await ref.read(storeActionProvider.notifier).flushPreferences();
      }
      await system.back();
    } else {
      await handleExit();
    }
  }

  Future<void> updateVisible() async {
    final currentWindow = window;
    if (currentWindow == null) return;
    await updateWindowVisibility(
      isVisible: () => currentWindow.isVisible,
      show: currentWindow.show,
      hide: currentWindow.hide,
    );
  }

  void updateTun() {
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.tun(enable: !state.tun.enable));
  }

  void updateSystemProxy() {
    ref
        .read(networkSettingProvider.notifier)
        .update((state) => state.copyWith(systemProxy: !state.systemProxy));
  }

  void updateAutoLaunch() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(autoLaunch: !state.autoLaunch));
  }

  Future<void> updateTray() async {
    await tray?.update(
      trayState: ref.read(trayStateProvider),
      traffic: ref.read(
        trafficsProvider.select(
          (state) => state.list.safeLast(const Traffic()),
        ),
      ),
    );
  }

  Future<bool> updateLocalIp({bool Function()? isCurrent}) async {
    final shouldCommit = isCurrent ?? () => true;
    if (ref.read(localIpProvider) != null) {
      ref.read(localIpProvider.notifier).value = null;
    }
    await Future.delayed(commonDuration);
    try {
      final localIp = await utils.getLocalIpAddress();
      if (!shouldCommit()) {
        return false;
      }
      ref.read(localIpProvider.notifier).value = localIp;
      return true;
    } catch (_) {
      if (!shouldCommit()) {
        return false;
      }
      rethrow;
    }
  }
}
