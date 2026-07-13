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

@Riverpod(keepAlive: true)
class SetupAction extends _$SetupAction {
  Timer? _updateTimer;
  DateTime? startTime;
  int _statusGeneration = 0;

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

  Future<void> fullSetup() {
    if (!ref.read(initProvider)) {
      return Future<void>.value();
    }
    return serializedSetup(() async {
      ref.read(delayDataSourceProvider.notifier).value = {};
      await applyProfileUnlocked(force: true);
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

  /// Starts core listeners / Android VPN. Returns false on failure.
  Future<bool> _startListenerOrVpn() async {
    if (ref.read(suspendProvider)) {
      return true;
    }
    final ok = await coreController.startListener();
    if (!ok) {
      commonPrint.log('startListener failed', logLevel: LogLevel.error);
    }
    return ok;
  }

  Future _updateStartTime() async {
    startTime = await service?.getRunTime();
  }

  Future handleStop() async {
    startTime = null;
    _updateTimer?.cancel();
    _updateTimer = null;
    await coreController.stopListener();
  }

  Future<void> _rollbackStart() async {
    await handleStop();
    coreController.resetTraffic();
    ref.read(trafficsProvider.notifier).clear();
    ref.read(totalTrafficProvider.notifier).value = const Traffic();
    ref.read(runTimeProvider.notifier).value = null;
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
      await updateStatus(true, isInit: true);
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
  Future<void> updateStatus(bool wantStart, {bool isInit = false}) async {
    final gen = ++_statusGeneration;
    if (wantStart) {
      // Block double-taps; allow nested re-entry from restartCore (isInit).
      if (ref.read(isStartingProvider) && !isInit) {
        commonPrint.log('start ignored: already starting');
        return;
      }
      if (!isInit && isStart) {
        return;
      }
      final ownsStartingFlag = !ref.read(isStartingProvider);
      if (ownsStartingFlag) {
        ref.read(isStartingProvider.notifier).value = true;
      }
      try {
        // Ensure core is connected; restartCore may re-enter updateStatus(isInit).
        final restarted = await ref
            .read(coreActionProvider.notifier)
            .tryStartCore(true);
        if (gen != _statusGeneration) return;
        if (restarted) {
          // Nested updateStatus already finished the start path.
          return;
        }
        if (!ref.read(initProvider)) {
          commonPrint.log('start aborted: app not init');
          return;
        }
        if (isInit) {
          ref.read(needInitStatusProvider.notifier).value = false;
        }
        // Apply profile first (await), then listener/VPN, then mark running.
        var listenerStarted = false;
        try {
          await applyProfile(
            force: true,
            silence: true,
            preloadInvoke: () async {
              if (gen != _statusGeneration) return;
              final ok = await _startListenerOrVpn();
              listenerStarted = ok;
              if (!ok) {
                throw 'start listener failed';
              }
            },
          );
          if (gen != _statusGeneration) {
            await _rollbackStart();
            return;
          }
          // md5 short-circuit still runs preloadInvoke; if not, start here.
          if (!listenerStarted) {
            final ok = await _startListenerOrVpn();
            if (!ok) {
              throw 'start listener failed';
            }
          }
          if (gen != _statusGeneration) {
            await _rollbackStart();
            return;
          }
          _markRunning();
          ref.read(checkIpNumProvider.notifier).add();
        } catch (e) {
          commonPrint.log('start failed: $e', logLevel: LogLevel.error);
          await _rollbackStart();
          if (ref.mounted) {
            globalState.showNotifier(e.toString());
          }
        }
      } finally {
        if (ownsStartingFlag && ref.mounted && gen == _statusGeneration) {
          ref.read(isStartingProvider.notifier).value = false;
        }
      }
    } else {
      final ownsStartingFlag = !ref.read(isStartingProvider);
      if (ownsStartingFlag) {
        ref.read(isStartingProvider.notifier).value = true;
      }
      try {
        await handleStop();
        coreController.resetTraffic();
        ref.read(trafficsProvider.notifier).clear();
        ref.read(totalTrafficProvider.notifier).value = const Traffic();
        ref.read(runTimeProvider.notifier).value = null;
        ref.read(checkIpNumProvider.notifier).add();
      } finally {
        if (ownsStartingFlag && ref.mounted && gen == _statusGeneration) {
          ref.read(isStartingProvider.notifier).value = false;
        }
      }
    }
  }

  Future<void> updateConfigDebounce() async {
    debouncer.call(FunctionTag.updateConfig, () async {
      await globalState.safeRun(() async {
        final updateParams = ref.read(updateParamsProvider);
        final res = await _requestAdmin(updateParams.tun.enable);
        if (res.isError) return;
        final realTunEnable = ref.read(realTunEnableProvider);
        final message = await coreController.updateConfig(
          updateParams.copyWith.tun(enable: realTunEnable),
        );
        ref.read(checkIpNumProvider.notifier).add();
        if (message.isNotEmpty) throw message;
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
      ref
          .read(proxiesActionProvider.notifier)
          .updateCurrentGroupName(GroupName.GLOBAL.name);
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
  }) async {
    await _setupConfig(
      force: force,
      silence: silence,
      preloadInvoke: preloadInvoke,
      onUpdated: () async {
        await ref.read(proxiesActionProvider.notifier).updateGroups();
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
    FutureOr Function()? onUpdated,
  }) async {
    var profile = ref.read(currentProfileProvider);
    final nextProfile = await profile?.checkAndUpdateAndCopy();
    if (nextProfile != null) {
      profile = nextProfile;
      ref.read(profilesProvider.notifier).put(nextProfile);
    }
    commonPrint.log('setup ===> ${profile?.id}');
    final patchConfig = ref.read(patchClashConfigProvider);
    final res = await _requestAdmin(patchConfig.tun.enable);
    if (res.isError) {
      // Denied or hard failure — do not silently continue as if configured.
      if (res.message.isNotEmpty) {
        throw res.message;
      }
      throw 'request admin failed';
    }
    final realTunEnable = ref.read(realTunEnableProvider);
    final realPatchConfig = patchConfig.copyWith.tun(enable: realTunEnable);
    final setupState = await ref.read(setupStateProvider(profile?.id).future);
    if (system.isAndroid) {
      ref.read(lastVpnStateProvider.notifier).value = ref.read(vpnStateProvider);
      final sharedState = ref.read(sharedStateProvider);
      preferences.saveShareState(sharedState);
    }
    final vm2 = await getProfile(
      setupState: setupState,
      patchConfig: realPatchConfig,
    );
    final yamlString = vm2.a;
    final yamlMd5 = vm2.b;
    if (yamlMd5 == ref.read(lastConfigMd5Provider) && force == false) {
      // Config unchanged: still run preload (e.g. start listener) if requested.
      await preloadInvoke?.call();
      return;
    }
    await globalState.loadingRun(
      () async {
        final configFilePath = await appPath.configFilePath;
        await File(configFilePath).safeWriteAsString(yamlString);
        ref.read(lastConfigMd5Provider.notifier).value = yamlMd5;
        final message = await coreController.setupConfig(
          setupState: setupState,
          params: _setupParams,
          preloadInvoke: preloadInvoke,
        );
        if (message.isNotEmpty && !message.endsWith('is empty')) {
          throw message;
        }
        ref.read(checkIpNumProvider.notifier).add();
        await onUpdated?.call();
      },
      silence: true,
      tag: !silence ? LoadingTag.proxies : null,
    );
  }
}
