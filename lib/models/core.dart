import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'generated/core.freezed.dart';
part 'generated/core.g.dart';

@freezed
abstract class SetupParams with _$SetupParams {
  const factory SetupParams({
    @JsonKey(name: 'selected-map') required Map<String, String> selectedMap,
    @JsonKey(name: 'test-url') required String testUrl,
  }) = _SetupParams;

  factory SetupParams.fromJson(Map<String, dynamic> json) =>
      _$SetupParamsFromJson(json);
}

@freezed
abstract class UpdateParams with _$UpdateParams {
  const factory UpdateParams({
    required Tun tun,
    @JsonKey(name: 'mixed-port') required int mixedPort,
    @JsonKey(name: 'allow-lan') required bool allowLan,
    @JsonKey(name: 'find-process-mode')
    required FindProcessMode findProcessMode,
    required Mode mode,
    @JsonKey(name: 'log-level') required LogLevel logLevel,
    required bool ipv6,
    @JsonKey(name: 'tcp-concurrent') required bool tcpConcurrent,
    @JsonKey(name: 'external-controller')
    required ExternalControllerStatus externalController,
    @JsonKey(name: 'unified-delay') required bool unifiedDelay,
    @Default(false) @JsonKey(name: 'geo-auto-update') bool geoAutoUpdate,
    @Default(24) @JsonKey(name: 'geo-update-interval') int geoUpdateInterval,
  }) = _UpdateParams;

  factory UpdateParams.fromJson(Map<String, dynamic> json) =>
      _$UpdateParamsFromJson(json);
}

@freezed
abstract class VpnOptions with _$VpnOptions {
  const factory VpnOptions({
    required bool enable,
    required int port,
    required bool ipv6,
    required bool dnsHijacking,
    required AccessControlProps accessControlProps,
    required bool allowBypass,
    required bool systemProxy,
    required List<String> bypassDomain,
    required String stack,
    @Default([]) List<String> routeAddress,
  }) = _VpnOptions;

  factory VpnOptions.fromJson(Map<String, Object?> json) =>
      _$VpnOptionsFromJson(json);
}

@freezed
abstract class InitParams with _$InitParams {
  const factory InitParams({
    @JsonKey(name: 'home-dir') required String homeDir,
    required int version,
  }) = _InitParams;

  factory InitParams.fromJson(Map<String, Object?> json) =>
      _$InitParamsFromJson(json);
}

@freezed
abstract class ChangeProxyParams with _$ChangeProxyParams {
  const factory ChangeProxyParams({
    @JsonKey(name: 'group-name') String? groupName,
    @JsonKey(name: 'proxy-name') String? proxyName,
    @JsonKey(name: 'group-id') String? groupId,
    @JsonKey(name: 'member-id') String? memberId,
    int? generation,
  }) = _ChangeProxyParams;

  factory ChangeProxyParams.fromJson(Map<String, Object?> json) =>
      _$ChangeProxyParamsFromJson(json);
}

@freezed
abstract class UpdateGeoDataParams with _$UpdateGeoDataParams {
  const factory UpdateGeoDataParams({
    @JsonKey(name: 'geo-type') required String geoType,
    @JsonKey(name: 'geo-name') required String geoName,
  }) = _UpdateGeoDataParams;

  factory UpdateGeoDataParams.fromJson(Map<String, Object?> json) =>
      _$UpdateGeoDataParamsFromJson(json);
}

@freezed
abstract class CoreEvent with _$CoreEvent {
  const factory CoreEvent({required CoreEventType type, dynamic data}) =
      _CoreEvent;

  factory CoreEvent.fromJson(Map<String, Object?> json) =>
      _$CoreEventFromJson(json);
}

@freezed
abstract class InvokeMessage with _$InvokeMessage {
  const factory InvokeMessage({required InvokeMessageType type, dynamic data}) =
      _InvokeMessage;

  factory InvokeMessage.fromJson(Map<String, Object?> json) =>
      _$InvokeMessageFromJson(json);
}

@freezed
abstract class Delay with _$Delay {
  const factory Delay({required String name, required String url, int? value}) =
      _Delay;

  factory Delay.fromJson(Map<String, Object?> json) => _$DelayFromJson(json);
}

@freezed
abstract class Now with _$Now {
  const factory Now({required String name, required String value}) = _Now;

  factory Now.fromJson(Map<String, Object?> json) => _$NowFromJson(json);
}

@freezed
abstract class ProviderSubscriptionInfo with _$ProviderSubscriptionInfo {
  const factory ProviderSubscriptionInfo({
    @JsonKey(name: 'UPLOAD') @Default(0) int upload,
    @JsonKey(name: 'DOWNLOAD') @Default(0) int download,
    @JsonKey(name: 'TOTAL') @Default(0) int total,
    @JsonKey(name: 'EXPIRE') @Default(0) int expire,
  }) = _ProviderSubscriptionInfo;

