import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part '../generated/actions/core_action.g.dart';

@Riverpod(keepAlive: true)
class CoreAction extends _$CoreAction {
  @override
  void build() {}

  Future<void> initCore() async {
    final isInit = await coreController.isInit;

    final version = ref.read(versionProvider);
    if (!isInit) {
      final res = await coreController.init(version);
      commonPrint.log('init result: $res');
    } else {
      await ref.read(proxiesActionProvider.notifier).updateGroups();
    }
  }

  Future<void> connectCore() async {
    ref.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
    final result = await Future.wait([
      coreController.preload(),
      Future.delayed(const Duration(milliseconds: 300)),
    ]);
    final String message = result[0];
    if (message.isNotEmpty) {
      ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
      globalState.showNotifier(message);
      return;
    }
    ref.read(coreStatusProvider.notifier).value = CoreStatus.connected;
  }

  Future<Result<bool>> requestAdmin(bool enableTun) async {
    final realTunEnable = ref.read(realTunEnableProvider);
    if (enableTun != realTunEnable && realTunEnable == false) {
      final code = await system.authorizeCore();
      switch (code) {
        case AuthorizeCode.success:
          // Restart core with elevated privileges, then continue setup.
          // Must not return error — callers treat error as abort.
          await restartCore(ref.read(isStartProvider));
          ref.read(realTunEnableProvider.notifier).value = enableTun;
          return Result.success(enableTun);
        case AuthorizeCode.none:
          break;
        case AuthorizeCode.error:
          enableTun = false;
          break;
      }
    }
    ref.read(realTunEnableProvider.notifier).value = enableTun;
    return Result.success(enableTun);
  }

  Future<void> restartCore([bool start = false]) {
    return serializedSetup(() async {
      final isDisconnected =
          ref.read(coreStatusProvider) == CoreStatus.disconnected;
      ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
      await coreController.shutdown(!isDisconnected);
      await connectCore();
      await initCore();
      final shouldStart = start || ref.read(isStartProvider);
      if (shouldStart) {
        await ref
            .read(setupActionProvider.notifier)
            .updateStatus(true, isInit: true);
      } else {
        await ref
            .read(setupActionProvider.notifier)
            .applyProfileUnlocked(force: true);
      }
    });
  }

  /// Returns true if a full core restart was performed (caller must not double-start).
  Future<bool> tryStartCore([bool start = false]) async {
    if (coreController.isCompleted) return false;
    await restartCore(start);
    return true;
  }

  void handleCoreDisconnected() {
    ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
  }
}

