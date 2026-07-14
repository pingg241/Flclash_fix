import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fl_clash/models/models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constant.dart';

const _davPasswordKey = 'webdav_password';
const _restorePreferencesSnapshotName = 'preferences-before-restore.json';
const _restorePreferencesRolledBackName = 'preferences-rolled-back';
const _configTransactionsDirectoryName = '.config-transactions';
const _configTransactionManifestName = 'manifest.json';
const _configPreparedMarkerName = 'prepared';
const _configSecretAppliedMarkerName = 'secret-applied';
const _configAppliedMarkerName = 'config-applied';
const _configSettledMarkerName = 'settled';
const _configDiscardedMarkerName = 'discarded';

typedef ConfigPreferenceWriter = Future<bool> Function(String value);
typedef ConfigPreferenceRemover = Future<bool> Function();
typedef PreferenceWriter = Future<bool> Function(String key, Object value);
typedef PreferenceRemover = Future<bool> Function(String key);
typedef PreferencesClearer = Future<bool> Function();
typedef ConfigTransactionDirectoryProvider = Future<String> Function();
typedef ConfigTransactionFaultInjector =
    FutureOr<void> Function(ConfigTransactionCheckpoint checkpoint);

enum ConfigTransactionCheckpoint {
  journalPersisted,
  oldCredentialStaged,
  newCredentialStaged,
  credentialsPrepared,
  secretApplied,
  secretPhasePersisted,
  configApplied,
  configPhasePersisted,
}

class ConfigTransactionInterruption implements Exception {
  const ConfigTransactionInterruption();
}

class PreferencesCompensationException implements Exception {
  final Object cause;
  final Object compensationError;

  const PreferencesCompensationException(this.cause, this.compensationError);

  @override
  String toString() {
    return 'PreferencesCompensationException: $cause; '
        'compensation failed: $compensationError';
  }
}

