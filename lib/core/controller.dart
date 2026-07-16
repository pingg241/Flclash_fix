import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart';

class CoreController {
  static CoreController? _instance;
  late CoreHandlerInterface _interface;

  CoreController._internal() {
    if (system.isAndroid) {
      _interface = coreLib!;
    } else {
      _interface = coreService!;
    }
  }

  @visibleForTesting
  CoreController.test(this._interface);

  @visibleForTesting
  static void resetInstance() {
    _instance = null;
  }

  factory CoreController() {
    _instance ??= CoreController._internal();
    return _instance!;
  }

  bool get isCompleted => _interface.completer.isCompleted;

  Future<String> preload() {
    return _interface.preload();
  }

  static Future<void> initGeo() async {
    final homePath = await appPath.homeDirPath;
    final homeDir = Directory(homePath);
    final isExists = await homeDir.exists();
    if (!isExists) {
      await homeDir.create(recursive: true);
    }
    const geoFileNameList = [MMDB, GEOIP, GEOSITE, ASN];
    try {
      for (final geoFileName in geoFileNameList) {
        final geoFile = File(join(homePath, geoFileName));
        final isExists = await geoFile.exists();
        if (isExists) {
          continue;
        }
        final data = await rootBundle.load('assets/data/$geoFileName');
        final List<int> bytes = data.buffer.asUint8List();
        await geoFile.writeAsBytes(bytes, flush: true);
      }
    } catch (e) {
      commonPrint.log(
        'Failed to initialize geo data: $e',
        logLevel: LogLevel.error,
      );
      rethrow;
    }
  }

  Future<bool> init(int version) async {
    await initGeo();
    final homeDirPath = await appPath.homeDirPath;
    return _interface.init(InitParams(homeDir: homeDirPath, version: version));
  }

  Future<bool> shutdown(bool isUser) async {
    return _interface.shutdown(isUser);
  }

  FutureOr<bool> get isInit => _interface.isInit;

  Future<String> validateConfig(String path) async {
    final res = await _interface.validateConfig(path);
    return res;
  }

  Future<String> validateConfigWithData(String data) async {
    final homeDirPath = await appPath.homeDirPath;
    return validateConfigWithDataAtHome(data, homeDirPath);
  }

  @visibleForTesting
  Future<String> validateConfigWithDataAtHome(
    String data,
    String homeDirPath,
  ) async {
    final path = join(homeDirPath, '.tmp', 'validate-${utils.id}.yaml');
    final file = File(path);
    try {
      await file.safeWriteAsString(data);
      return await _interface.validateConfig(path);
    } finally {
      await file.safeDelete();
    }
  }

  Future<String> updateConfig(UpdateParams updateParams) async {
    return _interface.updateConfig(updateParams);
  }

  Future<String> setupConfig({
    required SetupParams params,
    required SetupState setupState,
    FutureOr<void> Function()? preloadInvoke,
  }) async {
    final res = await _interface.setupConfig(params);
    // Await listener/VPN bring-up before treating setup as complete.
    if (res.isEmpty && preloadInvoke != null) {
      await preloadInvoke();
    }
    return res;
  }

  Future<List<Group>> getProxiesGroups({
    required ProxiesSortType sortType,
    required DelayMap delayMap,
    required Map<String, String> selectedMap,
    required String defaultTestUrl,
  }) async {
    final proxiesData = await _interface.getProxies();
    return buildProxiesGroups(
      proxiesData: proxiesData,
      sortType: sortType,
      delayMap: delayMap,
      selectedMap: selectedMap,
      defaultTestUrl: defaultTestUrl,
    );
  }

  Future<ProxiesData> getProxies() {
    return _interface.getProxies();
  }

  Future<List<Group>> buildProxiesGroups({
    required ProxiesData proxiesData,
    required ProxiesSortType sortType,
    required DelayMap delayMap,
    required Map<String, String> selectedMap,
    required String defaultTestUrl,
  }) {
    return toGroupsTask(
      ComputeGroupsState(
        proxiesData: proxiesData,
        sortType: sortType,
        delayMap: delayMap,
        selectedMap: selectedMap,
        defaultTestUrl: defaultTestUrl,
      ),
    );
  }

  Future<ProxyServerGeos> getProxyServerGeos(ProxyServerGeoParams params) {
    return _interface.getProxyServerGeos(params);
  }

  Future<ProxyExitGeo> probeProxyExit(ProbeProxyExitParams params) {
    return _interface.probeProxyExit(params);
  }

  FutureOr<String> changeProxy(ChangeProxyParams changeProxyParams) async {
    return await _interface.changeProxy(changeProxyParams);
  }

