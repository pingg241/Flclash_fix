import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part '../generated/actions/core_action.g.dart';

abstract interface class CoreLifecycleOperations {
  bool get isCompleted;

  Future<String> preload();

  Future<bool> get isInit;

  Future<bool> init(int version);

  Future<bool> shutdown(bool isUser);
}

class _DefaultCoreLifecycleOperations implements CoreLifecycleOperations {
  const _DefaultCoreLifecycleOperations();

  @override
  bool get isCompleted => coreController.isCompleted;

  @override
  Future<String> preload() => coreController.preload();

  @override
  Future<bool> get isInit async => await coreController.isInit;

  @override
  Future<bool> init(int version) => coreController.init(version);

  @override
  Future<bool> shutdown(bool isUser) => coreController.shutdown(isUser);
}

final coreLifecycleOperationsProvider = Provider<CoreLifecycleOperations>(
  (_) => const _DefaultCoreLifecycleOperations(),
);

@Riverpod(keepAlive: true)
class CoreAction extends _$CoreAction {
  @override
  void build() {}

  Future<void> initCore() async {
    final operations = ref.read(coreLifecycleOperationsProvider);
    final isInit = await operations.isInit;

    final version = ref.read(versionProvider);
    if (!isInit) {
      final res = await operations.init(version);
      commonPrint.log('init result: $res');
      if (!res) {
        throw StateError('core initialization failed');
      }
    } else {
      await ref.read(proxiesActionProvider.notifier).updateGroups();
    }
  }

  Future<void> connectCore() async {
    ref.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
    try {
      final result = await Future.wait([
        ref.read(coreLifecycleOperationsProvider).preload(),
        Future.delayed(const Duration(milliseconds: 300)),
      ]);
      final String message = result[0];
      if (message.isNotEmpty) {
        globalState.showNotifier(message);
        throw StateError(message);
      }
      ref.read(coreStatusProvider.notifier).value = CoreStatus.connected;
      if (system.isMacOS) {
        // A sidecar is bound to one core process and never survives reconnect.
        ref.read(realTunEnableProvider.notifier).value = false;
      }
    } catch (_) {
      ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
      rethrow;
    }
  }

  Future<Result<bool>> requestAdmin(bool enableTun) async {
    final realTunEnable = ref.read(realTunEnableProvider);
    if (system.isMacOS && enableTun) {
      final code = await system.authorizeCore();
      if (code == AuthorizeCode.error) {
        ref.read(realTunEnableProvider.notifier).value = false;
        return Result.error('TUN authorization failed');
      }
      ref.read(realTunEnableProvider.notifier).value = true;
      return Result.success(true);
    }
    if (enableTun != realTunEnable && realTunEnable == false) {
      final code = await system.authorizeCore();
      switch (code) {
        case AuthorizeCode.success:
          await serializedSetup(_restartCoreTransport);
          ref.read(realTunEnableProvider.notifier).value = enableTun;
          return Result.success(enableTun);
        case AuthorizeCode.none:
          break;
        case AuthorizeCode.error:
          return Result.error('TUN authorization failed');
      }
    }
    ref.read(realTunEnableProvider.notifier).value = enableTun;
    return Result.success(enableTun);
  }

  Future<void> restartCore([bool start = false]) {
    return serializedSetup(() async {
      final shouldStart = start || ref.read(isStartProvider);
      await _restartCoreTransport();
      if (shouldStart) {
        final started = await ref
            .read(setupActionProvider.notifier)
            .updateStatus(true, isInit: true);
        if (!started) {
          throw StateError('core session restart was not confirmed');
        }
      } else {
        await ref
            .read(setupActionProvider.notifier)
            .applyProfileUnlocked(force: true);
      }
    });
  }

  Future<void> _restartCoreTransport() async {
    final isDisconnected =
        ref.read(coreStatusProvider) == CoreStatus.disconnected;
    final operations = ref.read(coreLifecycleOperationsProvider);
    var shutdown = false;
    var transportDisconnected = false;
    try {
      shutdown = await operations.shutdown(!isDisconnected);
    } finally {
      transportDisconnected = !operations.isCompleted;
      if (transportDisconnected) {
        ref.read(commonActionProvider.notifier).invalidateTraffic();
        ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
      }
    }
    if (!shutdown) {
      throw StateError('core shutdown was not confirmed');
    }
    if (!transportDisconnected) {
      throw StateError('core shutdown returned success while still connected');
    }
    await connectCore();
    await initCore();
  }

  /// Ensures the transport is connected without re-entering session setup.
  Future<bool> ensureCoreConnected() async {
    if (ref.read(coreLifecycleOperationsProvider).isCompleted) return false;
    await serializedSetup(_restartCoreTransport);
    return true;
  }

  /// Returns true if a full core restart was performed (caller must not double-start).
  Future<bool> tryStartCore([bool start = false]) async {
    if (ref.read(coreLifecycleOperationsProvider).isCompleted) return false;
    await restartCore(start);
    return true;
  }

  void handleCoreDisconnected() {
    ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
  }
}
