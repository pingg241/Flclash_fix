import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';

Future<T> decodeJSONTask<T>(String data) async {
  return compute<String, T>(_decodeJSON, data);
}

Future<T> _decodeJSON<T>(String content) async {
  return json.decode(content);
}

Future<String> encodeJSONTask<T>(T data) async {
  return compute<T, String>(_encodeJSON, data);
}

Future<String> _encodeJSON<T>(T content) async {
  return json.encode(content);
}

Future<String> encodeYamlTask<T>(T data) async {
  return compute<T, String>(_encodeYaml, data);
}

Future<String> _encodeYaml<T>(T content) async {
  return yaml.encode(content);
}

Future<String> encodeMD5Task(String data) async {
  return compute<String, String>(_encodeMD5, data);
}

Future<String> _encodeMD5<T>(String content) async {
  return content.toMd5();
}

Future<List<Group>> toGroupsTask(ComputeGroupsState data) async {
  return compute<ComputeGroupsState, List<Group>>(_toGroupsTask, data);
}

Future<List<Group>> _toGroupsTask(ComputeGroupsState state) async {
  final proxiesData = state.proxiesData;
  final sortType = state.sortType;
  final delayMap = state.delayMap;
  final selectedMap = state.selectedMap;
  final defaultTestUrl = state.defaultTestUrl;
  final proxies = proxiesData.proxies;
  if (proxies.isEmpty) return [];
  final groups =
      proxiesData.groups.isNotEmpty && proxiesData.nodesById.isNotEmpty
      ? _runtimeGroups(proxiesData)
      : _legacyGroups(proxiesData);
  return computeSort(
    groups: groups,
    sortType: sortType,
    delayMap: delayMap,
    selectedMap: selectedMap,
    defaultTestUrl: defaultTestUrl,
  );
}

List<Group> _legacyGroups(ProxiesData proxiesData) {
  final proxies = proxiesData.proxies;
  final groupsRaw = proxiesData.all
      .where((name) {
        final proxy = proxies[name] ?? {};
        return GroupTypeExtension.valueList.contains(proxy['type']);
      })
      .map((groupName) {
        final group = Map<String, dynamic>.from(proxies[groupName] as Map);
        group['all'] = ((group['all'] ?? []) as List)
            .map((name) => proxies[name])
            .where((proxy) => proxy != null)
            .map((proxy) => Map<String, dynamic>.from(proxy as Map))
            .toList();
        return group;
      })
      .toList();
  return groupsRaw.map(Group.fromJson).toList();
}

List<Group> _runtimeGroups(ProxiesData proxiesData) {
  final nodes = proxiesData.nodesById;
  final groupSnapshots = {
    for (final group in proxiesData.groups) group.id: group,
  };
  return proxiesData.groups
      .where((group) => GroupTypeExtension.valueList.contains(group.type))
      .map((group) {
        final legacy = proxiesData.proxies[group.name];
        final raw = legacy is Map
            ? Map<String, dynamic>.from(legacy)
            : <String, dynamic>{};
        final groupNode = nodes[group.id];
        raw
          ..['name'] = group.name
          ..['type'] = group.type
          ..['runtimeId'] = group.id
          ..['stableKey'] = groupNode?.stableKey ?? ''
          ..['nowId'] = group.nowId
          ..['now'] = nodes[group.nowId]?.name ?? ''
          ..['all'] = group.memberIds
              .map((memberId) {
                final node = nodes[memberId];
                if (node == null) return null;
                final nestedGroup = groupSnapshots[memberId];
                return <String, dynamic>{
                  'name': node.name,
                  'type': node.type,
                  'now': nodes[nestedGroup?.nowId]?.name,
                  'runtimeId': node.id,
                  'stableKey': node.stableKey,
                  'providerName': node.providerName,
                };
              })
              .whereType<Map<String, dynamic>>()
              .toList();
        return Group.fromJson(raw);
      })
      .toList();
}