  Future<List<TrackerInfo>> getConnections() async {
    final res = await _interface.getConnections();
    final connectionsData = _asJsonMap(res);
    if (connectionsData == null) {
      return [];
    }
    final connectionsRaw = connectionsData['connections'] as List? ?? [];
    return connectionsRaw
        .map((e) => TrackerInfo.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> closeConnection(String id) async {
    await _requireSuccess(
      _interface.closeConnection(id),
      'close connection $id',
    );
  }

  Future<void> closeConnections() async {
    await _requireSuccess(
      _interface.closeConnections(),
      'close all connections',
    );
  }

  Future<void> resetConnections() async {
    await _interface.resetConnections();
  }

  Future<List<ExternalProvider>> getExternalProviders() async {
    final raw = await _interface.getExternalProviders();
    final list = _asJsonList(raw);
    if (list == null) {
      return [];
    }
    return list
        .map(
          (item) =>
              ExternalProvider.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<ExternalProvider?> getExternalProvider(
    String externalProviderName,
  ) async {
    final raw = await _interface.getExternalProvider(externalProviderName);
    final map = _asJsonMap(raw);
    if (map == null) {
      return null;
    }
    return ExternalProvider.fromJson(map);
  }

  Future<String> updateGeoData(String type) {
    return _interface.updateGeoData(type);
  }

  Future<String> sideLoadExternalProvider({
    required String providerName,
    required String data,
  }) {
    return _interface.sideLoadExternalProvider(
      providerName: providerName,
      data: data,
    );
  }

  Future<String> updateExternalProvider({required String providerName}) async {
    return _interface.updateExternalProvider(providerName);
  }

  Future<bool> startListener() async {
    return _interface.startListener();
  }

  Future<bool> stopListener() async {
    return _interface.stopListener();
  }

  Future<Delay> getDelay(String url, String proxyName) async {
    final data = await _interface.asyncTestDelay(url, proxyName);
    return Delay.fromJson(json.decode(data));
  }

  Future<Map<String, dynamic>> getConfig(int id) async {
    final profilePath = await appPath.getProfilePath(id.toString());
    final res = await _interface.getConfig(profilePath);
    if (res.isSuccess) {
      final data = Map<String, dynamic>.from(res.data);
      data['rules'] = data['rule'];
      data.remove('rule');
      return data;
    } else {
      throw res.message;
    }
  }

  Future<Traffic> getTraffic(bool onlyStatisticsProxy) async {
    final raw = await _interface.getTraffic(onlyStatisticsProxy);
    return _parseTraffic(raw);
  }

  Future<IpInfo?> getCountryCode(String ip) async {
    final countryCode = await _interface.getCountryCode(ip);
    if (countryCode.isEmpty) {
      return null;
    }
    return IpInfo(ip: ip, countryCode: countryCode);
  }

  Future<Traffic> getTotalTraffic(bool onlyStatisticsProxy) async {
    final raw = await _interface.getTotalTraffic(onlyStatisticsProxy);
    return _parseTraffic(raw);
  }

  /// One core round-trip for both live speed and cumulative totals.
  Future<({Traffic now, Traffic total})> getTrafficSnapshot(
    bool onlyStatisticsProxy,
  ) async {
    final raw = await _interface.getTrafficSnapshot(onlyStatisticsProxy);
    final map = _asJsonMap(raw);
    if (map == null) {
      return (now: const Traffic(), total: const Traffic());
    }
    final nowMap = map['now'];
    final totalMap = map['total'];
    return (
      now: nowMap is Map
          ? Traffic.fromJson(Map<String, dynamic>.from(nowMap))
          : const Traffic(),
      total: totalMap is Map
          ? Traffic.fromJson(Map<String, dynamic>.from(totalMap))
          : const Traffic(),
    );
  }

  static Traffic _parseTraffic(dynamic raw) {
    final map = _asJsonMap(raw);
    if (map == null) {
      return const Traffic();
    }
    return Traffic.fromJson(map);
  }

  /// Accepts structured maps (new core) or JSON strings (legacy / CGO exports).
  static Map<String, dynamic>? _asJsonMap(dynamic raw) {
    if (raw == null) {
      return null;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String) {
      if (raw.isEmpty) {
        return null;
      }
      try {
        final decoded = json.decode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return null;
  }

  static List<dynamic>? _asJsonList(dynamic raw) {
    if (raw == null) {
      return null;
    }
    if (raw is List) {
      return raw;
    }
    if (raw is String) {
      if (raw.isEmpty) {
        return null;
      }
      try {
        final decoded = json.decode(raw);
        if (decoded is List) {
          return decoded;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<int> getMemory() async {
    final value = await _interface.getMemory();
    if (value.isEmpty) {
      return 0;
    }
    return int.parse(value);
  }

  Future<void> resetTraffic() => _interface.resetTraffic();

  Future<void> startLog() => _interface.startLog();

  Future<void> stopLog() => _interface.stopLog();

  Future<void> requestGc() async {
    await _interface.forceGc();
  }

  Future<void> prepareTunHelper() async {
    final error = await _interface.prepareTunHelper();
    if (error.isNotEmpty) {
      throw StateError(error);
    }
  }

  Future<void> releaseTunHelper() async {
    final error = await _interface.releaseTunHelper();
    if (error.isNotEmpty) {
      throw StateError(error);
    }
  }

  Future<void> destroy() async {
    await _requireSuccess(_interface.destroy(), 'destroy core');
  }

  Future<void> crash() async {
    await _interface.crash();
  }

  Future<String> deleteFile(String path) async {
    return _interface.deleteFile(path);
  }

  Future<void> _requireSuccess(FutureOr<bool> result, String operation) async {
    if (!await result) {
      throw StateError('Core rejected operation: $operation');
    }
  }
}

final coreController = CoreController();