  factory ProviderSubscriptionInfo.fromJson(Map<String, Object?> json) =>
      _$ProviderSubscriptionInfoFromJson(json);
}

SubscriptionInfo? subscriptionInfoFormCore(Map<String, Object?>? json) {
  if (json == null) return null;
  return SubscriptionInfo(
    upload: (json['Upload'] as num?)?.toInt() ?? 0,
    download: (json['Download'] as num?)?.toInt() ?? 0,
    total: (json['Total'] as num?)?.toInt() ?? 0,
    expire: (json['Expire'] as num?)?.toInt() ?? 0,
  );
}

@freezed
abstract class ExternalProvider with _$ExternalProvider {
  const factory ExternalProvider({
    required String name,
    required String type,
    String? path,
    required int count,
    @JsonKey(name: 'subscription-info', fromJson: subscriptionInfoFormCore)
    SubscriptionInfo? subscriptionInfo,
    @JsonKey(name: 'vehicle-type') required String vehicleType,
    @JsonKey(name: 'update-at') required DateTime updateAt,
  }) = _ExternalProvider;

  factory ExternalProvider.fromJson(Map<String, Object?> json) =>
      _$ExternalProviderFromJson(json);
}

extension ExternalProviderExt on ExternalProvider {
  String get updatingKey => 'provider_$name';
}

@freezed
abstract class Action with _$Action {
  const factory Action({
    required ActionMethod method,
    required dynamic data,
    required String id,
  }) = _Action;

  factory Action.fromJson(Map<String, Object?> json) => _$ActionFromJson(json);
}

@freezed
abstract class ProxiesData with _$ProxiesData {
  const factory ProxiesData({
    @Default({}) Map<String, dynamic> proxies,
    @Default([]) List<String> all,
    @Default(0) int generation,
    @Default([]) List<ProxyGroupSnapshot> groups,
    @Default({}) Map<String, ProxyNodeSnapshot> nodesById,
  }) = _ProxiesData;

  factory ProxiesData.fromJson(Map<String, Object?> json) =>
      _$ProxiesDataFromJson(json);
}