Future<VM2<String, String>> makeRealProfileTask(
  MakeRealProfileState data, {
  bool overrideProfileData = false,
}) async {
  return compute<VM2<MakeRealProfileState, bool>, VM2<String, String>>(
    _makeRealProfileTask,
    VM2(data, overrideProfileData),
  );
}

Future<VM2<String, String>> _makeRealProfileTask(
  VM2<MakeRealProfileState, bool> input,
) async {
  final data = input.a;
  final overrideProfileData = input.b;
  final rawConfig = Map.from(data.rawConfig);
  final realPatchConfig = data.realPatchConfig;
  final profilesPath = data.profilesPath;
  final profileId = data.profileId;
  final overrideDns = data.overrideDns;
  final addedRules = data.addedRules;
  final appendSystemDns = data.appendSystemDns;
  final defaultUA = data.defaultUA;
  String getProvidersFilePathInner(String type, String url) {
    return join(
      profilesPath,
      'providers',
      profileId.toString(),
      type,
      url.toMd5(),
    );
  }

  rawConfig['external-controller'] = realPatchConfig.externalController.value;
  rawConfig['external-ui'] = '';
  rawConfig['interface-name'] = '';
  rawConfig['external-ui-url'] = '';
  rawConfig['tcp-concurrent'] = realPatchConfig.tcpConcurrent;
  rawConfig['unified-delay'] = realPatchConfig.unifiedDelay;
  rawConfig['ipv6'] = realPatchConfig.ipv6;
  rawConfig['log-level'] = realPatchConfig.logLevel.name;
  rawConfig['port'] = 0;
  rawConfig['socks-port'] = 0;
  rawConfig['keep-alive-interval'] = realPatchConfig.keepAliveInterval;
  rawConfig['mixed-port'] = realPatchConfig.mixedPort;
  rawConfig['port'] = realPatchConfig.port;
  rawConfig['socks-port'] = realPatchConfig.socksPort;
  rawConfig['redir-port'] = realPatchConfig.redirPort;
  rawConfig['tproxy-port'] = realPatchConfig.tproxyPort;
  rawConfig['find-process-mode'] = realPatchConfig.findProcessMode.name;
  rawConfig['allow-lan'] = realPatchConfig.allowLan;
  rawConfig['mode'] = realPatchConfig.mode.name;
  if (rawConfig['tun'] == null) {
    rawConfig['tun'] = {};
  }
  rawConfig['tun']['enable'] = realPatchConfig.tun.enable;
  rawConfig['tun']['device'] = realPatchConfig.tun.device;
  rawConfig['tun']['dns-hijack'] = realPatchConfig.tun.dnsHijack;
  rawConfig['tun']['stack'] = realPatchConfig.tun.stack.name;
  rawConfig['tun']['route-address'] = realPatchConfig.tun.routeAddress;
  rawConfig['tun']['auto-route'] = realPatchConfig.tun.autoRoute;
  rawConfig['geodata-loader'] = realPatchConfig.geodataLoader.name;
  rawConfig['geo-auto-update'] = realPatchConfig.geoAutoUpdate;
  rawConfig['geo-update-interval'] = realPatchConfig.geoUpdateInterval;
  if (rawConfig['sniffer']?['sniff'] != null) {
    for (final value in (rawConfig['sniffer']?['sniff'] as Map).values) {
      if (value['ports'] != null && value['ports'] is List) {
        value['ports'] =
            value['ports']?.map((item) => item.toString()).toList() ?? [];
      }
    }
  }
  if (rawConfig['profile'] == null) {
    rawConfig['profile'] = {};
  }
  if (rawConfig['proxy-providers'] != null) {
    final proxyProviders = rawConfig['proxy-providers'] as Map;
    for (final key in proxyProviders.keys) {
      final proxyProvider = proxyProviders[key];
      if (proxyProvider['type'] != 'http') {
        continue;
      }
      if (proxyProvider['url'] != null) {
        proxyProvider['path'] = getProvidersFilePathInner(
          'proxies',
          proxyProvider['url'],
        );
      }
    }
  }
  if (rawConfig['rule-providers'] != null) {
    final ruleProviders = rawConfig['rule-providers'] as Map;
    for (final key in ruleProviders.keys) {
      final ruleProvider = ruleProviders[key];
      if (ruleProvider['type'] != 'http') {
        continue;
      }
      if (ruleProvider['url'] != null) {
        ruleProvider['path'] = getProvidersFilePathInner(
          'rules',
          ruleProvider['url'],
        );
      }
    }
  }
  rawConfig['profile']['store-selected'] = false;
  rawConfig['geox-url'] = realPatchConfig.geoXUrl.raw;
  rawConfig['global-ua'] = realPatchConfig.globalUa ?? defaultUA;
  if (rawConfig['hosts'] == null) {
    rawConfig['hosts'] = {};
  }
  for (final host in realPatchConfig.hosts.entries) {
    rawConfig['hosts'][host.key] = host.value.splitByMultipleSeparators;
  }
  if (rawConfig['dns'] == null) {
    rawConfig['dns'] = {};
  }
  final isEnableDns = rawConfig['dns']['enable'] == true;
  const systemDns = 'system://';
  if (overrideDns || !isEnableDns) {
    final dns = realPatchConfig.dns;
    rawConfig['dns'] = dns.toJson();
    rawConfig['dns']['nameserver-policy'] = {};
    for (final entry in dns.nameserverPolicy.entries) {
      rawConfig['dns']['nameserver-policy'][entry.key] =
          entry.value.splitByMultipleSeparators;
    }
  }
  if (appendSystemDns) {
    final List<String> nameserver = List<String>.from(
      rawConfig['dns']['nameserver'] ?? [],
    );
    if (!nameserver.contains(systemDns)) {
      rawConfig['dns']['nameserver'] = [...nameserver, systemDns];
    }
  }
  List<String> rules = [];
  if (!overrideProfileData) {
    if (rawConfig['rules'] != null) {
      rules = List<String>.from(rawConfig['rules']);
    }
    if (addedRules.isNotEmpty) {
      final hasMatchPlaceholder = addedRules.any(
        (item) => item.ruleTarget?.toUpperCase() == 'MATCH',
      );
      String? replacementTarget;

      if (hasMatchPlaceholder) {
        for (int i = rules.length - 1; i >= 0; i--) {
          final parsed = Rule.parse(rules[i]);
          if (parsed.ruleAction == RuleAction.MATCH) {
            final target = parsed.ruleTarget;
            if (target != null && target.isNotEmpty) {
              replacementTarget = target;
              break;
            }
          }
        }
      }
      final List<String> finalAddedRules;

      if (replacementTarget?.isNotEmpty == true) {
        finalAddedRules = [];
        for (int i = 0; i < addedRules.length; i++) {
          final parsed = addedRules[i];
          if (parsed.ruleTarget?.toUpperCase() == 'MATCH') {
            finalAddedRules.add(
              parsed.copyWith(ruleTarget: replacementTarget).rawValue,
            );
          } else {
            finalAddedRules.add(addedRules[i].rawValue);
          }
        }
      } else {
        finalAddedRules = addedRules.map((e) => e.rawValue).toList();
      }
      rules = [...finalAddedRules, ...rules];
    }
  } else {
    rules = data.rules.map((item) => item.rawValue).toList();
  }
  if (overrideProfileData) {
    rawConfig['proxy-groups'] = data.proxyGroups;
  }
  rawConfig['rules'] = rules;
  final yaml = await _encodeYaml(Map<String, dynamic>.from(rawConfig));
  return VM2(yaml, yaml.toMd5());
}

