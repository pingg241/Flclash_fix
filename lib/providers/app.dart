import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wifi_ssid/wifi_ssid.dart';

part 'generated/app.g.dart';

typedef IpInfoLoader =
    Future<Result<IpInfo?>> Function(
      CancelToken cancelToken,
      bool useLocalProxy,
    );

final ipInfoLoaderProvider = Provider<IpInfoLoader>(
  (_) =>
      (cancelToken, useLocalProxy) => request.checkIp(
        cancelToken: cancelToken,
        useLocalProxy: useLocalProxy,
      ),
);

typedef IpCheckForegroundGate = bool Function();

final ipCheckForegroundGateProvider = Provider<IpCheckForegroundGate>(
  (_) =>
      () => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
);

typedef _IpCheckOwner = ({
  CancelToken cancelToken,
  int generation,
  bool usesLocalProxy,
});

@riverpod
class RealTunEnable extends _$RealTunEnable with AutoDisposeNotifierMixin {
  @override
  bool build() {
    return false;
  }
}

@Riverpod(keepAlive: true)
class Logs extends _$Logs with AutoDisposeNotifierMixin {
  Timer? _notifyTimer;

  @override
  FixedList<Log> build() {
    ref.onDispose(() => _notifyTimer?.cancel());
    return FixedList(maxLength);
  }

  void add(Log value) {
    if (!ref.mounted) {
      return;
    }
    state.add(value);
    _scheduleNotification();
  }

  void _scheduleNotification() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 50), () {
      _notifyTimer = null;
      if (ref.mounted) {
        value = state.copyWith();
      }
    });
  }

  Future<bool> exportLogs() async {
    final logString = await encodeLogsTask(value.list);
    final tempFilePath = await appPath.tempFilePath;
    final file = File(tempFilePath);
    await file.safeWriteAsString(logString);
    bool res = false;
    res = await picker.saveFileWithPath(utils.logFile, tempFilePath) != null;
    return res;
  }
}

@Riverpod(keepAlive: true)
class Requests extends _$Requests with AutoDisposeNotifierMixin {
  Timer? _notifyTimer;

  @override
  FixedList<TrackerInfo> build() {
    ref.onDispose(() => _notifyTimer?.cancel());
    return FixedList(maxLength);
  }

  void addRequest(TrackerInfo value) {
    if (!ref.mounted) {
      return;
    }
    state.add(value);
    _scheduleNotification();
  }

  void _scheduleNotification() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 50), () {
      _notifyTimer = null;
      if (ref.mounted) {
        value = state.copyWith();
      }
    });
  }
}

@Riverpod(keepAlive: true)
class Providers extends _$Providers with AutoDisposeNotifierMixin {
  @override
  List<ExternalProvider> build() {
    return [];
  }

  void setProvider(ExternalProvider? provider) {
    if (provider == null) return;
    final index = value.indexWhere((item) => item.name == provider.name);
    if (index == -1) return;
    final newState = List<ExternalProvider>.from(value)..[index] = provider;
    value = newState;
  }

  Future<void> syncProviders() async {
    value = await coreController.getExternalProviders();
  }
}

@Riverpod(keepAlive: true)
class Packages extends _$Packages with AutoDisposeNotifierMixin {
  @override
  List<Package> build() {
    return [];
  }
}

@Riverpod(keepAlive: true)
class SystemBrightness extends _$SystemBrightness
    with AutoDisposeNotifierMixin {
  @override
  Brightness build() {
    return Brightness.dark;
  }
}

@Riverpod(keepAlive: true)
class Traffics extends _$Traffics with AutoDisposeNotifierMixin {
  @override
  FixedList<Traffic> build() {
    return FixedList(30);
  }

  void addTraffic(Traffic traffic) {
    final next = state.copyWith();
    next.add(traffic);
    value = next;
  }

  void clear() {
    value = FixedList(state.maxLength);
  }
}

@Riverpod(keepAlive: true)
class TotalTraffic extends _$TotalTraffic with AutoDisposeNotifierMixin {
  @override
  Traffic build() {
    return const Traffic();
  }
}

@Riverpod(keepAlive: true)
class LocalIp extends _$LocalIp with AutoDisposeNotifierMixin {
  @override
  String? build() {
    return null;
  }
}