extension ProxiesDataExt on ProxiesData {
  ProxyGroupSnapshot? groupById(String id) {
    for (final group in groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  String? resolveCurrentLeafId(String groupId) {
    final group = groupById(groupId);
    if (group == null || group.nowId.isEmpty) return null;
    return resolveMemberLeafId(groupId, group.nowId);
  }

  String? resolveMemberLeafId(String groupId, String memberId) {
    final path = resolveMemberPathIds(groupId, memberId);
    return path == null || path.isEmpty ? null : path.last;
  }

  List<String>? resolveMemberPathIds(String groupId, String memberId) {
    final groupsById = {for (final group in groups) group.id: group};
    final rootGroup = groupsById[groupId];
    if (rootGroup == null || !rootGroup.memberIds.contains(memberId)) {
      return null;
    }
    var currentId = memberId;
    final path = <String>[groupId];
    final visited = <String>{};
    while (true) {
      final node = nodesById[currentId];
      if (node == null) return null;
      path.add(currentId);
      final nestedGroup = groupsById[currentId];
      if (nestedGroup == null) return path;
      if (!visited.add(nestedGroup.id)) return null;
      final nextId = nestedGroup.nowId;
      if (nextId.isEmpty || !nestedGroup.memberIds.contains(nextId)) {
        return null;
      }
      currentId = nextId;
    }
  }

  ProxyGroupSnapshot? uniqueGroupByName(String name) {
    ProxyGroupSnapshot? result;
    for (final group in groups) {
      if (group.name != name) continue;
      if (result != null) return null;
      result = group;
    }
    return result;
  }

  ProxyNodeSnapshot? uniqueMemberByName(ProxyGroupSnapshot group, String name) {
    ProxyNodeSnapshot? result;
    for (final memberId in group.memberIds) {
      final node = nodesById[memberId];
      if (node?.name != name) continue;
      if (result != null) return null;
      result = node;
    }
    return result;
  }
}

@freezed
abstract class ProxyGroupSnapshot with _$ProxyGroupSnapshot {
  const factory ProxyGroupSnapshot({
    required String id,
    required String name,
    required String type,
    @Default('') String nowId,
    @Default([]) List<String> memberIds,
  }) = _ProxyGroupSnapshot;

  factory ProxyGroupSnapshot.fromJson(Map<String, Object?> json) =>
      _$ProxyGroupSnapshotFromJson(json);
}

@freezed
abstract class ProxyNodeSnapshot with _$ProxyNodeSnapshot {
  const factory ProxyNodeSnapshot({
    required String id,
    required String stableKey,
    required String name,
    required String type,
    @Default('') String providerName,
  }) = _ProxyNodeSnapshot;

  factory ProxyNodeSnapshot.fromJson(Map<String, Object?> json) =>
      _$ProxyNodeSnapshotFromJson(json);
}

@freezed
abstract class ProxyServerGeoParams with _$ProxyServerGeoParams {
  const factory ProxyServerGeoParams({
    required int generation,
    @Default(0) int networkRevision,
    @Default('') String requestId,
    @Default(false) bool all,
    @Default([]) List<String> memberIds,
  }) = _ProxyServerGeoParams;

  factory ProxyServerGeoParams.fromJson(Map<String, Object?> json) =>
      _$ProxyServerGeoParamsFromJson(json);
}

@freezed
abstract class GeoDatabaseGeneration with _$GeoDatabaseGeneration {
  const factory GeoDatabaseGeneration({
    @Default(0) int country,
    @Default(0) int asn,
  }) = _GeoDatabaseGeneration;

  factory GeoDatabaseGeneration.fromJson(Map<String, Object?> json) =>
      _$GeoDatabaseGenerationFromJson(json);
}

@freezed
abstract class ProxyGeoAddress with _$ProxyGeoAddress {
  const factory ProxyGeoAddress({
    required String ip,
    @Default('') String countryCode,
    @Default('') String asn,
    @Default('') String aso,
  }) = _ProxyGeoAddress;

  factory ProxyGeoAddress.fromJson(Map<String, Object?> json) =>
      _$ProxyGeoAddressFromJson(json);
}

@freezed
abstract class ProxyServerGeo with _$ProxyServerGeo {
  const factory ProxyServerGeo({
    required String memberId,
    @Default('') String serverHost,
    @Default('') String source,
    @Default('') String status,
    @Default(false) bool multiRegion,
    @Default([]) List<ProxyGeoAddress> addresses,
  }) = _ProxyServerGeo;

  factory ProxyServerGeo.fromJson(Map<String, Object?> json) =>
      _$ProxyServerGeoFromJson(json);
}

extension ProxyServerGeoExt on ProxyServerGeo {
  ProxyGeoAddress? get primaryAddress =>
      addresses.isEmpty ? null : addresses.first;
}

@freezed
abstract class ProxyServerGeos with _$ProxyServerGeos {
  const factory ProxyServerGeos({
    required int generation,
    @Default('') String requestId,
    @Default(false) bool stale,
    @Default(GeoDatabaseGeneration()) GeoDatabaseGeneration dbGeneration,
    @Default({}) Map<String, ProxyServerGeo> members,
  }) = _ProxyServerGeos;

  factory ProxyServerGeos.fromJson(Map<String, Object?> json) =>
      _$ProxyServerGeosFromJson(json);
}

@freezed
abstract class ProbeProxyExitParams with _$ProbeProxyExitParams {
  const factory ProbeProxyExitParams({
    required int generation,
    @Default(0) int networkRevision,
    @Default('') String requestId,
    required String groupId,
    required String memberId,
  }) = _ProbeProxyExitParams;

  factory ProbeProxyExitParams.fromJson(Map<String, Object?> json) =>
      _$ProbeProxyExitParamsFromJson(json);
}

@freezed
abstract class ProxyExitGeo with _$ProxyExitGeo {
  const factory ProxyExitGeo({
    required int generation,
    @Default('') String requestId,
    @Default(false) bool stale,
    @Default('') String leafId,
    @Default([]) List<String> pathIds,
    @Default(false) bool routeSample,
    @Default(false) bool cached,
    @Default('') String ip,
    @Default('') String countryCode,
    @Default('') String asn,
    @Default('') String aso,
    @Default(GeoDatabaseGeneration()) GeoDatabaseGeneration dbGeneration,
  }) = _ProxyExitGeo;

  factory ProxyExitGeo.fromJson(Map<String, Object?> json) =>
      _$ProxyExitGeoFromJson(json);
}

@freezed
abstract class ActionResult with _$ActionResult {
  const factory ActionResult({
    required ActionMethod method,
    required dynamic data,
    String? id,
    @Default(ResultType.success) ResultType code,
  }) = _ActionResult;

  factory ActionResult.fromJson(Map<String, Object?> json) =>
      _$ActionResultFromJson(json);
}

extension ActionResultExt on ActionResult {
  Result get toResult {
    if (code == ResultType.success) {
      return Result.success(data);
    } else {
      return Result.error('$data');
    }
  }
}