Future<List<String>> shakingProfileTask(
  VM2<Iterable<int>, Iterable<int>> data,
) async {
  return compute<
    VM3<Iterable<int>, Iterable<int>, RootIsolateToken>,
    List<String>
  >(_shakingProfileTask, VM3(data.a, data.b, RootIsolateToken.instance!));
}

Future<List<String>> _shakingProfileTask(
  VM3<Iterable<int>, Iterable<int>, RootIsolateToken> data,
) async {
  final profileIds = data.a;
  final scriptIds = data.b;
  final token = data.c;
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final profilesDir = Directory(await appPath.profilesPath);
  final scriptsDir = Directory(await appPath.scriptsDirPath);
  final providersDir = Directory(await appPath.getProvidersRootPath());
  final List<String> targets = [];
  void scanDirectory(
    Directory dir,
    Iterable<int> baseNames, {
    bool skipProvidersFolder = false,
  }) {
    if (!dir.existsSync()) return;
    final entities = dir.listSync(recursive: false, followLinks: false);

    for (final entity in entities) {
      if (entity is File) {
        final id = basenameWithoutExtension(entity.path);
        if (!baseNames.contains(int.tryParse(id))) {
          targets.add(entity.path);
        }
      } else if (skipProvidersFolder && entity is Directory) {
        if (basename(entity.path) == 'providers') {
          continue;
        }
      }
    }
  }

  scanDirectory(profilesDir, profileIds, skipProvidersFolder: true);
  scanDirectory(providersDir, profileIds);
  scanDirectory(scriptsDir, scriptIds);
  return targets;
}

