// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../core.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SetupParams _$SetupParamsFromJson(Map<String, dynamic> json) => _SetupParams(
  selectedMap: Map<String, String>.from(json['selected-map'] as Map),
  testUrl: json['test-url'] as String,
);

Map<String, dynamic> _$SetupParamsToJson(_SetupParams instance) =>
    <String, dynamic>{
      'selected-map': instance.selectedMap,
      'test-url': instance.testUrl,
    };

_UpdateParams _$UpdateParamsFromJson(Map<String, dynamic> json) =>
    _UpdateParams(
      tun: Tun.fromJson(json['tun'] as Map<String, dynamic>),
      mixedPort: (json['mixed-port'] as num).toInt(),
      allowLan: json['allow-lan'] as bool,
      findProcessMode: $enumDecode(
        _$FindProcessModeEnumMap,
        json['find-process-mode'],
      ),
      mode: $enumDecode(_$ModeEnumMap, json['mode']),
      logLevel: $enumDecode(_$LogLevelEnumMap, json['log-level']),
      ipv6: json['ipv6'] as bool,
      tcpConcurrent: json['tcp-concurrent'] as bool,
      externalController: $enumDecode(
        _$ExternalControllerStatusEnumMap,
        json['external-controller'],
      ),
      unifiedDelay: json['unified-delay'] as bool,
      geoAutoUpdate: json['geo-auto-update'] as bool? ?? false,
      geoUpdateInterval: (json['geo-update-interval'] as num?)?.toInt() ?? 24,
    );

Map<String, dynamic> _$UpdateParamsToJson(_UpdateParams instance) =>
    <String, dynamic>{
      'tun': instance.tun,
      'mixed-port': instance.mixedPort,
      'allow-lan': instance.allowLan,
      'find-process-mode': _$FindProcessModeEnumMap[instance.findProcessMode]!,
      'mode': _$ModeEnumMap[instance.mode]!,
      'log-level': _$LogLevelEnumMap[instance.logLevel]!,
      'ipv6': instance.ipv6,
      'tcp-concurrent': instance.tcpConcurrent,
      'external-controller':
          _$ExternalControllerStatusEnumMap[instance.externalController]!,
      'unified-delay': instance.unifiedDelay,
      'geo-auto-update': instance.geoAutoUpdate,
      'geo-update-interval': instance.geoUpdateInterval,
    };

const _$FindProcessModeEnumMap = {
  FindProcessMode.always: 'always',
  FindProcessMode.off: 'off',
};

const _$ModeEnumMap = {
  Mode.rule: 'rule',
  Mode.global: 'global',
  Mode.direct: 'direct',
};

const _$LogLevelEnumMap = {
  LogLevel.debug: 'debug',
  LogLevel.info: 'info',
  LogLevel.warning: 'warning',
  LogLevel.error: 'error',
  LogLevel.silent: 'silent',
};

const _$ExternalControllerStatusEnumMap = {
  ExternalControllerStatus.close: '',
  ExternalControllerStatus.open: '127.0.0.1:9090',
};