@Riverpod(keepAlive: true)
class RunTime extends _$RunTime with AutoDisposeNotifierMixin {
  @override
  int? build() {
    return null;
  }
}

@Riverpod(keepAlive: true)
class ViewSize extends _$ViewSize with AutoDisposeNotifierMixin {
  @override
  Size build() {
    return Size.zero;
  }
}

@Riverpod(keepAlive: true)
class SideWidth extends _$SideWidth with AutoDisposeNotifierMixin {
  @override
  double build() {
    return 0;
  }
}

@Riverpod(keepAlive: true)
double viewWidth(Ref ref) {
  return ref.watch(viewSizeProvider).width;
}

@Riverpod(keepAlive: true)
ViewMode viewMode(Ref ref) {
  return utils.getViewMode(ref.watch(viewWidthProvider));
}

@Riverpod(keepAlive: true)
bool isMobileView(Ref ref) {
  return ref.watch(viewModeProvider) == ViewMode.mobile;
}

@Riverpod(keepAlive: true)
double viewHeight(Ref ref) {
  return ref.watch(viewSizeProvider).height;
}

@Riverpod(keepAlive: true)
class Init extends _$Init with AutoDisposeNotifierMixin {
  @override
  bool build() {
    return false;
  }
}

@Riverpod(keepAlive: true)
class CurrentPageLabel extends _$CurrentPageLabel
    with AutoDisposeNotifierMixin {
  @override
  PageLabel build() {
    return PageLabel.dashboard;
  }

  void toPage(PageLabel pageLabel) {
    value = pageLabel;
  }

  void toProfiles() {
    toPage(PageLabel.profiles);
  }
}

@Riverpod(keepAlive: true)
class SortNum extends _$SortNum with AutoDisposeNotifierMixin {
  @override
  int build() {
    return 0;
  }

  int add() => state++;
}

@Riverpod(keepAlive: true)
class CheckIpNum extends _$CheckIpNum with AutoDisposeNotifierMixin {
  @override
  int build() {
    return 0;
  }

  int add() => state++;
}

@Riverpod(keepAlive: true)
class BackBlock extends _$BackBlock with AutoDisposeNotifierMixin {
  @override
  bool build() {
    return false;
  }

  void backBlock() {
    value = true;
  }

  void unBackBlock() {
    value = false;
  }
}

@Riverpod(keepAlive: true)
class Version extends _$Version with AutoDisposeNotifierMixin {
  @override
  int build() {
    return 0;
  }
}

@Riverpod(keepAlive: true)
class Groups extends _$Groups with AutoDisposeNotifierMixin {
  @override
  List<Group> build() {
    return [];
  }
}

@Riverpod(keepAlive: true)
class RuntimeProxies extends _$RuntimeProxies with AutoDisposeNotifierMixin {
  @override
  ProxiesData build() {
    return const ProxiesData();
  }
}

@Riverpod(keepAlive: true)
class NetworkRevision extends _$NetworkRevision with AutoDisposeNotifierMixin {
  @override
  int build() {
    return 0;
  }

  int bump() => ++state;
}

@Riverpod(keepAlive: true)
class GeoDatabaseRevision extends _$GeoDatabaseRevision
    with AutoDisposeNotifierMixin {
  @override
  int build() {
    return 0;
  }

  int bump() => ++state;
}

@Riverpod(keepAlive: true)
class ProxyGeoDataSource extends _$ProxyGeoDataSource
    with AutoDisposeNotifierMixin {
  @override
  ProxyGeoState build() {
    return const ProxyGeoState();
  }

  void replace(ProxyGeoState next) {
    value = next;
  }
}

@Riverpod(keepAlive: true)
class DelayDataSource extends _$DelayDataSource with AutoDisposeNotifierMixin {
  Timer? _delayFlushTimer;
  DelayMap? _pendingDelayMap;

  @override
  DelayMap build() {
    ref.onDispose(() {
      _delayFlushTimer?.cancel();
      _delayFlushTimer = null;
      _pendingDelayMap = null;
    });
    return {};
  }

  DelayMap _copyDelayMap(DelayMap source) {
    return {
      for (final entry in source.entries)
        entry.key: Map<String, int?>.from(entry.value),
    };
  }