Future<String> encodeLogsTask(List<Log> data) async {
  return compute<List<Log>, String>(_encodeLogsTask, data);
}

Future<String> _encodeLogsTask(List<Log> data) async {
  final logsRaw = data.map((item) => item.toString());
  final logsRawString = logsRaw.join('\n');
  return logsRawString;
}

Future<MigrationData> oldToNowTask(Map<String, Object?> data) async {
  final homeDir = await appPath.homeDirPath;
  return compute<VM3<Map<String, Object?>, String, String>, MigrationData>(
    _oldToNowTask,
    VM3(data, homeDir, homeDir),
  );
}

Future<MigrationData> _oldToNowTask(
  VM3<Map<String, Object?>, String, String> data,
) async {
  final configMap = data.a;
  final sourcePath = data.b;
  final targetPath = data.c;

  final accessControlMap = configMap['accessControl'];
  final isAccessControl = configMap['isAccessControl'];
  if (accessControlMap != null) {
    (accessControlMap as Map)['enable'] = isAccessControl;
    if (configMap['vpnProps'] != null) {
      final vpnPropsRaw = configMap['vpnProps'] as Map;
      vpnPropsRaw['accessControl'] = accessControlMap;
    }
  }
  if (configMap['vpnProps'] != null) {
    final vpnPropsRaw = configMap['vpnProps'] as Map;
    vpnPropsRaw['accessControlProps'] = vpnPropsRaw['accessControl'];
  }
  configMap['davProps'] = configMap['dav'];
  final appSettingProps =
      configMap['appSetting'] as Map<String, dynamic>? ?? {};
  appSettingProps['restoreStrategy'] = appSettingProps['recoveryStrategy'];
  configMap['appSettingProps'] = appSettingProps;
  configMap['proxiesStyleProps'] = configMap['proxiesStyle'];
  configMap['proxiesStyleProps'] = configMap['proxiesStyle'];
  // final overwriteMap = configMap['overwrite'] as Map? ?? {};
  // configMap['overwriteType'] = overwriteMap['type'];
  // configMap['scriptId'] = overwriteMap['scriptOverwrite'];
  List rawScripts = configMap['scripts'] as List<dynamic>? ?? [];
  if (rawScripts.isEmpty) {
    final scriptPropsJson = configMap['scriptProps'] as Map<String, dynamic>?;
    if (scriptPropsJson != null) {
      rawScripts = scriptPropsJson['scripts'] as List<dynamic>? ?? [];
    }
  }
  final Map<String, int> idMap = {};
  final List<Script> scripts = [];
  for (final rawScript in rawScripts) {
    final id = rawScript['id'] as String?;
    final content = rawScript['content'] as String?;
    final label = rawScript['label'] as String?;
    if (id == null || content == null || label == null) {
      continue;
    }
    final newId = idMap.updateCacheValue(rawScript['id'], () => snowflake.id);
    final path = _getScriptPath(targetPath, newId.toString());
    final file = File(path);
    await file.safeWriteAsString(content);
    scripts.add(
      Script(id: newId, label: label, lastUpdateTime: DateTime.now()),
    );
  }
  final List rawRules = configMap['rules'] as List<dynamic>? ?? [];
  final List<Rule> rules = [];
  final List<ProfileRuleLink> links = [];
  for (final rawRule in rawRules) {
    final id = idMap.updateCacheValue(rawRule['id'], () => snowflake.id);
    rawRule['id'] = id;
    final value = rawRule['value'] ?? '';
    rules.add(Rule.parse(value, id: id));
    links.add(ProfileRuleLink(ruleId: id));
  }
  final List rawProfiles = configMap['profiles'] as List<dynamic>? ?? [];
  final List<Profile> profiles = [];
  for (final rawProfile in rawProfiles) {
    final rawId = rawProfile['id'] as String?;
    if (rawId == null) {
      continue;
    }
    final profileId = idMap.updateCacheValue(rawId, () => snowflake.id);
    rawProfile['id'] = profileId;
    final overwrite = rawProfile['overwrite'] as Map?;
    if (overwrite != null) {
      final standardOverwrite = overwrite['standardOverwrite'] as Map?;
      if (standardOverwrite != null) {
        final addedRules = standardOverwrite['addedRules'] as List? ?? [];
        for (final addRule in addedRules) {
          final id = idMap.updateCacheValue(addRule['id'], () => snowflake.id);
          final value = addRule['value'] ?? '';
          rules.add(Rule.parse(value, id: id));
          links.add(
            ProfileRuleLink(
              profileId: profileId,
              ruleId: id,
              scene: RuleScene.added,
            ),
          );
        }
        final disabledRuleIds = standardOverwrite['disabledRuleIds'] as List?;
        if (disabledRuleIds != null) {
          for (final disabledRuleId in disabledRuleIds) {
            final newDisabledRuleId = idMap[disabledRuleId];
            if (newDisabledRuleId != null) {
              links.add(
                ProfileRuleLink(
                  profileId: profileId,
                  ruleId: newDisabledRuleId,
                  scene: RuleScene.disabled,
                ),
              );
            }
          }
        }
      }
      final scriptOverwrite = overwrite['scriptOverwrite'] as Map?;
      if (scriptOverwrite != null) {
        final scriptId = scriptOverwrite['scriptId'] as String?;
        rawProfile['scriptId'] = scriptId != null ? idMap[scriptId] : null;
      }
      rawProfile['overwriteType'] = overwrite['type'];
    }

    final sourceFile = File(_getProfilePath(sourcePath, rawId));
    final targetFilePath = _getProfilePath(targetPath, profileId.toString());
    await sourceFile.safeCopy(targetFilePath);
    profiles.add(Profile.fromJson(rawProfile));
  }
  final currentProfileId = configMap['currentProfileId'];
  configMap['currentProfileId'] = currentProfileId != null
      ? idMap[currentProfileId]
      : null;
  return MigrationData(
    configMap: configMap,
    profiles: profiles,
    rules: rules,
    scripts: scripts,
    links: links,
  );
}