_VpnOptions _$VpnOptionsFromJson(Map<String, dynamic> json) => _VpnOptions(
  enable: json['enable'] as bool,
  port: (json['port'] as num).toInt(),
  ipv6: json['ipv6'] as bool,
  dnsHijacking: json['dnsHijacking'] as bool,
  accessControlProps: AccessControlProps.fromJson(
    json['accessControlProps'] as Map<String, dynamic>,
  ),
  allowBypass: json['allowBypass'] as bool,
  systemProxy: json['systemProxy'] as bool,
  bypassDomain: (json['bypassDomain'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  stack: json['stack'] as String,
  routeAddress:
      (json['routeAddress'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
);

Map<String, dynamic> _$VpnOptionsToJson(_VpnOptions instance) =>
    <String, dynamic>{
      'enable': instance.enable,
      'port': instance.port,
      'ipv6': instance.ipv6,
      'dnsHijacking': instance.dnsHijacking,
      'accessControlProps': instance.accessControlProps,
      'allowBypass': instance.allowBypass,
      'systemProxy': instance.systemProxy,
      'bypassDomain': instance.bypassDomain,
      'stack': instance.stack,
      'routeAddress': instance.routeAddress,
    };

_InitParams _$InitParamsFromJson(Map<String, dynamic> json) => _InitParams(
  homeDir: json['home-dir'] as String,
  version: (json['version'] as num).toInt(),
);

Map<String, dynamic> _$InitParamsToJson(_InitParams instance) =>
    <String, dynamic>{
      'home-dir': instance.homeDir,
      'version': instance.version,
    };

_ChangeProxyParams _$ChangeProxyParamsFromJson(Map<String, dynamic> json) =>
    _ChangeProxyParams(
      groupName: json['group-name'] as String?,
      proxyName: json['proxy-name'] as String?,
      groupId: json['group-id'] as String?,
      memberId: json['member-id'] as String?,
      generation: (json['generation'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ChangeProxyParamsToJson(_ChangeProxyParams instance) =>
    <String, dynamic>{
      'group-name': instance.groupName,
      'proxy-name': instance.proxyName,
      'group-id': instance.groupId,
      'member-id': instance.memberId,
      'generation': instance.generation,
    };

_UpdateGeoDataParams _$UpdateGeoDataParamsFromJson(Map<String, dynamic> json) =>
    _UpdateGeoDataParams(
      geoType: json['geo-type'] as String,
      geoName: json['geo-name'] as String,
    );

Map<String, dynamic> _$UpdateGeoDataParamsToJson(
  _UpdateGeoDataParams instance,
) => <String, dynamic>{
  'geo-type': instance.geoType,
  'geo-name': instance.geoName,
};

_CoreEvent _$CoreEventFromJson(Map<String, dynamic> json) => _CoreEvent(
  type: $enumDecode(_$CoreEventTypeEnumMap, json['type']),
  data: json['data'],
);

Map<String, dynamic> _$CoreEventToJson(_CoreEvent instance) =>
    <String, dynamic>{
      'type': _$CoreEventTypeEnumMap[instance.type]!,
      'data': instance.data,
    };

const _$CoreEventTypeEnumMap = {
  CoreEventType.log: 'log',
  CoreEventType.delay: 'delay',
  CoreEventType.request: 'request',
  CoreEventType.loaded: 'loaded',
  CoreEventType.crash: 'crash',
  CoreEventType.geoUpdate: 'geoUpdate',
};

_InvokeMessage _$InvokeMessageFromJson(Map<String, dynamic> json) =>
    _InvokeMessage(
      type: $enumDecode(_$InvokeMessageTypeEnumMap, json['type']),
      data: json['data'],
    );

Map<String, dynamic> _$InvokeMessageToJson(_InvokeMessage instance) =>
    <String, dynamic>{
      'type': _$InvokeMessageTypeEnumMap[instance.type]!,
      'data': instance.data,
    };

const _$InvokeMessageTypeEnumMap = {
  InvokeMessageType.protect: 'protect',
  InvokeMessageType.process: 'process',
};

_Delay _$DelayFromJson(Map<String, dynamic> json) => _Delay(
  name: json['name'] as String,
  url: json['url'] as String,
  value: (json['value'] as num?)?.toInt(),
);

Map<String, dynamic> _$DelayToJson(_Delay instance) => <String, dynamic>{
  'name': instance.name,
  'url': instance.url,
  'value': instance.value,
};

_Now _$NowFromJson(Map<String, dynamic> json) =>
    _Now(name: json['name'] as String, value: json['value'] as String);

Map<String, dynamic> _$NowToJson(_Now instance) => <String, dynamic>{
  'name': instance.name,
  'value': instance.value,
};

_ProviderSubscriptionInfo _$ProviderSubscriptionInfoFromJson(
  Map<String, dynamic> json,
) => _ProviderSubscriptionInfo(
  upload: (json['UPLOAD'] as num?)?.toInt() ?? 0,
  download: (json['DOWNLOAD'] as num?)?.toInt() ?? 0,
  total: (json['TOTAL'] as num?)?.toInt() ?? 0,
  expire: (json['EXPIRE'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$ProviderSubscriptionInfoToJson(
  _ProviderSubscriptionInfo instance,
) => <String, dynamic>{
  'UPLOAD': instance.upload,
  'DOWNLOAD': instance.download,
  'TOTAL': instance.total,
  'EXPIRE': instance.expire,
};

_ExternalProvider _$ExternalProviderFromJson(Map<String, dynamic> json) =>
    _ExternalProvider(
      name: json['name'] as String,
      type: json['type'] as String,
      path: json['path'] as String?,
      count: (json['count'] as num).toInt(),
      subscriptionInfo: subscriptionInfoFormCore(
        json['subscription-info'] as Map<String, Object?>?,
      ),
      vehicleType: json['vehicle-type'] as String,
      updateAt: DateTime.parse(json['update-at'] as String),
    );

Map<String, dynamic> _$ExternalProviderToJson(_ExternalProvider instance) =>
    <String, dynamic>{
      'name': instance.name,
      'type': instance.type,
      'path': instance.path,
      'count': instance.count,
      'subscription-info': instance.subscriptionInfo,
      'vehicle-type': instance.vehicleType,
      'update-at': instance.updateAt.toIso8601String(),
    };

_Action _$ActionFromJson(Map<String, dynamic> json) => _Action(
  method: $enumDecode(_$ActionMethodEnumMap, json['method']),
  data: json['data'],
  id: json['id'] as String,
);

Map<String, dynamic> _$ActionToJson(_Action instance) => <String, dynamic>{
  'method': _$ActionMethodEnumMap[instance.method]!,
  'data': instance.data,
  'id': instance.id,
};

const _$ActionMethodEnumMap = {
  ActionMethod.message: 'message',
  ActionMethod.initClash: 'initClash',
  ActionMethod.getIsInit: 'getIsInit',
  ActionMethod.forceGc: 'forceGc',
  ActionMethod.shutdown: 'shutdown',
  ActionMethod.validateConfig: 'validateConfig',
  ActionMethod.updateConfig: 'updateConfig',
  ActionMethod.getConfig: 'getConfig',
  ActionMethod.getProxies: 'getProxies',
  ActionMethod.getProxyServerGeos: 'getProxyServerGeos',
  ActionMethod.probeProxyExit: 'probeProxyExit',
  ActionMethod.changeProxy: 'changeProxy',
  ActionMethod.getTraffic: 'getTraffic',
  ActionMethod.getTotalTraffic: 'getTotalTraffic',
  ActionMethod.getTrafficSnapshot: 'getTrafficSnapshot',
  ActionMethod.resetTraffic: 'resetTraffic',
  ActionMethod.asyncTestDelay: 'asyncTestDelay',
  ActionMethod.getConnections: 'getConnections',
  ActionMethod.closeConnections: 'closeConnections',
  ActionMethod.resetConnections: 'resetConnections',
  ActionMethod.closeConnection: 'closeConnection',
  ActionMethod.getExternalProviders: 'getExternalProviders',
  ActionMethod.getExternalProvider: 'getExternalProvider',
  ActionMethod.updateGeoData: 'updateGeoData',
  ActionMethod.updateExternalProvider: 'updateExternalProvider',
  ActionMethod.sideLoadExternalProvider: 'sideLoadExternalProvider',
  ActionMethod.startLog: 'startLog',
  ActionMethod.stopLog: 'stopLog',
  ActionMethod.startListener: 'startListener',
  ActionMethod.stopListener: 'stopListener',
  ActionMethod.getCountryCode: 'getCountryCode',
  ActionMethod.getMemory: 'getMemory',
  ActionMethod.crash: 'crash',
  ActionMethod.setupConfig: 'setupConfig',
  ActionMethod.deleteFile: 'deleteFile',
  ActionMethod.prepareTunHelper: 'prepareTunHelper',
  ActionMethod.releaseTunHelper: 'releaseTunHelper',
  ActionMethod.setState: 'setState',
  ActionMethod.startTun: 'startTun',
  ActionMethod.stopTun: 'stopTun',
  ActionMethod.getRunTime: 'getRunTime',
  ActionMethod.updateDns: 'updateDns',
  ActionMethod.getAndroidVpnOptions: 'getAndroidVpnOptions',
  ActionMethod.getCurrentProfileName: 'getCurrentProfileName',
};

_ProxiesData _$ProxiesDataFromJson(Map<String, dynamic> json) => _ProxiesData(
  proxies: json['proxies'] as Map<String, dynamic>? ?? const {},
  all:
      (json['all'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
  generation: (json['generation'] as num?)?.toInt() ?? 0,
  groups:
      (json['groups'] as List<dynamic>?)
          ?.map((e) => ProxyGroupSnapshot.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  nodesById:
      (json['nodesById'] as Map<String, dynamic>?)?.map(
        (k, e) =>
            MapEntry(k, ProxyNodeSnapshot.fromJson(e as Map<String, dynamic>)),
      ) ??
      const {},
);

Map<String, dynamic> _$ProxiesDataToJson(_ProxiesData instance) =>
    <String, dynamic>{
      'proxies': instance.proxies,
      'all': instance.all,
      'generation': instance.generation,
      'groups': instance.groups,
      'nodesById': instance.nodesById,
    };

_ProxyGroupSnapshot _$ProxyGroupSnapshotFromJson(Map<String, dynamic> json) =>
    _ProxyGroupSnapshot(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      nowId: json['nowId'] as String? ?? '',
      memberIds:
          (json['memberIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );

Map<String, dynamic> _$ProxyGroupSnapshotToJson(_ProxyGroupSnapshot instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'type': instance.type,
      'nowId': instance.nowId,
      'memberIds': instance.memberIds,
    };

_ProxyNodeSnapshot _$ProxyNodeSnapshotFromJson(Map<String, dynamic> json) =>
    _ProxyNodeSnapshot(
      id: json['id'] as String,
      stableKey: json['stableKey'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      providerName: json['providerName'] as String? ?? '',
    );

Map<String, dynamic> _$ProxyNodeSnapshotToJson(_ProxyNodeSnapshot instance) =>
    <String, dynamic>{
      'id': instance.id,
      'stableKey': instance.stableKey,
      'name': instance.name,
      'type': instance.type,
      'providerName': instance.providerName,
    };

_ProxyServerGeoParams _$ProxyServerGeoParamsFromJson(
  Map<String, dynamic> json,
) => _ProxyServerGeoParams(
  generation: (json['generation'] as num).toInt(),
  networkRevision: (json['networkRevision'] as num?)?.toInt() ?? 0,
  requestId: json['requestId'] as String? ?? '',
  all: json['all'] as bool? ?? false,
  memberIds:
      (json['memberIds'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
);

Map<String, dynamic> _$ProxyServerGeoParamsToJson(
  _ProxyServerGeoParams instance,
) => <String, dynamic>{
  'generation': instance.generation,
  'networkRevision': instance.networkRevision,
  'requestId': instance.requestId,
  'all': instance.all,
  'memberIds': instance.memberIds,
};

_GeoDatabaseGeneration _$GeoDatabaseGenerationFromJson(
  Map<String, dynamic> json,
) => _GeoDatabaseGeneration(
  country: (json['country'] as num?)?.toInt() ?? 0,
  asn: (json['asn'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$GeoDatabaseGenerationToJson(
  _GeoDatabaseGeneration instance,
) => <String, dynamic>{'country': instance.country, 'asn': instance.asn};

_ProxyGeoAddress _$ProxyGeoAddressFromJson(Map<String, dynamic> json) =>
    _ProxyGeoAddress(
      ip: json['ip'] as String,
      countryCode: json['countryCode'] as String? ?? '',
      asn: json['asn'] as String? ?? '',
      aso: json['aso'] as String? ?? '',
    );

Map<String, dynamic> _$ProxyGeoAddressToJson(_ProxyGeoAddress instance) =>
    <String, dynamic>{
      'ip': instance.ip,
      'countryCode': instance.countryCode,
      'asn': instance.asn,
      'aso': instance.aso,
    };

_ProxyServerGeo _$ProxyServerGeoFromJson(Map<String, dynamic> json) =>
    _ProxyServerGeo(
      memberId: json['memberId'] as String,
      serverHost: json['serverHost'] as String? ?? '',
      source: json['source'] as String? ?? '',
      status: json['status'] as String? ?? '',
      multiRegion: json['multiRegion'] as bool? ?? false,
      addresses:
          (json['addresses'] as List<dynamic>?)
              ?.map((e) => ProxyGeoAddress.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$ProxyServerGeoToJson(_ProxyServerGeo instance) =>
    <String, dynamic>{
      'memberId': instance.memberId,
      'serverHost': instance.serverHost,
      'source': instance.source,
      'status': instance.status,
      'multiRegion': instance.multiRegion,
      'addresses': instance.addresses,
    };

_ProxyServerGeos _$ProxyServerGeosFromJson(Map<String, dynamic> json) =>
    _ProxyServerGeos(
      generation: (json['generation'] as num).toInt(),
      requestId: json['requestId'] as String? ?? '',
      stale: json['stale'] as bool? ?? false,
      dbGeneration: json['dbGeneration'] == null
          ? const GeoDatabaseGeneration()
          : GeoDatabaseGeneration.fromJson(
              json['dbGeneration'] as Map<String, dynamic>,
            ),
      members:
          (json['members'] as Map<String, dynamic>?)?.map(
            (k, e) =>
                MapEntry(k, ProxyServerGeo.fromJson(e as Map<String, dynamic>)),
          ) ??
          const {},
    );

Map<String, dynamic> _$ProxyServerGeosToJson(_ProxyServerGeos instance) =>
    <String, dynamic>{
      'generation': instance.generation,
      'requestId': instance.requestId,
      'stale': instance.stale,
      'dbGeneration': instance.dbGeneration,
      'members': instance.members,
    };

_ProbeProxyExitParams _$ProbeProxyExitParamsFromJson(
  Map<String, dynamic> json,
) => _ProbeProxyExitParams(
  generation: (json['generation'] as num).toInt(),
  networkRevision: (json['networkRevision'] as num?)?.toInt() ?? 0,
  requestId: json['requestId'] as String? ?? '',
  groupId: json['groupId'] as String,
  memberId: json['memberId'] as String,
);

Map<String, dynamic> _$ProbeProxyExitParamsToJson(
  _ProbeProxyExitParams instance,
) => <String, dynamic>{
  'generation': instance.generation,
  'networkRevision': instance.networkRevision,
  'requestId': instance.requestId,
  'groupId': instance.groupId,
  'memberId': instance.memberId,
};

_ProxyExitGeo _$ProxyExitGeoFromJson(Map<String, dynamic> json) =>
    _ProxyExitGeo(
      generation: (json['generation'] as num).toInt(),
      requestId: json['requestId'] as String? ?? '',
      stale: json['stale'] as bool? ?? false,
      leafId: json['leafId'] as String? ?? '',
      pathIds:
          (json['pathIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      routeSample: json['routeSample'] as bool? ?? false,
      cached: json['cached'] as bool? ?? false,
      ip: json['ip'] as String? ?? '',
      countryCode: json['countryCode'] as String? ?? '',
      asn: json['asn'] as String? ?? '',
      aso: json['aso'] as String? ?? '',
      dbGeneration: json['dbGeneration'] == null
          ? const GeoDatabaseGeneration()
          : GeoDatabaseGeneration.fromJson(
              json['dbGeneration'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$ProxyExitGeoToJson(_ProxyExitGeo instance) =>
    <String, dynamic>{
      'generation': instance.generation,
      'requestId': instance.requestId,
      'stale': instance.stale,
      'leafId': instance.leafId,
      'pathIds': instance.pathIds,
      'routeSample': instance.routeSample,
      'cached': instance.cached,
      'ip': instance.ip,
      'countryCode': instance.countryCode,
      'asn': instance.asn,
      'aso': instance.aso,
      'dbGeneration': instance.dbGeneration,
    };

_ActionResult _$ActionResultFromJson(Map<String, dynamic> json) =>
    _ActionResult(
      method: $enumDecode(_$ActionMethodEnumMap, json['method']),
      data: json['data'],
      id: json['id'] as String?,
      code:
          $enumDecodeNullable(_$ResultTypeEnumMap, json['code']) ??
          ResultType.success,
    );

Map<String, dynamic> _$ActionResultToJson(_ActionResult instance) =>
    <String, dynamic>{
      'method': _$ActionMethodEnumMap[instance.method]!,
      'data': instance.data,
      'id': instance.id,
      'code': _$ResultTypeEnumMap[instance.code]!,
    };

const _$ResultTypeEnumMap = {ResultType.success: 0, ResultType.error: -1};