  void _applyDelay(DelayMap delayMap, Delay delay) {
    final urlMap = delayMap[delay.url];
    if (urlMap == null) {
      delayMap[delay.url] = {delay.name: delay.value};
      return;
    }
    urlMap[delay.name] = delay.value;
  }

  bool _wouldChange(DelayMap delayMap, Delay delay) {
    return delayMap[delay.url]?[delay.name] != delay.value;
  }

  void setDelay(Delay delay) {
    final base = _pendingDelayMap ?? state;
    if (!_wouldChange(base, delay)) {
      return;
    }
    _pendingDelayMap ??= _copyDelayMap(state);
    _applyDelay(_pendingDelayMap!, delay);
    _delayFlushTimer?.cancel();
    _delayFlushTimer = Timer(const Duration(milliseconds: 100), () {
      if (_pendingDelayMap != null) {
        value = _pendingDelayMap!;
        _pendingDelayMap = null;
      }
      _delayFlushTimer = null;
    });
  }

  void setDelays(List<Delay> delays) {
    if (delays.isEmpty) {
      return;
    }
    var changed = false;
    final next = _copyDelayMap(_pendingDelayMap ?? state);
    for (final delay in delays) {
      if (!_wouldChange(next, delay)) {
        continue;
      }
      _applyDelay(next, delay);
      changed = true;
    }
    if (!changed) {
      return;
    }
    _delayFlushTimer?.cancel();
    _delayFlushTimer = null;
    _pendingDelayMap = null;
    value = next;
  }
}

@Riverpod(keepAlive: true)
class SystemUiOverlayStyleState extends _$SystemUiOverlayStyleState
    with AutoDisposeNotifierMixin {
  @override
  SystemUiOverlayStyle build() {
    return const SystemUiOverlayStyle();
  }
}

@Riverpod(name: 'coreStatusProvider', keepAlive: true)
class _CoreStatus extends _$CoreStatus with AutoDisposeNotifierMixin {
  @override
  CoreStatus build() {
    return CoreStatus.disconnected;
  }
}

/// True while start/stop is in progress (UI loading; not yet [isStartProvider]).
@Riverpod(keepAlive: true)
class IsStarting extends _$IsStarting with AutoDisposeNotifierMixin {
  @override
  bool build() {
    return false;
  }
}

/// Session flags for core setup (config MD5 cache, VPN tip baseline, init gate).
/// Kept out of [globalState] so setup/VPN logic can depend on Riverpod only.
@Riverpod(keepAlive: true)
class NeedInitStatus extends _$NeedInitStatus with AutoDisposeNotifierMixin {
  @override
  bool build() {
    return true;
  }
}

@Riverpod(keepAlive: true)
class LastConfigMd5 extends _$LastConfigMd5 with AutoDisposeNotifierMixin {
  @override
  String? build() {
    return null;
  }
}

@Riverpod(keepAlive: true)
class LastVpnState extends _$LastVpnState with AutoDisposeNotifierMixin {
  @override
  VpnState? build() {
    return null;
  }
}

@riverpod
class Query extends _$Query with AutoDisposeNotifierMixin {
  @override
  String build(QueryTag tag) {
    return '';
  }
}

@Riverpod(keepAlive: true)
class Loading extends _$Loading with AutoDisposeNotifierMixin {
  DateTime? _start;
  Timer? _timer;

  @override
  bool build(LoadingTag tag) {
    return false;
  }

  void start() {
    _timer?.cancel();
    _timer = null;
    _start = DateTime.now();
    value = true;
  }

  Future<void> stop() async {
    if (_start == null) {
      value = false;
      return;
    }
    final startedAt = _start!;
    final elapsed = DateTime.now().difference(_start!).inMilliseconds;
    const minDuration = 1000;
    if (elapsed >= minDuration) {
      value = false;
      return;
    }
    _timer = Timer(Duration(milliseconds: minDuration - elapsed), () {
      if (_start != startedAt) {
        return;
      }
      value = false;
    });
  }
}

@riverpod
class Items extends _$Items with AutoDisposeNotifierMixin {
  @override
  Set<dynamic> build(String key) {
    return {};
  }
}

@riverpod
class Item extends _$Item with AutoDisposeNotifierMixin {
  @override
  dynamic build(String key) {
    return null;
  }
}