Future<String> backupTask(
  Map<String, dynamic> configMap,
  Iterable<String> fileNames,
  String databaseSnapshotPath,
) async {
  return compute<
    VM4<Map<String, dynamic>, Iterable<String>, String, RootIsolateToken>,
    String
  >(
    _backupTask,
    VM4(configMap, fileNames, databaseSnapshotPath, RootIsolateToken.instance!),
  );
}

Future<String> _backupTask<T>(
  VM4<Map<String, dynamic>, Iterable<String>, String, RootIsolateToken> args,
) async {
  final configMap = args.a;
  final fileNames = args.b;
  final databaseSnapshotPath = args.c;
  final token = args.d;
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final configStr = json.encode(configMap);
  final profilesDir = Directory(await appPath.profilesPath);
  final scriptsDir = Directory(await appPath.scriptsDirPath);
  final tempZipFilePath = await appPath.tempFilePath;
  final tempConfigFile = File(await appPath.tempFilePath);
  final databaseSnapshot = File(databaseSnapshotPath);
  if (!await databaseSnapshot.exists()) {
    throw StateError('Database snapshot does not exist');
  }
  final encoder = ZipFileEncoder();
  encoder.create(tempZipFilePath);
  try {
    await tempConfigFile.writeAsString(configStr);
    await encoder.addFile(databaseSnapshot, backupDatabaseName);
    await encoder.addFile(tempConfigFile, configJsonName);
    if (await profilesDir.exists()) {
      await encoder.addDirectory(
        profilesDir,
        filter: (file, _) => fileNames.contains(basename(file.path))
            ? ZipFileOperation.include
            : ZipFileOperation.skip,
      );
    }
    if (await scriptsDir.exists()) {
      await encoder.addDirectory(
        scriptsDir,
        filter: (file, _) => fileNames.contains(basename(file.path))
            ? ZipFileOperation.include
            : ZipFileOperation.skip,
      );
    }
    encoder.close();
    return tempZipFilePath;
  } catch (_) {
    encoder.close();
    await File(tempZipFilePath).safeDelete();
    rethrow;
  } finally {
    await tempConfigFile.safeDelete();
  }
}