abstract interface class CredentialStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class PlatformCredentialStorage implements CredentialStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(migrateWithBackup: true),
  );

  const PlatformCredentialStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class Preferences {
  static Preferences? _instance;
  Completer<SharedPreferences?> sharedPreferencesCompleter = Completer();
  final CredentialStorage _credentialStorage;
  final ConfigPreferenceWriter? _configWriter;
  final ConfigPreferenceRemover? _configRemover;
  final PreferenceWriter? _preferenceWriter;
  final PreferenceRemover? _preferenceRemover;
  final PreferencesClearer? _preferencesClearer;
  final ConfigTransactionDirectoryProvider? _configTransactionDirectoryProvider;
  final ConfigTransactionFaultInjector? _configTransactionFaultInjector;
  Future<void> _configOperationTail = Future<void>.value();

  Future<bool> get isInit async =>
      await sharedPreferencesCompleter.future != null;

  Preferences._internal()
    : _credentialStorage = const PlatformCredentialStorage(),
      _configWriter = null,
      _configRemover = null,
      _preferenceWriter = null,
      _preferenceRemover = null,
      _preferencesClearer = null,
      _configTransactionDirectoryProvider = _defaultConfigTransactionDirectory,
      _configTransactionFaultInjector = null {
    SharedPreferences.getInstance()
        .then((value) => sharedPreferencesCompleter.complete(value))
        .onError((_, _) => sharedPreferencesCompleter.complete(null));
  }

  factory Preferences() {
    _instance ??= Preferences._internal();
    return _instance!;
  }

  Preferences.test(
    SharedPreferences sharedPreferences,
    CredentialStorage credentialStorage, {
    ConfigPreferenceWriter? configWriter,
    ConfigPreferenceRemover? configRemover,
    PreferenceWriter? preferenceWriter,
    PreferenceRemover? preferenceRemover,
    PreferencesClearer? preferencesClearer,
    ConfigTransactionDirectoryProvider? configTransactionDirectoryProvider,
    ConfigTransactionFaultInjector? configTransactionFaultInjector,
  }) : _credentialStorage = credentialStorage,
       _configWriter = configWriter,
       _configRemover = configRemover,
       _preferenceWriter = preferenceWriter,
       _preferenceRemover = preferenceRemover,
       _preferencesClearer = preferencesClearer,
       _configTransactionDirectoryProvider = configTransactionDirectoryProvider,
       _configTransactionFaultInjector = configTransactionFaultInjector {
    sharedPreferencesCompleter.complete(sharedPreferences);
  }

  Future<int> getVersion() {
    return _serializeConfigOperation(_getVersion);
  }

  Future<int> _getVersion() async {
    final preferences = await sharedPreferencesCompleter.future;
    return preferences?.getInt('version') ?? 0;
  }

  Future<void> setVersion(int version) {
    return _serializeConfigOperation(() => _setVersion(version));
  }

  Future<void> _setVersion(int version) async {
    final preferences = await sharedPreferencesCompleter.future;
    if (preferences == null) return;
    if (!await _writePreference(preferences, 'version', version)) {
      throw StateError('Failed to save application version');
    }
  }

  Future<void> saveShareState(SharedState shareState) {
    return _serializeConfigOperation(() => _saveShareState(shareState));
  }

  Future<void> _saveShareState(SharedState shareState) async {
    final preferences = await sharedPreferencesCompleter.future;
    if (preferences == null) return;
    if (!await _writePreference(
      preferences,
      'sharedState',
      json.encode(shareState),
    )) {
      throw StateError('Failed to save shared state');
    }
  }

  Future<T> _serializeConfigOperation<T>(Future<T> Function() operation) {
    final result = _configOperationTail.then((_) => operation());
    _configOperationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<Map<String, Object?>?> getConfigMap() {
    return _serializeConfigOperation(_getConfigMap);
  }

  Future<Map<String, Object?>?> _getConfigMap() async {
    final preferences = await sharedPreferencesCompleter.future;
    if (preferences != null && _configTransactionDirectoryProvider != null) {
      await _recoverConfigTransactions(preferences);
    }
    try {
      final configString = preferences?.getString(configKey);
      if (configString == null) return null;
      final Map<String, Object?>? configMap = json.decode(configString);
      if (configMap == null) return null;
      await _injectDavPassword(preferences, configMap);
      return configMap;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>?> getClashConfigMap() {
    return _serializeConfigOperation(_getClashConfigMap);
  }

  Future<Map<String, Object?>?> _getClashConfigMap() async {
    try {
      final preferences = await sharedPreferencesCompleter.future;
      final clashConfigString = preferences?.getString(clashConfigKey);
      if (clashConfigString == null) return null;
      return json.decode(clashConfigString);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearClashConfig() {
    return _serializeConfigOperation(_clearClashConfig);
  }

  Future<void> _clearClashConfig() async {
    final preferences = await sharedPreferencesCompleter.future;
    if (preferences != null &&
        !await _removePreference(preferences, clashConfigKey)) {
      throw StateError('Failed to clear legacy Clash config');
    }
  }

  Future<Config?> getConfig() async {
    final configMap = await getConfigMap();
    if (configMap == null) {
      return null;
    }
    return Config.fromJson(configMap);
  }

  Future<bool> saveConfig(Config config) {
    return _serializeConfigOperation(() => _saveConfig(config));
  }

  Future<bool> _saveConfig(Config config) async {
    if (_configTransactionDirectoryProvider != null) {
      return _saveConfigDurably(config);
    }
    return _saveConfigWithCompensation(config);
  }

  Future<bool> _saveConfigWithCompensation(Config config) async {
    final preferences = await sharedPreferencesCompleter.future;
    if (preferences == null) return false;
    final previousConfig = preferences.getString(configKey);
    final previousPassword = await _credentialStorage.read(_davPasswordKey);
    final password = config.davProps?.password;
    try {
      if (password == null || password.isEmpty) {
        await _credentialStorage.delete(_davPasswordKey);
      } else {
        await _credentialStorage.write(_davPasswordKey, password);
      }
      final saved = await _writeConfig(preferences, json.encode(config));
      if (!saved) {
        throw StateError('Failed to save application preferences');
      }
      return true;
    } catch (error, stackTrace) {
      try {
        await _restoreConfigState(
          preferences,
          config: previousConfig,
          password: previousPassword,
        );
      } catch (compensationError, compensationStackTrace) {
        Error.throwWithStackTrace(
          PreferencesCompensationException(error, compensationError),
          compensationStackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<bool> _saveConfigDurably(Config config) async {
    final sharedPreferences = await sharedPreferencesCompleter.future;
    if (sharedPreferences == null) return false;
    await _recoverConfigTransactions(sharedPreferences);

    final sanitizedOld = _sanitizeConfigForJournal(
      sharedPreferences.getString(configKey),
    );
    final oldConfig = sanitizedOld.config;
    final newConfig = json.encode(config);
    final storedPassword = await _credentialStorage.read(_davPasswordKey);
    final password = config.davProps?.password;
    final newPassword = password == null || password.isEmpty ? null : password;
    if (storedPassword == newPassword) {
      if (!await _writeConfig(sharedPreferences, newConfig)) {
        throw StateError('Failed to save application preferences');
      }
      return true;
    }
    final oldPassword = storedPassword ?? sanitizedOld.legacyPassword;
    final transaction = await _createConfigTransaction(
      oldConfig: oldConfig,
      newConfig: newConfig,
      hasOldPassword: oldPassword != null,
      hasNewPassword: newPassword != null,
    );

    try {
      await _configTransactionFaultInjector?.call(
        ConfigTransactionCheckpoint.journalPersisted,
      );
      if (oldPassword != null) {
        await _credentialStorage.write(
          transaction.oldCredentialKey,
          oldPassword,
        );
      }
      await _configTransactionFaultInjector?.call(
        ConfigTransactionCheckpoint.oldCredentialStaged,
      );
      if (newPassword != null) {
        await _credentialStorage.write(
          transaction.newCredentialKey,
          newPassword,
        );
      }
      await _configTransactionFaultInjector?.call(
        ConfigTransactionCheckpoint.newCredentialStaged,
      );
      await _writeConfigTransactionMarker(
        transaction.root,
        _configPreparedMarkerName,
      );
      await _configTransactionFaultInjector?.call(
        ConfigTransactionCheckpoint.credentialsPrepared,
      );

      await _applyDavPassword(newPassword);
      await _configTransactionFaultInjector?.call(
        ConfigTransactionCheckpoint.secretApplied,
      );
      await _writeConfigTransactionMarker(
        transaction.root,
        _configSecretAppliedMarkerName,
      );
      await _configTransactionFaultInjector?.call(
        ConfigTransactionCheckpoint.secretPhasePersisted,
      );

      if (!await _writeConfig(sharedPreferences, newConfig)) {
        throw StateError('Failed to save application preferences');
      }
      await _configTransactionFaultInjector?.call(
        ConfigTransactionCheckpoint.configApplied,
      );
      await _writeConfigTransactionMarker(
        transaction.root,
        _configAppliedMarkerName,
      );
      await _configTransactionFaultInjector?.call(
        ConfigTransactionCheckpoint.configPhasePersisted,
      );
      await _writeConfigTransactionMarker(
        transaction.root,
        _configSettledMarkerName,
      );
    } on ConfigTransactionInterruption {
      rethrow;
    } catch (error, stackTrace) {
      try {
        await _recoverConfigTransaction(sharedPreferences, transaction.root);
      } catch (compensationError, compensationStackTrace) {
        Error.throwWithStackTrace(
          PreferencesCompensationException(error, compensationError),
          compensationStackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    if (!await _cleanupConfigTransactionBestEffort(transaction)) {
      throw StateError('Failed to finalize configuration transaction');
    }
    return true;
  }

  Future<void> recoverConfigTransactions() {
    return _serializeConfigOperation(() async {
      final sharedPreferences = await sharedPreferencesCompleter.future;
      if (sharedPreferences == null) {
        throw StateError('Application preferences are unavailable');
      }
      await _recoverConfigTransactions(sharedPreferences);
    });
  }

  Future<bool> _writeConfig(SharedPreferences preferences, String value) {
    return _configWriter?.call(value) ??
        _writePreference(preferences, configKey, value);
  }

  Future<bool> _removeConfig(SharedPreferences preferences) {
    return _configRemover?.call() ?? _removePreference(preferences, configKey);
  }

  Future<bool> _writePreference(
    SharedPreferences preferences,
    String key,
    Object value,
  ) {
    final writer = _preferenceWriter;
    if (writer != null) {
      return writer(key, value);
    }
    return switch (value) {
      int() => preferences.setInt(key, value),
      String() => preferences.setString(key, value),
      bool() => preferences.setBool(key, value),
      double() => preferences.setDouble(key, value),
      List<String>() => preferences.setStringList(key, value),
      _ => throw ArgumentError.value(value, 'value'),
    };
  }

  Future<bool> _removePreference(SharedPreferences preferences, String key) {
    return _preferenceRemover?.call(key) ?? preferences.remove(key);
  }

  Future<bool> _clearStoredPreferences(SharedPreferences preferences) {
    return _preferencesClearer?.call() ?? preferences.clear();
  }

  Future<void> _restoreConfigState(
    SharedPreferences preferences, {
    required String? config,
    required String? password,
  }) async {
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      final restored = config == null
          ? await _removeConfig(preferences)
          : await _writeConfig(preferences, config);
      if (!restored) {
        throw StateError('Failed to restore application preferences');
      }
    } catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }
    try {
      await _restoreDavPassword(password);
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  Future<void> _restoreDavPassword(String? password) {
    return password == null
        ? _credentialStorage.delete(_davPasswordKey)
        : _credentialStorage.write(_davPasswordKey, password);
  }

  Future<void> _applyDavPassword(String? password) {
    return password == null
        ? _credentialStorage.delete(_davPasswordKey)
        : _credentialStorage.write(_davPasswordKey, password);
  }

  Future<_ConfigTransaction> _createConfigTransaction({
    required String? oldConfig,
    required String newConfig,
    required bool hasOldPassword,
    required bool hasNewPassword,
  }) async {
    final directoryPath = await _configTransactionDirectoryProvider!.call();
    final transactionsRoot = Directory(directoryPath);
    await transactionsRoot.create(recursive: true);
    final transactionId = _newConfigTransactionId();
    final root = Directory(p.join(directoryPath, 'pending-$transactionId'));
    await root.create();
    final transaction = _ConfigTransaction(
      root: root,
      transactionId: transactionId,
      oldConfig: oldConfig,
      newConfig: newConfig,
      hasOldPassword: hasOldPassword,
      hasNewPassword: hasNewPassword,
    );
    try {
      await _writeNewConfigTransactionFile(
        File(p.join(root.path, _configTransactionManifestName)),
        jsonEncode(transaction.toJson()),
      );
      return transaction;
    } catch (_) {
      try {
        await root.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _recoverConfigTransactions(
    SharedPreferences sharedPreferences,
  ) async {
    final provider = _configTransactionDirectoryProvider;
    if (provider == null) return;
    final transactionsRoot = Directory(await provider());
    if (!await transactionsRoot.exists()) return;
    final roots = await transactionsRoot
        .list(followLinks: false)
        .where((entity) => entity is Directory)
        .cast<Directory>()
        .toList();
    roots.sort((left, right) => left.path.compareTo(right.path));
    for (final root in roots) {
      await _recoverConfigTransaction(sharedPreferences, root);
    }
    if (await transactionsRoot.exists() &&
        await transactionsRoot.list(followLinks: false).isEmpty) {
      await transactionsRoot.delete();
    }
  }

  Future<void> _recoverConfigTransaction(
    SharedPreferences sharedPreferences,
    Directory root,
  ) async {
    final discarded = await File(
      p.join(root.path, _configDiscardedMarkerName),
    ).exists();
    if (discarded) {
      if (!await _cleanupConfigTransactionRootBestEffort(root)) {
        throw StateError('Failed to discard configuration transaction');
      }
      return;
    }
    final manifest = File(p.join(root.path, _configTransactionManifestName));
    if (!await manifest.exists()) {
      if (!await _cleanupConfigTransactionRootBestEffort(root)) {
        throw StateError('Failed to finalize configuration transaction');
      }
      return;
    }
    final transaction = _ConfigTransaction.fromJson(
      root,
      jsonDecode(await manifest.readAsString()),
    );
    final prepared = await File(
      p.join(root.path, _configPreparedMarkerName),
    ).exists();
    final secretApplied = await File(
      p.join(root.path, _configSecretAppliedMarkerName),
    ).exists();
    final configApplied = await File(
      p.join(root.path, _configAppliedMarkerName),
    ).exists();
    final settled = await File(
      p.join(root.path, _configSettledMarkerName),
    ).exists();

    if (!settled && prepared) {
      final currentConfig = sharedPreferences.getString(configKey);
      final commit =
          configApplied ||
          (secretApplied &&
              (transaction.oldConfig == transaction.newConfig ||
                  currentConfig == transaction.newConfig));
      if (commit) {
        await _applyTransactionState(
          sharedPreferences,
          transaction,
          config: transaction.newConfig,
          hasPassword: transaction.hasNewPassword,
          credentialKey: transaction.newCredentialKey,
          allowCurrentCredentialFallback: true,
        );
      } else {
        await _applyTransactionState(
          sharedPreferences,
          transaction,
          config: transaction.oldConfig,
          hasPassword: transaction.hasOldPassword,
          credentialKey: transaction.oldCredentialKey,
          allowCurrentCredentialFallback: false,
        );
      }
    }
    if (!settled) {
      await _writeConfigTransactionMarker(root, _configSettledMarkerName);
    }

    final cleaned = await _cleanupConfigTransactionBestEffort(transaction);
    if (!cleaned) {
      throw StateError('Failed to finalize configuration transaction');
    }
  }

  Future<void> _applyTransactionState(
    SharedPreferences sharedPreferences,
    _ConfigTransaction transaction, {
    required String? config,
    required bool hasPassword,
    required String credentialKey,
    required bool allowCurrentCredentialFallback,
  }) async {
    if (hasPassword) {
      final staged = await _credentialStorage.read(credentialKey);
      if (staged != null) {
        await _credentialStorage.write(_davPasswordKey, staged);
      } else if (!allowCurrentCredentialFallback ||
          await _credentialStorage.read(_davPasswordKey) == null) {
        throw StateError('Configuration transaction credential is missing');
      }
    } else {
      await _credentialStorage.delete(_davPasswordKey);
    }

    final persisted = config == null
        ? await _removeConfig(sharedPreferences)
        : await _writeConfig(sharedPreferences, config);
    if (!persisted) {
      throw StateError('Failed to recover application preferences');
    }
  }

  Future<bool> _cleanupConfigTransactionBestEffort(
    _ConfigTransaction transaction,
  ) {
    return _cleanupConfigTransactionRootBestEffort(transaction.root);
  }

  Future<bool> _cleanupConfigTransactionRootBestEffort(Directory root) async {
    var credentialsCleaned = true;
    for (final key in _configTransactionCredentialKeys(root)) {
      try {
        await _credentialStorage.delete(key);
      } catch (_) {
        credentialsCleaned = false;
      }
    }
    if (!credentialsCleaned) return false;
    try {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> createRestoreSnapshot(String transactionRootPath) {
    return _serializeConfigOperation(
      () => _createRestoreSnapshot(transactionRootPath),
    );
  }

  Future<void> _createRestoreSnapshot(String transactionRootPath) async {
    final sharedPreferences = await sharedPreferencesCompleter.future;
    if (sharedPreferences == null) {
      throw StateError('Application preferences are unavailable');
    }
    await _recoverConfigTransactions(sharedPreferences);
    final transactionId = p.basename(transactionRootPath);
    final credentialBackupKey = '${_davPasswordKey}_restore_$transactionId';
    final credential = await _credentialStorage.read(_davPasswordKey);
    if (credential != null) {
      await _credentialStorage.write(credentialBackupKey, credential);
    }
    final snapshot = File(
      p.join(transactionRootPath, _restorePreferencesSnapshotName),
    );
    final temporary = File('${snapshot.path}.tmp');
    try {
      await temporary.writeAsString(
        jsonEncode({
          'hasConfig': sharedPreferences.containsKey(configKey),
          'config': sharedPreferences.getString(configKey),
          'hasCredential': credential != null,
          'credentialBackupKey': credentialBackupKey,
        }),
        flush: true,
      );
      await temporary.rename(snapshot.path);
    } catch (_) {
      try {
        await _credentialStorage.delete(credentialBackupKey);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> rollbackRestoreSnapshot(String transactionRootPath) {
    return _serializeConfigOperation(
      () => _rollbackRestoreSnapshot(transactionRootPath),
    );
  }

  Future<void> _rollbackRestoreSnapshot(String transactionRootPath) async {
    final rolledBackMarker = File(
      p.join(transactionRootPath, _restorePreferencesRolledBackName),
    );
    if (await rolledBackMarker.exists()) {
      return;
    }
    final snapshot = File(
      p.join(transactionRootPath, _restorePreferencesSnapshotName),
    );
    if (!await snapshot.exists()) {
      return;
    }
    final raw = jsonDecode(await snapshot.readAsString());
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid preferences restore snapshot');
    }
    final sharedPreferences = await sharedPreferencesCompleter.future;
    if (sharedPreferences == null) {
      throw StateError('Application preferences are unavailable');
    }
    final hasConfig = raw['hasConfig'] == true;
    final config = raw['config'];
    final configRestored = hasConfig
        ? config is String &&
              await _writePreference(sharedPreferences, configKey, config)
        : await _removePreference(sharedPreferences, configKey);
    if (!configRestored) {
      throw StateError('Failed to restore application preferences');
    }
    final credentialBackupKey = raw['credentialBackupKey'];
    if (credentialBackupKey is! String) {
      throw const FormatException('Invalid credential restore reference');
    }
    if (raw['hasCredential'] == true) {
      final credential = await _credentialStorage.read(credentialBackupKey);
      if (credential == null) {
        throw StateError('Credential restore reference is unavailable');
      }
      await _credentialStorage.write(_davPasswordKey, credential);
    } else {
      await _credentialStorage.delete(_davPasswordKey);
    }
    final temporary = File('${rolledBackMarker.path}.tmp');
    try {
      await temporary.writeAsString('', flush: true);
      await temporary.rename(rolledBackMarker.path);
    } finally {
      try {
        if (await temporary.exists()) {
          await temporary.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> finalizeRestoreSnapshot(String transactionRootPath) {
    return _serializeConfigOperation(
      () => _finalizeRestoreSnapshot(transactionRootPath),
    );
  }

  Future<void> _finalizeRestoreSnapshot(String transactionRootPath) async {
    final snapshot = File(
      p.join(transactionRootPath, _restorePreferencesSnapshotName),
    );
    String credentialBackupKey =
        '${_davPasswordKey}_restore_${p.basename(transactionRootPath)}';
    if (await snapshot.exists()) {
      final raw = jsonDecode(await snapshot.readAsString());
      if (raw is Map<String, dynamic> && raw['credentialBackupKey'] is String) {
        credentialBackupKey = raw['credentialBackupKey'] as String;
      }
    }
    await _credentialStorage.delete(credentialBackupKey);
  }

  Future<void> clearPreferences() {
    return _serializeConfigOperation(_clearPreferences);
  }

  Future<void> _clearPreferences() async {
    await _discardConfigTransactions();
    final sharedPreferencesIns = await sharedPreferencesCompleter.future;
    final results = await Future.wait([
      sharedPreferencesIns == null
          ? Future<bool>.value(true)
          : _clearStoredPreferences(sharedPreferencesIns),
      _credentialStorage.delete(_davPasswordKey).then((_) => true),
    ]);
    if (!results.first) {
      throw StateError('Failed to clear application preferences');
    }
  }

  Future<void> _discardConfigTransactions() async {
    final provider = _configTransactionDirectoryProvider;
    if (provider == null) return;
    final transactionsRoot = Directory(await provider());
    if (!await transactionsRoot.exists()) return;
    final roots = await transactionsRoot
        .list(followLinks: false)
        .where((entity) => entity is Directory)
        .cast<Directory>()
        .toList();
    roots.sort((left, right) => left.path.compareTo(right.path));
    for (final root in roots) {
      await _writeConfigTransactionMarker(root, _configDiscardedMarkerName);
      if (!await _cleanupConfigTransactionRootBestEffort(root)) {
        throw StateError('Failed to discard configuration transaction');
      }
    }
    if (await transactionsRoot.exists() &&
        await transactionsRoot.list(followLinks: false).isEmpty) {
      await transactionsRoot.delete();
    }
  }

  Future<void> _injectDavPassword(
    SharedPreferences? sharedPreferences,
    Map<String, Object?> configMap,
  ) async {
    final davProps = configMap['davProps'];
    if (davProps is! Map) return;
    final davMap = Map<String, Object?>.from(davProps);
    final legacyPassword = davMap['password'];
    String? password;
    if (legacyPassword is String && legacyPassword.isNotEmpty) {
      try {
        await _credentialStorage.write(_davPasswordKey, legacyPassword);
        davMap.remove('password');
        configMap['davProps'] = davMap;
        if (sharedPreferences != null &&
            !await _writePreference(
              sharedPreferences,
              configKey,
              json.encode(configMap),
            )) {
          throw StateError('Failed to migrate application preferences');
        }
        password = legacyPassword;
      } catch (_) {
        password = legacyPassword;
      }
    } else {
      try {
        password = await _credentialStorage.read(_davPasswordKey);
      } catch (_) {
        password = null;
      }
    }
    davMap['password'] = password ?? '';
    configMap['davProps'] = davMap;
  }
}

final preferences = Preferences();

Future<String> _defaultConfigTransactionDirectory() async {
  final directory = await getApplicationSupportDirectory();
  return p.join(directory.path, _configTransactionsDirectoryName);
}

String _newConfigTransactionId() {
  final random = Random.secure();
  return List<int>.generate(
    16,
    (_) => random.nextInt(256),
    growable: false,
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

Iterable<String> _configTransactionCredentialKeys(Directory root) sync* {
  final match = RegExp(
    r'^pending-([0-9a-f]{32})$',
  ).firstMatch(p.basename(root.path));
  final transactionId = match?.group(1);
  if (transactionId == null) return;
  yield '${_davPasswordKey}_config_${transactionId}_old';
  yield '${_davPasswordKey}_config_${transactionId}_new';
}

({String? config, String? legacyPassword}) _sanitizeConfigForJournal(
  String? value,
) {
  if (value == null) return (config: null, legacyPassword: null);
  final decoded = jsonDecode(value);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid persisted application configuration');
  }
  final davProps = decoded['davProps'];
  if (davProps is! Map) return (config: value, legacyPassword: null);
  final sanitizedDav = Map<String, Object?>.from(davProps);
  final password = sanitizedDav.remove('password');
  decoded['davProps'] = sanitizedDav;
  return (
    config: jsonEncode(decoded),
    legacyPassword: password is String && password.isNotEmpty ? password : null,
  );
}

Future<void> _writeConfigTransactionMarker(Directory root, String name) async {
  final marker = File(p.join(root.path, name));
  if (await marker.exists()) return;
  await _writeNewConfigTransactionFile(marker, '');
}

Future<void> _writeNewConfigTransactionFile(File target, String content) async {
  await target.parent.create(recursive: true);
  final temporary = File('${target.path}.tmp-${_newConfigTransactionId()}');
  try {
    await temporary.writeAsString(content, flush: true);
    await temporary.rename(target.path);
  } finally {
    try {
      if (await temporary.exists()) await temporary.delete();
    } catch (_) {}
  }
}

class _ConfigTransaction {
  const _ConfigTransaction({
    required this.root,
    required this.transactionId,
    required this.oldConfig,
    required this.newConfig,
    required this.hasOldPassword,
    required this.hasNewPassword,
  });

  factory _ConfigTransaction.fromJson(Directory root, Object? raw) {
    if (raw is! Map<String, dynamic> || raw['version'] != 1) {
      throw const FormatException('Invalid configuration transaction');
    }
    final transactionId = raw['transactionId'];
    final oldConfig = raw['oldConfig'];
    final newConfig = raw['newConfig'];
    final hasOldPassword = raw['hasOldPassword'];
    final hasNewPassword = raw['hasNewPassword'];
    if (transactionId is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(transactionId) ||
        (oldConfig != null && oldConfig is! String) ||
        newConfig is! String ||
        hasOldPassword is! bool ||
        hasNewPassword is! bool ||
        p.basename(root.path) != 'pending-$transactionId') {
      throw const FormatException('Invalid configuration transaction');
    }
    _validateJournalConfig(oldConfig as String?);
    _validateJournalConfig(newConfig);
    return _ConfigTransaction(
      root: root,
      transactionId: transactionId,
      oldConfig: oldConfig,
      newConfig: newConfig,
      hasOldPassword: hasOldPassword,
      hasNewPassword: hasNewPassword,
    );
  }

  final Directory root;
  final String transactionId;
  final String? oldConfig;
  final String newConfig;
  final bool hasOldPassword;
  final bool hasNewPassword;

  String get oldCredentialKey =>
      '${_davPasswordKey}_config_${transactionId}_old';
  String get newCredentialKey =>
      '${_davPasswordKey}_config_${transactionId}_new';

  Map<String, Object?> toJson() => {
    'version': 1,
    'transactionId': transactionId,
    'oldConfig': oldConfig,
    'newConfig': newConfig,
    'hasOldPassword': hasOldPassword,
    'hasNewPassword': hasNewPassword,
  };
}

void _validateJournalConfig(String? value) {
  if (value == null) return;
  final decoded = jsonDecode(value);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid configuration transaction config');
  }
  final davProps = decoded['davProps'];
  if (davProps is Map && davProps.containsKey('password')) {
    throw const FormatException('Configuration transaction contains a secret');
  }
}