@riverpod
class IsUpdating extends _$IsUpdating with AutoDisposeNotifierMixin {
  @override
  bool build(String name) {
    return false;
  }
}

@Riverpod(keepAlive: true)
class NetworkDetection extends _$NetworkDetection
    with AutoDisposeNotifierMixin {
  static final _probeUri = Uri.parse('https://ipwho.is');
  static const _timeoutDisplayDelay = Duration(seconds: 2);

  bool? _preUsesLocalProxy;
  _IpCheckOwner? _activeCheck;
  Timer? _timeoutTimer;
  int _checkGeneration = 0;
  final Map<bool, IpInfo> _lastSuccessByRunningState = {};

  @override
  NetworkDetectionState build() {
    ref.onDispose(() {
      debouncer.cancel(FunctionTag.checkIp);
      _cancelActiveCheck();
    });
    return const NetworkDetectionState(isLoading: true, ipInfo: null);
  }

  void startCheck({bool immediate = false}) {
    final route = _readyRoute();
    if (route == null || !_canCheckInForeground()) {
      return;
    }
    if (immediate) {
      debouncer.cancel(FunctionTag.checkIp);
      _launchCheck();
      return;
    }
    debouncer.call(FunctionTag.checkIp, () {
      final currentRoute = _readyRoute();
      if (currentRoute == null || !_canCheckInForeground()) {
        return;
      }
      _launchCheck();
    }, duration: commonDuration);
  }

  void _launchCheck() {
    unawaited(
      runAsyncSafely(
        operation: _checkIp,
        onError: (_, _) {
          commonPrint.log(
            'IP check operation failed',
            logLevel: LogLevel.warning,
          );
        },
      ),
    );
  }

  Future<void> _checkIp() async {
    final readyRoute = _readyRoute();
    if (readyRoute == null || !_canCheckInForeground()) {
      return;
    }
    final usesLocalProxy = readyRoute;
    if (!usesLocalProxy &&
        _preUsesLocalProxy == false &&
        state.ipInfo != null) {
      return;
    }
    final owner = _beginCheck(usesLocalProxy);
    Result<IpInfo?> res;
    try {
      res = await ref.read(ipInfoLoaderProvider)(
        owner.cancelToken,
        usesLocalProxy,
      );
    } catch (_) {
      commonPrint.log('IP check request failed', logLevel: LogLevel.warning);
      if (_ownsCheck(owner)) {
        owner.cancelToken.cancel();
        _delayTimeoutDisplay(owner);
      }
      return;
    }

    if (!_ownsCheck(owner)) {
      return;
    }
    final ipInfo = res.data;
    final currentRoute = _readyRoute();
    if (currentRoute != usesLocalProxy) {
      if (ipInfo != null) {
        _lastSuccessByRunningState[usesLocalProxy] = ipInfo;
      }
      if (currentRoute != null && _canCheckInForeground()) {
        _launchCheck();
      } else {
        _finishLoading(owner);
      }
      return;
    }
    if (ipInfo == null) {
      _delayTimeoutDisplay(owner);
      return;
    }
    _lastSuccessByRunningState[usesLocalProxy] = ipInfo;
    if (_ownsCheck(owner)) {
      _activeCheck = null;
      state = state.copyWith(isLoading: false, ipInfo: ipInfo);
    }
  }

  bool? _readyRoute() {
    if (!ref.read(initProvider) || ref.read(isStartingProvider)) {
      return null;
    }
    return _usesLocalProxy();
  }

  bool _usesLocalProxy() {
    return FlClashHttpOverrides.shouldUseLocalProxy(
      url: _probeUri,
      coreStatus: ref.read(coreStatusProvider),
      isStart: ref.read(isStartProvider),
      isStarting: ref.read(isStartingProvider),
      suspend: ref.read(suspendProvider),
    );
  }

  bool _ownsCheck(_IpCheckOwner owner) {
    final activeCheck = _activeCheck;
    return ref.mounted &&
        activeCheck?.generation == owner.generation &&
        activeCheck?.usesLocalProxy == owner.usesLocalProxy &&
        identical(activeCheck?.cancelToken, owner.cancelToken);
  }

  bool _canCheckInForeground() {
    return ref.read(ipCheckForegroundGateProvider)() &&
        ref.read(
          dashboardStateProvider.select(
            (state) => state.dashboardWidgets.contains(
              DashboardWidget.networkDetection,
            ),
          ),
        );
  }

  _IpCheckOwner _beginCheck(bool usesLocalProxy) {
    _cancelTimeoutTimer();
    final owner = (
      cancelToken: CancelToken(),
      generation: ++_checkGeneration,
      usesLocalProxy: usesLocalProxy,
    );
    final previousOwner = _activeCheck;
    _activeCheck = owner;
    previousOwner?.cancelToken.cancel();
    _preUsesLocalProxy = usesLocalProxy;
    state = state.copyWith(
      isLoading: true,
      ipInfo: _lastSuccessByRunningState[usesLocalProxy],
    );
    return owner;
  }

  void _cancelActiveCheck() {
    _cancelTimeoutTimer();
    final activeCheck = _activeCheck;
    _activeCheck = null;
    activeCheck?.cancelToken.cancel();
  }

  void _finishLoading(_IpCheckOwner owner) {
    if (!_ownsCheck(owner)) {
      return;
    }
    _cancelTimeoutTimer();
    _activeCheck = null;
    state = state.copyWith(isLoading: false);
  }

  void _delayTimeoutDisplay(_IpCheckOwner owner) {
    _cancelTimeoutTimer();
    _timeoutTimer = Timer(_timeoutDisplayDelay, () {
      _timeoutTimer = null;
      if (!_ownsCheck(owner)) {
        return;
      }
      _activeCheck = null;
      state = state.copyWith(isLoading: false, ipInfo: null);
    });
  }

  void _cancelTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }
}

