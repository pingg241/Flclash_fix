import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part '../generated/actions/setup_action.g.dart';

abstract interface class SetupCoreOperations {
  Future<String> setupConfig({
    required SetupParams params,
    required SetupState setupState,
    FutureOr<void> Function()? preloadInvoke,
  });

  Future<bool> startListener();

  Future<bool> stopListener();

  Future<void> resetTraffic();
}

class _DefaultSetupCoreOperations implements SetupCoreOperations {
  const _DefaultSetupCoreOperations();

  @override
  Future<String> setupConfig({
    required SetupParams params,
    required SetupState setupState,
    FutureOr<void> Function()? preloadInvoke,
  }) {
    return coreController.setupConfig(
      params: params,
      setupState: setupState,
      preloadInvoke: preloadInvoke,
    );
  }

  @override
  Future<bool> startListener() => coreController.startListener();

  @override
  Future<bool> stopListener() => coreController.stopListener();

  @override
  Future<void> resetTraffic() => coreController.resetTraffic();
}

final setupCoreOperationsProvider = Provider<SetupCoreOperations>(
  (_) => const _DefaultSetupCoreOperations(),
);

@visibleForTesting
Future<void> requireSuccessfulListenerStart(
  Future<bool> Function() startListener,
) async {
  if (!await startListener()) {
    throw StateError('start listener failed');
  }
}

typedef ConfigFileWriter = Future<void> Function(String yaml);
typedef SharedStatePersister = Future<void> Function(SharedState state);
typedef PostApplyFailureReporter =
    void Function(Object error, StackTrace stackTrace);
typedef PostApplyRetryDelay = Future<void> Function(Duration duration);
typedef PostApplySnapshotInvalidator = void Function();

const _postApplyRefreshAttempts = 3;
const _postApplyRefreshRetryDelay = Duration(milliseconds: 100);

@visibleForTesting
Future<bool> runPostApplyRefresh({
  required FutureOr<void> Function()? refresh,
  required bool tolerateFailure,
  required PostApplyFailureReporter reportFailure,
  int maxAttempts = 1,
  Duration retryDelay = Duration.zero,
  PostApplyRetryDelay? delay,
  FutureOr<void> Function()? onFinalFailure,
}) async {
  if (maxAttempts < 1) {
    throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be positive');
  }
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      await refresh?.call();
      return true;
    } catch (error, stackTrace) {
      if (!tolerateFailure) rethrow;
      if (attempt < maxAttempts) {
        await (delay ?? _delayPostApplyRefresh)(retryDelay);
        continue;
      }
      try {
        await onFinalFailure?.call();
      } catch (invalidationError, invalidationStackTrace) {
        reportFailure(invalidationError, invalidationStackTrace);
      }
      reportFailure(error, stackTrace);
      return false;
    }
  }
  return false;
}

Future<void> _delayPostApplyRefresh(Duration duration) =>
    Future<void>.delayed(duration);

final configFileWriterProvider = Provider<ConfigFileWriter>((_) {
  return (yaml) async {
    final configFilePath = await appPath.configFilePath;
    await File(configFilePath).safeWriteAsString(yaml);
  };
});
final sharedStatePersisterProvider = Provider<SharedStatePersister>(
  (_) => preferences.saveShareState,
);
final postApplyRetryDelayProvider = Provider<PostApplyRetryDelay>(
  (_) => _delayPostApplyRefresh,
);
final postApplySnapshotInvalidatorProvider =
    Provider<PostApplySnapshotInvalidator>((ref) {
      return () {
        ref.read(groupsProvider.notifier).value = [];
        ref.read(providersProvider.notifier).value = [];
      };
    });

@visibleForTesting
Future<void> persistSharedStateBeforeService({
  required SharedState state,
  required SharedStatePersister persist,
}) {
  return persist(state);
}

@Riverpod(keepAlive: true)
class SetupAction extends _$SetupAction {
  Timer? _updateTimer;
  DateTime? startTime;
  Future<bool>? _statusOperation;
  bool? _statusTarget;

  bool get isStart => startTime != null && startTime!.isBeforeNow;

  @override
  void build() {}

  SetupParams get _setupParams {
    final selectedMap = ref.read(selectedMapProvider);
    final testUrl = ref.read(
      appSettingProvider.select((state) => state.testUrl),
    );
    return SetupParams(selectedMap: selectedMap, testUrl: testUrl);
  }

  Future<void> fullSetup({bool toleratePostApplyFailure = false}) {
    if (!ref.read(initProvider)) {
      return Future<void>.value();
    }
    return serializedSetup(() async {
      ref.read(delayDataSourceProvider.notifier).value = {};
      await applyProfileUnlocked(
        force: true,
        toleratePostApplyFailure: toleratePostApplyFailure,
      );
      ref.read(logsProvider.notifier).value = FixedList(maxLength);
      ref.read(requestsProvider.notifier).value = FixedList(maxLength);
    });
  }

