import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part '../generated/actions/backup_action.g.dart';

abstract interface class RestoreConfigPersistence {
  Future<void> createSnapshot(String transactionRootPath);

  Future<void> save(Config config);

  Future<void> rollback(String transactionRootPath);

  Future<void> finalize(String transactionRootPath);
}

class _DefaultRestoreConfigPersistence implements RestoreConfigPersistence {
  const _DefaultRestoreConfigPersistence();

  @override
  Future<void> createSnapshot(String transactionRootPath) =>
      preferences.createRestoreSnapshot(transactionRootPath);

  @override
  Future<void> finalize(String transactionRootPath) =>
      preferences.finalizeRestoreSnapshot(transactionRootPath);

  @override
  Future<void> rollback(String transactionRootPath) =>
      preferences.rollbackRestoreSnapshot(transactionRootPath);

  @override
  Future<void> save(Config config) async {
    if (!await preferences.saveConfig(config)) {
      throw StateError('Failed to persist restored configuration');
    }
  }
}

final restoreConfigPersistenceProvider = Provider<RestoreConfigPersistence>(
  (_) => const _DefaultRestoreConfigPersistence(),
);

Config validateBackupConfig(
  Map<String, Object?> configMap,
  Config currentConfig,
) {
  if (configMap['version'] != migration.currentVersion) {
    throw const FormatException('Unsupported backup configuration version');
  }
  final rawDav = configMap['davProps'];
  if (rawDav != null && rawDav is! Map) {
    throw const FormatException('Invalid WebDAV configuration');
  }
  if (rawDav is Map &&
      rawDav['password'] is String &&
      (rawDav['password'] as String).isNotEmpty) {
    throw const FormatException('Plaintext backup credentials are not allowed');
  }
  final rawAppSetting = configMap['appSettingProps'];
  final rawTheme = configMap['themeProps'];
  if (rawAppSetting is! Map<String, Object?> ||
      rawTheme is! Map<String, Object?>) {
    throw const FormatException('Invalid backup configuration structure');
  }
  AppSettingProps.fromJson(rawAppSetting);
  ThemeProps.fromJson(rawTheme);
  final restored = Config.fromJson(configMap);
  final restoredDav = restored.davProps;
  final currentDav = currentConfig.davProps;
  if (restoredDav == null ||
      currentDav == null ||
      restoredDav.uri != currentDav.uri ||
      restoredDav.user != currentDav.user) {
    return restored;
  }
  return restored.copyWith(
    davProps: restoredDav.copyWith(password: currentDav.password),
  );
}

@Riverpod(keepAlive: true)
class BackupAction extends _$BackupAction {
  @override
  void build() {}

  Future<String> backup() async {
    final res = await Future.wait([
      database.profilesDao.fileNames().get(),
      database.scriptsDao.fileNames().get(),
    ]);
    final profileFileNames = res[0];
    final scriptFileNames = res[1];
    final configMap = ref.read(configProvider).toJson();
    configMap['version'] = await preferences.getVersion();
    final snapshot = File(await appPath.tempFilePath);
    try {
      await database.backupTo(snapshot.path);
      return backupTask(configMap, [
        ...profileFileNames,
        ...scriptFileNames,
      ], snapshot.path);
    } finally {
      await snapshot.safeDelete();
    }
  }

  Future<void> restore(RestoreOption option) async {
    final restoreDirPath = await appPath.restoreDirPath;
    final restoreDir = Directory(restoreDirPath);
    final restoreStrategy = ref.read(
      appSettingProvider.select((state) => state.restoreStrategy),
    );
    final isOverride = restoreStrategy == RestoreStrategy.override;
    try {
      final migrationData = await restoreTask();
      if (!await restoreDir.exists()) {
        throw currentAppLocalizations.restoreException;
      }
      final configMap = migrationData.configMap;
      final applyConfig = option != RestoreOption.onlyProfiles;
      final currentConfig = ref.read(configProvider);
      final Config? config;
      final MigrationData? previousDatabaseData;
      if (applyConfig) {
        if (configMap == null) {
          throw const FormatException('Backup configuration is missing');
        }
        config = validateBackupConfig(configMap, currentConfig);
        final currentProfileId = config.currentProfileId;
        if (currentProfileId != null &&
            !migrationData.profiles.any(
              (profile) => profile.id == currentProfileId,
            )) {
          throw const FormatException(
            'Backup configuration references a missing profile',
          );
        }
        previousDatabaseData = await database.readRestoreData();
      } else {
        config = null;
        previousDatabaseData = null;
      }
      final configPersistence = ref.read(restoreConfigPersistenceProvider);
      final createConfigSnapshot = config == null
          ? null
          : configPersistence.createSnapshot;
      final applyConfigState = switch (config) {
        final restoredConfig? => () => configPersistence.save(restoredConfig),
        null => null,
      };
      final rollbackDatabaseState = switch (previousDatabaseData) {
        final previous? => () => database.restore(
          previous.profiles,
          previous.scripts,
          previous.rules,
          previous.links,
          previous.proxyGroups,
          isOverride: true,
        ),
        null => null,
      };
      await applyRestoreFilesAtomically(
        migrationData,
        () {
          return database.restore(
            migrationData.profiles,
            migrationData.scripts,
            migrationData.rules,
            migrationData.links,
            migrationData.proxyGroups,
            isOverride: isOverride,
          );
        },
        createDatabaseSnapshot: database.backupTo,
        createExternalStateSnapshot: createConfigSnapshot,
        applyExternalState: applyConfigState,
        rollbackDatabase: rollbackDatabaseState,
        rollbackExternalState: configPersistence.rollback,
        finalizeExternalState: configPersistence.finalize,
      );
      if (config == null) return;
      ref.read(patchClashConfigProvider.notifier).value =
          config.patchClashConfig;
      ref.read(appSettingProvider.notifier).value = config.appSettingProps;
      ref.read(currentProfileIdProvider.notifier).value =
          config.currentProfileId;
      ref.read(davSettingProvider.notifier).value = config.davProps;
      ref.read(themeSettingProvider.notifier).value = config.themeProps;
      ref.read(windowSettingProvider.notifier).value = config.windowProps;
      ref.read(vpnSettingProvider.notifier).value = config.vpnProps;
      ref.read(proxiesStyleSettingProvider.notifier).value =
          config.proxiesStyleProps;
      ref.read(overrideDnsProvider.notifier).value = config.overrideDns;
      ref.read(networkSettingProvider.notifier).value = config.networkProps;
      ref.read(hotKeyActionsProvider.notifier).value = config.hotKeyActions;
      ref.read(excludeSSIDsProvider.notifier).value = config.excludeSSIDs;
      return;
    } finally {
      await restoreDir.safeDelete(recursive: true);
    }
  }
}