Future<MigrationData> restoreTask() async {
  return compute<RootIsolateToken, MigrationData>(
    _restoreTask,
    RootIsolateToken.instance!,
  );
}

Future<MigrationData> _restoreTask(RootIsolateToken token) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final backupFilePath = await appPath.backupFilePath;
  final restoreDirPath = await appPath.restoreDirPath;
  await extractBackupArchive(backupFilePath, restoreDirPath);
  final restoreConfigFile = File(join(restoreDirPath, configJsonName));
  if (!await restoreConfigFile.exists()) {
    throw currentAppLocalizations.invalidBackupFile;
  }
  final restoreConfigMap =
      json.decode(await restoreConfigFile.readAsString())
          as Map<String, Object?>?;
  final version = restoreConfigMap?['version'] ?? 0;
  MigrationData migrationData = MigrationData(configMap: restoreConfigMap);
  if (version == 0 && restoreConfigMap != null) {
    migrationData = await _oldToNowTask(
      VM3(restoreConfigMap, restoreDirPath, restoreDirPath),
    );
    return migrationData;
  }
  final backupDatabaseFile = File(join(restoreDirPath, backupDatabaseName));
  if (!await backupDatabaseFile.exists()) {
    return migrationData;
  }
  final database = Database(
    driftDatabase(
      name: 'database',
      native: DriftNativeOptions(
        databaseDirectory: () async => Directory(restoreDirPath),
      ),
    ),
  );
  try {
    final integrity = await database
        .customSelect('PRAGMA integrity_check')
        .get();
    if (integrity.any((row) => row.data.values.single != 'ok')) {
      throw const FormatException('Invalid backup database');
    }
    final results = await Future.wait([
      database.profilesDao.query().get(),
      database.scriptsDao.query().get(),
      database.rules.all().map((item) => item.toRule()).get(),
      database.profileRuleLinks.all().map((item) => item.toLink()).get(),
      database.proxyGroups.all().map((item) => item.toProxyGroup()).get(),
    ]);
    final profiles = results[0].cast<Profile>();
    final scripts = results[1].cast<Script>();
    await _validateRestoreFiles(restoreDirPath, profiles, scripts);
    return migrationData.copyWith(
      profiles: profiles,
      scripts: scripts,
      rules: results[2].cast<Rule>(),
      links: results[3].cast<ProfileRuleLink>(),
      proxyGroups: results[4].cast<ProxyGroup>(),
    );
  } finally {
    await database.close();
  }
}

const _maxBackupEntries = 4096;
const _maxBackupFileSize = 256 * 1024 * 1024;
const _maxBackupTotalSize = 512 * 1024 * 1024;