  /// Marks session as running and starts the 1Hz timer.
  /// Call only after config is applied and listener/VPN is up.
  void _markRunning() {
    startTime ??= DateTime.now();
    ref.read(commonActionProvider.notifier).updateRunTime();
    ref.read(commonActionProvider.notifier).updateTraffic();
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      ref.read(commonActionProvider.notifier).updateRunTime();
      ref.read(commonActionProvider.notifier).updateTraffic();
    });
  }

  Future<void> _startListenerOrVpn() async {
    if (ref.read(suspendProvider)) {
      return;
    }
    await requireSuccessfulListenerStart(
      ref.read(setupCoreOperationsProvider).startListener,
    );
  }

  Future<void> _updateStartTime() async {
    startTime = await service?.getRunTime();
  }

  Future<bool> handleStop() async {
    final stopped = await ref.read(setupCoreOperationsProvider).stopListener();
    if (!stopped) {
      commonPrint.log('stopListener failed', logLevel: LogLevel.error);
      return false;
    }
    await _releaseMacTunHelper();
    ref.read(commonActionProvider.notifier).invalidateTraffic();
    startTime = null;
    _updateTimer?.cancel();
    _updateTimer = null;
    await ref.read(setupCoreOperationsProvider).resetTraffic();
    ref.read(trafficsProvider.notifier).clear();
    ref.read(totalTrafficProvider.notifier).value = const Traffic();
    ref.read(runTimeProvider.notifier).value = null;
    return true;
  }

  Future<void> _releaseMacTunHelper() async {
    if (!system.isMacOS) {
      return;
    }
    try {
      await coreController.releaseTunHelper();
    } catch (error) {
      commonPrint.log(
        'Failed to release the macOS TUN helper: $error',
        logLevel: LogLevel.error,
      );
    } finally {
      if (ref.mounted) {
        ref.read(realTunEnableProvider.notifier).value = false;
      }
    }
  }

  Future<void> _rollbackStart() async {
    if (!await handleStop()) {
      commonPrint.log('start rollback failed', logLevel: LogLevel.error);
    }
  }

  Future<void> initStatus() async {
    if (!ref.read(needInitStatusProvider)) {
      commonPrint.log('init status cancel');
      return;
    }
    commonPrint.log('init status');
    if (system.isAndroid) {
      await _updateStartTime();
    }
    final status = isStart == true
        ? true
        : ref.read(appSettingProvider).autoRun;
    if (status == true) {
      if (!await updateStatus(true, isInit: true)) {
        throw StateError('initial core start was not confirmed');
      }
    } else {
      await applyProfile(force: true);
    }
  }

  /// Start/stop proxy session.
  ///
  /// Ready means: core connected, profile applied, listener/VPN started.
  /// UI [isStartProvider] only becomes true after [startTime] is set on success.
  /// System proxy (Windows/desktop) keys off [isStartProvider], so it must not
  /// flip true until the local mixed port is actually serving.
  Future<bool> updateStatus(bool wantStart, {bool isInit = false}) async {
    final activeOperation = _statusOperation;
    if (activeOperation != null && _statusTarget == wantStart) {
      return activeOperation;
    }
    late final Future<bool> operation;
    operation = serializedSetup(() => _updateStatus(wantStart, isInit: isInit))
        .whenComplete(() {
          if (identical(_statusOperation, operation)) {
            _statusOperation = null;
            _statusTarget = null;
          }
        });
    _statusOperation = operation;
    _statusTarget = wantStart;
    return operation;
  }

  Future<bool> _updateStatus(bool wantStart, {required bool isInit}) async {
    if (wantStart) {
      if (!isInit && isStart) {
        return true;
      }
      ref.read(isStartingProvider.notifier).value = true;
      try {
        await ref.read(coreActionProvider.notifier).ensureCoreConnected();
        if (!ref.read(initProvider)) {
          commonPrint.log('start aborted: app not init');
          return false;
        }
        var listenerStarted = false;
        try {
          await applyProfileUnlocked(
            force: true,
            silence: true,
            preloadInvoke: () async {
              await _startListenerOrVpn();
              listenerStarted = true;
            },
          );
          if (!listenerStarted) {
            await _startListenerOrVpn();
          }
          _markRunning();
          if (isInit) {
            ref.read(needInitStatusProvider.notifier).value = false;
          }
          ref.read(checkIpNumProvider.notifier).add();
          return true;
        } catch (error, stackTrace) {
          final message = error.toString();
          commonPrint.log('start failed: $message', logLevel: LogLevel.error);
          try {
            await _rollbackStart();
          } catch (rollbackError, rollbackStackTrace) {
            commonPrint.log(
              'start rollback error: $rollbackError\n$rollbackStackTrace',
              logLevel: LogLevel.error,
            );
          }
          if (ref.mounted) {
            globalState.showNotifier(message);
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
      } finally {
        if (ref.mounted) {
          ref.read(isStartingProvider.notifier).value = false;
        }
      }
    } else {
      ref.read(isStartingProvider.notifier).value = true;
      try {
        final stopped = await handleStop();
        if (!stopped) {
          return false;
        }
        ref.read(checkIpNumProvider.notifier).add();
        return true;
      } finally {
        if (ref.mounted) {
          ref.read(isStartingProvider.notifier).value = false;
        }
      }
    }
  }

  Future<void> updateConfigDebounce() async {
    debouncer.call(FunctionTag.updateConfig, () async {
      await globalState.safeRun(() async {
        final updateParams = ref.read(updateParamsProvider);
        final hadTunAuthorization = ref.read(realTunEnableProvider);
        final shouldActivateTun = updateParams.tun.enable && isStart;
        final res = await _requestAdmin(shouldActivateTun);
        if (res.isError) return;
        final realTunEnable = ref.read(realTunEnableProvider);
        try {
          final message = await coreController.updateConfig(
            updateParams.copyWith.tun(enable: realTunEnable),
          );
          ref.read(checkIpNumProvider.notifier).add();
          if (message.isNotEmpty) throw message;
          if (!realTunEnable) {
            await _releaseMacTunHelper();
          }
        } catch (_) {
          if (system.isMacOS && !hadTunAuthorization && realTunEnable) {
            await _releaseMacTunHelper();
          }
          rethrow;
        }
      });
    });
  }

  void tryCheckIp() {
    final isTimeout = ref.read(
      networkDetectionProvider.select(
        (state) => state.ipInfo == null && state.isLoading == false,
      ),
    );
    if (!isTimeout) return;
    ref.read(checkIpNumProvider.notifier).add();
  }

  void applyProfileDebounce({bool silence = false, bool force = false}) {
    debouncer.call(FunctionTag.applyProfile, (silence, force) {
      applyProfile(silence: silence, force: force);
    }, args: [silence, force]);
  }

  void changeMode(Mode mode) {
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: mode));
    if (mode == Mode.global) {
      globalState.safeRun<void>(
        () => ref
            .read(proxiesActionProvider.notifier)
            .updateCurrentGroupName(GroupName.GLOBAL.name),
      );
    }
  }

  void autoApplyProfile() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      applyProfile();
    });
  }

  Future<void> applyProfile({
    bool silence = false,
    bool force = false,
    FutureOr<void> Function()? preloadInvoke,
  }) {
    return serializedSetup(
      () => applyProfileUnlocked(
        silence: silence,
        force: force,
        preloadInvoke: preloadInvoke,
      ),
    );
  }

  Future<void> applyProfileUnlocked({
    bool silence = false,
    bool force = false,
    FutureOr<void> Function()? preloadInvoke,
    bool toleratePostApplyFailure = false,
  }) async {
    await _setupConfig(
      force: force,
      silence: silence,
      preloadInvoke: preloadInvoke,
      toleratePostApplyFailure: toleratePostApplyFailure,
      onUpdated: () async {
        await ref
            .read(proxiesActionProvider.notifier)
            .updateGroups(rethrowOnFailure: true);
        await ref.read(providersProvider.notifier).syncProviders();
      },
    );
  }

  Future<VM2<String, String>> getProfile({
    required SetupState setupState,
    required PatchClashConfig patchConfig,
  }) async {
    final profileId = setupState.profileId;
    if (profileId == null) return const VM2('', '');
    final defaultUA = globalState.packageInfo.ua;
    final networkVM2 = ref.read(
      networkSettingProvider.select(
        (state) => VM2(state.appendSystemDns, state.routeMode),
      ),
    );
    final overrideDns = ref.read(overrideDnsProvider);
    final appendSystemDns = networkVM2.a;
    final routeMode = networkVM2.b;
    final configMap = await coreController.getConfig(profileId);
    String? scriptContent;
    final List<Rule> addedRules = [];
    final List<ProxyGroup> proxyGroups = [];
    final List<Rule> rules = [];
    if (setupState.overwriteType == OverwriteType.script) {
      scriptContent = await setupState.script?.content;
    } else if (setupState.overwriteType == OverwriteType.standard) {
      addedRules.addAll(setupState.addedRules);
    } else {
      proxyGroups.addAll(setupState.proxyGroups);
      rules.addAll(setupState.rules);
    }
    final realPatchConfig = patchConfig.copyWith(
      tun: patchConfig.tun.getRealTun(routeMode),
    );
    Map<String, dynamic> rawConfig = configMap;
    if (scriptContent?.isNotEmpty == true) {
      rawConfig = await handleEvaluate(scriptContent!, rawConfig);
    }
    final directory = await appPath.profilesPath;
    final res = makeRealProfileTask(
      MakeRealProfileState(
        rules: rules,
        proxyGroups: proxyGroups,
        profilesPath: directory,
        profileId: profileId,
        rawConfig: rawConfig,
        realPatchConfig: realPatchConfig,
        overrideDns: overrideDns,
        appendSystemDns: appendSystemDns,
        addedRules: addedRules,
        defaultUA: defaultUA,
      ),
      overrideProfileData: setupState.overwriteType == OverwriteType.custom,
    );
    return res;
  }

  Future<String> getProfileWithId(int profileId) async {
    try {
      final setupState = await ref.read(setupStateProvider(profileId).future);
      final patchClashConfig = ref.read(patchClashConfigProvider);
      final res = await getProfile(
        setupState: setupState,
        patchConfig: patchClashConfig,
      );
      return res.a;
    } catch (e) {
      globalState.showNotifier(e.toString());
    }
    return '';
  }

  Future<Result<bool>> _requestAdmin(bool enableTun) {
    return ref.read(coreActionProvider.notifier).requestAdmin(enableTun);
  }

  Future<void> _setupConfig({
    bool force = false,
    bool silence = false,
    FutureOr<void> Function()? preloadInvoke,
    FutureOr<void> Function()? onUpdated,
    bool toleratePostApplyFailure = false,
  }) async {
    var profile = ref.read(currentProfileProvider);
    final nextProfile = await profile?.checkAndUpdateAndCopy();
    if (nextProfile != null) {
      profile = nextProfile;
      await ref.read(profilesProvider.notifier).put(nextProfile);
    }
    commonPrint.log('setup ===> ${profile?.id}');
    final patchConfig = ref.read(patchClashConfigProvider);
    final shouldActivateTun =
        patchConfig.tun.enable && (isStart || preloadInvoke != null);
    final realPatchConfig = patchConfig.copyWith.tun(enable: shouldActivateTun);
    final setupState = await ref.read(setupStateProvider(profile?.id).future);
    if (system.isAndroid) {
      ref.read(lastVpnStateProvider.notifier).value = ref.read(
        vpnStateProvider,
      );
      final sharedState = ref.read(sharedStateProvider);
      await persistSharedStateBeforeService(
        state: sharedState,
        persist: ref.read(sharedStatePersisterProvider),
      );
    }
    final vm2 = await getProfile(
      setupState: setupState,
      patchConfig: realPatchConfig,
    );
    final yamlString = vm2.a;
    final yamlMd5 = vm2.b;
    final res = await _requestAdmin(shouldActivateTun);
    if (res.isError) {
      // Denied or hard failure — do not silently continue as if configured.
      if (res.message.isNotEmpty) {
        throw res.message;
      }
      throw 'request admin failed';
    }
    final realTunEnable = ref.read(realTunEnableProvider);
    if (realTunEnable != shouldActivateTun) {
      throw StateError('TUN authorization state did not match the request');
    }
    if (yamlMd5 == ref.read(lastConfigMd5Provider) && force == false) {
      // Config unchanged: still run preload (e.g. start listener) if requested.
      await preloadInvoke?.call();
      return;
    }
    final loading = !silence
        ? ref.read(loadingProvider(LoadingTag.proxies).notifier)
        : null;
    loading?.start();
    try {
      await ref.read(configFileWriterProvider)(yamlString);
      final message = await ref
          .read(setupCoreOperationsProvider)
          .setupConfig(
            setupState: setupState,
            params: _setupParams,
            preloadInvoke: preloadInvoke,
          );
      if (message.isNotEmpty) {
        throw message;
      }
      final refreshSucceeded = await runPostApplyRefresh(
        refresh: onUpdated,
        tolerateFailure: toleratePostApplyFailure,
        maxAttempts: toleratePostApplyFailure ? _postApplyRefreshAttempts : 1,
        retryDelay: _postApplyRefreshRetryDelay,
        delay: ref.read(postApplyRetryDelayProvider),
        onFinalFailure: toleratePostApplyFailure
            ? ref.read(postApplySnapshotInvalidatorProvider)
            : null,
        reportFailure: (error, stackTrace) {
          commonPrint.log(
            'Profile config applied but UI refresh failed: '
            '$error\n$stackTrace',
            logLevel: LogLevel.warning,
          );
          if (!silence) {
            globalState.showNotifier(error.toString());
          }
        },
      );
      if (!realTunEnable) {
        await _releaseMacTunHelper();
      }
      if (refreshSucceeded) {
        ref.read(lastConfigMd5Provider.notifier).value = yamlMd5;
      }
      ref.read(checkIpNumProvider.notifier).add();
    } finally {
      await loading?.stop();
    }
  }
}
