import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/models/models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import 'constant.dart';

const _davPasswordKey = 'webdav_password';
const _restorePreferencesSnapshotName = 'preferences-before-restore.json';
const _restorePreferencesRolledBackName = 'preferences-rolled-back';

typedef ConfigPreferenceWriter = Future<bool> Function(String value);
typedef ConfigPreferenceRemover = Future<bool> Function();
typedef PreferenceWriter = Future<bool> Function(String key, Object value);
typedef PreferenceRemover = Future<bool> Function(String key);
typedef PreferencesClearer = Future<bool> Function();

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
  Future<void> _configOperationTail = Future<void>.value();

  Future<bool> get isInit async =>
      await sharedPreferencesCompleter.future != null;

  Preferences._internal()
    : _credentialStorage = const PlatformCredentialStorage(),
      _configWriter = null,
      _configRemover = null,
      _preferenceWriter = null,
      _preferenceRemover = null,
      _preferencesClearer = null {
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
  }) : _credentialStorage = credentialStorage,
       _configWriter = configWriter,
       _configRemover = configRemover,
       _preferenceWriter = preferenceWriter,
       _preferenceRemover = preferenceRemover,
       _preferencesClearer = preferencesClearer {
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
    try {
      final preferences = await sharedPreferencesCompleter.future;
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