Future<void> extractBackupArchive(String archivePath, String outputPath) async {
  final outputDir = Directory(outputPath);
  await outputDir.safeDelete(recursive: true);
  final input = InputFileStream(archivePath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    if (archive.files.length > _maxBackupEntries) {
      throw const FormatException('Backup contains too many entries');
    }
    final entries = <ArchiveFile, String>{};
    final seenPaths = <String>{};
    var totalSize = 0;
    for (final entry in archive.files) {
      final normalized = _validateBackupEntry(entry);
      if (!seenPaths.add(normalized.toLowerCase())) {
        throw const FormatException('Backup contains duplicate paths');
      }
      if (entry.isFile) {
        totalSize += entry.size;
        if (entry.size > _maxBackupFileSize ||
            totalSize > _maxBackupTotalSize) {
          throw const FormatException('Backup is too large');
        }
      }
      entries[entry] = normalized;
    }
    await outputDir.create(recursive: true);
    var extractedSize = 0;
    for (final entry in entries.entries) {
      final destination = joinAll([outputPath, ...posix.split(entry.value)]);
      if (entry.key.isDirectory) {
        await Directory(destination).create(recursive: true);
        continue;
      }
      await File(destination).parent.create(recursive: true);
      final output = OutputFileStream(destination);
      try {
        entry.key.writeContent(output);
      } finally {
        await output.close();
      }
      final fileSize = await File(destination).length();
      extractedSize += fileSize;
      if (fileSize > _maxBackupFileSize ||
          extractedSize > _maxBackupTotalSize) {
        throw const FormatException('Backup entry is too large');
      }
    }
  } catch (_) {
    await outputDir.safeDelete(recursive: true);
    rethrow;
  } finally {
    await input.close();
  }
}

String _validateBackupEntry(ArchiveFile entry) {
  final rawName = entry.name.replaceAll('\\', '/');
  final normalized = posix.normalize(rawName);
  final parts = rawName.split('/');
  if (rawName.isEmpty ||
      rawName.contains('\u0000') ||
      rawName.startsWith('/') ||
      RegExp(r'^[A-Za-z]:/').hasMatch(rawName) ||
      parts.contains('..') ||
      entry.isSymbolicLink ||
      normalized == '.' ||
      normalized == '..' ||
      normalized.startsWith('../')) {
    throw const FormatException('Backup contains an unsafe path');
  }
  final allowed =
      normalized == configJsonName ||
      normalized == backupDatabaseName ||
      normalized == profilesDirectoryName ||
      normalized == 'scripts' ||
      RegExp(r'^profiles/[^/]+\.yaml$').hasMatch(normalized) ||
      RegExp(r'^scripts/[^/]+\.js$').hasMatch(normalized);
  if (!allowed) {
    throw const FormatException('Backup contains an unexpected path');
  }
  return normalized;
}

Future<void> _validateRestoreFiles(
  String restoreRoot,
  List<Profile> profiles,
  List<Script> scripts,
) async {
  final files = [
    ...profiles.map(
      (item) => File(_getProfilePath(restoreRoot, item.id.toString())),
    ),
    ...scripts.map(
      (item) => File(_getScriptPath(restoreRoot, item.id.toString())),
    ),
  ];
  for (final file in files) {
    if (!await file.exists()) {
      throw const FormatException('Backup is missing referenced files');
    }
  }
}

String _getScriptPath(String root, String fileName) {
  return join(root, 'scripts', '$fileName.js');
}

String _getProfilePath(String root, String fileName) {
  return join(root, 'profiles', '$fileName.yaml');
}

Future<List<T>> mapListTask<T, S>(List<S> results, T Function(S) mapper) async {
  return compute<VM2<List<S>, T Function(S)>, List<T>>(
    _mapListTask,
    VM2(results, mapper),
  );
}

Future<List<T>> _mapListTask<T, S>(VM2<List<S>, T Function(S)> vm2) async {
  final results = vm2.a;
  final mapper = vm2.b;
  return results.map((item) => mapper(item)).toList();
}