@Riverpod(keepAlive: true)
class CurrentSSID extends _$CurrentSSID with AutoDisposeNotifierMixin {
  @override
  String? build() {
    return null;
  }
}

@Riverpod(keepAlive: true)
class BatteryOptimizationDisable extends _$BatteryOptimizationDisable
    with AutoDisposeNotifierMixin {
  @override
  bool build() {
    return false;
  }
}

@Riverpod(keepAlive: true)
class LocationPermissions extends _$LocationPermissions
    with AutoDisposeNotifierMixin {
  @override
  WifiSsidPermission build() {
    return WifiSsidPermission.denied;
  }
}

List<Override> buildAppStateOverrides(AppState appState) {
  return [
    initProvider.overrideWithBuild((_, _) => appState.isInit),
    backBlockProvider.overrideWithBuild((_, _) => appState.backBlock),
    currentPageLabelProvider.overrideWithBuild((_, _) => appState.pageLabel),
    packagesProvider.overrideWithBuild((_, _) => appState.packages),
    sortNumProvider.overrideWithBuild((_, _) => appState.sortNum),
    viewSizeProvider.overrideWithBuild((_, _) => appState.viewSize),
    sideWidthProvider.overrideWithBuild((_, _) => appState.sideWidth),
    delayDataSourceProvider.overrideWithBuild((_, _) => appState.delayMap),
    groupsProvider.overrideWithBuild((_, _) => appState.groups),
    checkIpNumProvider.overrideWithBuild((_, _) => appState.checkIpNum),
    systemBrightnessProvider.overrideWithBuild((_, _) => appState.brightness),
    runTimeProvider.overrideWithBuild((_, _) => appState.runTime),
    providersProvider.overrideWithBuild((_, _) => appState.providers),
    localIpProvider.overrideWithBuild((_, _) => appState.localIp),
    requestsProvider.overrideWithBuild((_, _) => appState.requests),
    versionProvider.overrideWithBuild((_, _) => appState.version),
    logsProvider.overrideWithBuild((_, _) => appState.logs),
    trafficsProvider.overrideWithBuild((_, _) => appState.traffics),
    totalTrafficProvider.overrideWithBuild((_, _) => appState.totalTraffic),
    realTunEnableProvider.overrideWithBuild((_, _) => appState.realTunEnable),
    systemUiOverlayStyleStateProvider.overrideWithBuild(
      (_, _) => appState.systemUiOverlayStyle,
    ),
    coreStatusProvider.overrideWithBuild((_, _) => appState.coreStatus),
  ];
}
