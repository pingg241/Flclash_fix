import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryCredentialStorage implements CredentialStorage {
  final values = <String, String>{};
  bool failWrites = false;
  bool failDeletes = false;

  @override
  Future<void> delete(String key) async {
    if (failDeletes) {
      throw StateError('secure storage delete failed');
    }
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) {
      throw StateError('secure storage write failed');
    }
    values[key] = value;
  }
}

Config _config(String generation) {
  return Config(
    themeProps: defaultThemeProps,
    davProps: DAVProps(
      uri: 'https://$generation.example.com',
      user: generation,
      password: '$generation-secret',
    ),
  );
}

const _sharedState = SharedState(
  stopTip: 'stop tip',
  startTip: 'start tip',
  currentProfileName: 'profile',
  stopText: 'stop',
  onlyStatisticsProxy: false,
  crashlytics: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves WebDAV password only in credential storage', () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final storage = MemoryCredentialStorage();
    final preferences = Preferences.test(sharedPreferences, storage);
    const config = Config(
      themeProps: defaultThemeProps,
      davProps: DAVProps(
        uri: 'https://dav.example.com',
        user: 'alice',
        password: 'secret-value',
      ),
    );

    expect(await preferences.saveConfig(config), isTrue);

    final persisted =
        jsonDecode(sharedPreferences.getString(configKey)!)
            as Map<String, dynamic>;
    expect(persisted['davProps'], isNot(contains('password')));
    expect(storage.values.values, ['secret-value']);
    expect((await preferences.getConfig())?.davProps?.password, 'secret-value');
  });

  test('migrates a legacy plaintext password after a secure write', () async {
    SharedPreferences.setMockInitialValues({
      configKey: jsonEncode({
        'davProps': {
          'uri': 'https://dav.example.com',
          'user': 'alice',
          'password': 'legacy-secret',
        },
      }),
    });
    final sharedPreferences = await SharedPreferences.getInstance();
    final storage = MemoryCredentialStorage();
    final preferences = Preferences.test(sharedPreferences, storage);

    final configMap = await preferences.getConfigMap();

    expect((configMap?['davProps'] as Map)['password'], 'legacy-secret');
    expect(storage.values.values, ['legacy-secret']);
    final persisted =
        jsonDecode(sharedPreferences.getString(configKey)!)
            as Map<String, dynamic>;
    expect(persisted['davProps'], isNot(contains('password')));
  });

  test(
    'secure storage failure leaves persisted config and secret unchanged',
    () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      final storage = MemoryCredentialStorage()
        ..values['webdav_password'] = 'old-secret';
      final preferences = Preferences.test(sharedPreferences, storage);
      const oldConfig = Config(
        themeProps: defaultThemeProps,
        davProps: DAVProps(
          uri: 'https://old.example.com',
          user: 'old',
          password: 'old-secret',
        ),
      );
      expect(await preferences.saveConfig(oldConfig), isTrue);
      final oldPersisted = sharedPreferences.getString(configKey);
      storage.failWrites = true;

      await expectLater(
        preferences.saveConfig(
          const Config(
            themeProps: defaultThemeProps,
            davProps: DAVProps(
              uri: 'https://new.example.com',
              user: 'new',
              password: 'new-secret',
            ),
          ),
        ),
        throwsA(isA<PreferencesCompensationException>()),
      );

      expect(sharedPreferences.getString(configKey), oldPersisted);
      expect(storage.values['webdav_password'], 'old-secret');
    },
  );

  test('config write failure compensates config and secure storage', () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final storage = MemoryCredentialStorage();
    final initialPreferences = Preferences.test(sharedPreferences, storage);
    const oldConfig = Config(
      themeProps: defaultThemeProps,
      davProps: DAVProps(
        uri: 'https://old.example.com',
        user: 'old',
        password: 'old-secret',
      ),
    );
    expect(await initialPreferences.saveConfig(oldConfig), isTrue);
    final oldPersisted = sharedPreferences.getString(configKey);
    var writeCount = 0;
    final preferences = Preferences.test(
      sharedPreferences,
      storage,
      configWriter: (value) async {
        writeCount++;
        if (writeCount == 1) {
          throw StateError('preferences write failed');
        }
        return sharedPreferences.setString(configKey, value);
      },
    );

    await expectLater(
      preferences.saveConfig(
        const Config(
          themeProps: defaultThemeProps,
          davProps: DAVProps(
            uri: 'https://new.example.com',
            user: 'new',
            password: 'new-secret',
          ),
        ),
      ),
      throwsStateError,
    );

    expect(sharedPreferences.getString(configKey), oldPersisted);
    expect(storage.values['webdav_password'], 'old-secret');
    expect(writeCount, 2);
  });

  test('clearing a password propagates secure delete failure', () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final storage = MemoryCredentialStorage()
      ..values['webdav_password'] = 'old-secret';
    final preferences = Preferences.test(sharedPreferences, storage);
    const oldConfig = Config(
      themeProps: defaultThemeProps,
      davProps: DAVProps(uri: '', user: '', password: 'old-secret'),
    );
    expect(await preferences.saveConfig(oldConfig), isTrue);
    final oldPersisted = sharedPreferences.getString(configKey);
    storage.failDeletes = true;

    await expectLater(
      preferences.saveConfig(
        const Config(
          themeProps: defaultThemeProps,
          davProps: DAVProps(uri: '', user: '', password: ''),
        ),
      ),
      throwsStateError,
    );

    expect(sharedPreferences.getString(configKey), oldPersisted);
    expect(storage.values['webdav_password'], 'old-secret');
  });

  test(
    'restore snapshot uses a secure reference and restores old state',
    () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      final storage = MemoryCredentialStorage()
        ..values['webdav_password'] = 'old-secret';
      final preferences = Preferences.test(sharedPreferences, storage);
      await sharedPreferences.setString(configKey, '{"old":true}');
      final root = await Directory.systemTemp.createTemp(
        'flclash-preferences-restore-',
      );
      addTearDown(() => root.delete(recursive: true));

      await preferences.createRestoreSnapshot(root.path);
      await sharedPreferences.setString(configKey, '{"new":true}');
      storage.values['webdav_password'] = 'new-secret';
      final snapshot = await File(
        '${root.path}/preferences-before-restore.json',
      ).readAsString();
      expect(snapshot, isNot(contains('old-secret')));

      await preferences.rollbackRestoreSnapshot(root.path);

      expect(sharedPreferences.getString(configKey), '{"old":true}');
      expect(storage.values['webdav_password'], 'old-secret');
      await preferences.finalizeRestoreSnapshot(root.path);
      expect(
        storage.values.keys.where((key) => key.contains('_restore_')),
        isEmpty,
      );
      await preferences.rollbackRestoreSnapshot(root.path);
      expect(storage.values['webdav_password'], 'old-secret');
    },
  );

  test('snapshot waits for a concurrent config save generation', () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final storage = MemoryCredentialStorage();
    final initialPreferences = Preferences.test(sharedPreferences, storage);
    expect(await initialPreferences.saveConfig(_config('old')), isTrue);
    final writeStarted = Completer<void>();
    final releaseWrite = Completer<void>();
    final preferences = Preferences.test(
      sharedPreferences,
      storage,
      configWriter: (value) async {
        writeStarted.complete();
        await releaseWrite.future;
        return sharedPreferences.setString(configKey, value);
      },
    );
    final root = await Directory.systemTemp.createTemp(
      'flclash-preferences-snapshot-queue-',
    );
    addTearDown(() => root.delete(recursive: true));

    final save = preferences.saveConfig(_config('new'));
    await writeStarted.future;
    final snapshot = preferences.createRestoreSnapshot(root.path);
    await Future<void>.delayed(Duration.zero);
    expect(
      await File('${root.path}/preferences-before-restore.json').exists(),
      isFalse,
    );
    releaseWrite.complete();
    await Future.wait([save, snapshot]);

    await sharedPreferences.setString(configKey, '{}');
    storage.values['webdav_password'] = 'later-secret';
    await preferences.rollbackRestoreSnapshot(root.path);
    final restored = await preferences.getConfig();
    expect(restored?.davProps?.user, 'new');
    expect(restored?.davProps?.password, 'new-secret');
  });

  test('rollback waits for a concurrent config save', () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final storage = MemoryCredentialStorage();
    final initialPreferences = Preferences.test(sharedPreferences, storage);
    expect(await initialPreferences.saveConfig(_config('old')), isTrue);
    final root = await Directory.systemTemp.createTemp(
      'flclash-preferences-rollback-queue-',
    );
    addTearDown(() => root.delete(recursive: true));
    await initialPreferences.createRestoreSnapshot(root.path);
    final writeStarted = Completer<void>();
    final releaseWrite = Completer<void>();
    final preferences = Preferences.test(
      sharedPreferences,
      storage,
      configWriter: (value) async {
        writeStarted.complete();
        await releaseWrite.future;
        return sharedPreferences.setString(configKey, value);
      },
    );

    final save = preferences.saveConfig(_config('new'));
    await writeStarted.future;
    final rollback = preferences.rollbackRestoreSnapshot(root.path);
    releaseWrite.complete();
    await Future.wait([save, rollback]);

    final restored = await preferences.getConfig();
    expect(restored?.davProps?.user, 'old');
    expect(restored?.davProps?.password, 'old-secret');
  });

  test('clear waits for a concurrent config save', () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final storage = MemoryCredentialStorage();
    final initialPreferences = Preferences.test(sharedPreferences, storage);
    expect(await initialPreferences.saveConfig(_config('old')), isTrue);
    final writeStarted = Completer<void>();
    final releaseWrite = Completer<void>();
    final preferences = Preferences.test(
      sharedPreferences,
      storage,
      configWriter: (value) async {
        writeStarted.complete();
        await releaseWrite.future;
        return sharedPreferences.setString(configKey, value);
      },
    );

    final save = preferences.saveConfig(_config('new'));
    await writeStarted.future;
    final clear = preferences.clearPreferences();
    releaseWrite.complete();
    await Future.wait([save, clear]);

    expect(sharedPreferences.getString(configKey), isNull);
    expect(storage.values['webdav_password'], isNull);
  });

  test('clear waits for a concurrent version write', () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final writeStarted = Completer<void>();
    final releaseWrite = Completer<void>();
    var clearCalled = false;
    final preferences = Preferences.test(
      sharedPreferences,
      MemoryCredentialStorage(),
      preferenceWriter: (key, value) async {
        if (key == 'version') {
          writeStarted.complete();
          await releaseWrite.future;
        }
        return sharedPreferences.setInt(key, value as int);
      },
      preferencesClearer: () async {
        clearCalled = true;
        return sharedPreferences.clear();
      },
    );

    final write = preferences.setVersion(7);
    await writeStarted.future;
    final clear = preferences.clearPreferences();
    await Future<void>.delayed(Duration.zero);
    expect(clearCalled, isFalse);
    releaseWrite.complete();
    await Future.wait([write, clear]);

    expect(sharedPreferences.getInt('version'), isNull);
  });

  test('clear waits for a concurrent shared state write', () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final writeStarted = Completer<void>();
    final releaseWrite = Completer<void>();
    var clearCalled = false;
    final preferences = Preferences.test(
      sharedPreferences,
      MemoryCredentialStorage(),
      preferenceWriter: (key, value) async {
        if (key == 'sharedState') {
          writeStarted.complete();
          await releaseWrite.future;
        }
        return sharedPreferences.setString(key, value as String);
      },
      preferencesClearer: () async {
        clearCalled = true;
        return sharedPreferences.clear();
      },
    );

    final write = preferences.saveShareState(_sharedState);
    await writeStarted.future;
    final clear = preferences.clearPreferences();
    await Future<void>.delayed(Duration.zero);
    expect(clearCalled, isFalse);
    releaseWrite.complete();
    await Future.wait([write, clear]);

    expect(sharedPreferences.getString('sharedState'), isNull);
  });

  test('legacy Clash config clear serializes with config save', () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    await sharedPreferences.setString(clashConfigKey, '{"legacy":true}');
    final storage = MemoryCredentialStorage();
    final removeStarted = Completer<void>();
    final releaseRemove = Completer<void>();
    final preferences = Preferences.test(
      sharedPreferences,
      storage,
      preferenceRemover: (key) async {
        if (key == clashConfigKey) {
          removeStarted.complete();
          await releaseRemove.future;
        }
        return sharedPreferences.remove(key);
      },
    );

    final clearClash = preferences.clearClashConfig();
    await removeStarted.future;
    final save = preferences.saveConfig(_config('new'));
    await Future<void>.delayed(Duration.zero);
    expect(storage.values['webdav_password'], isNull);
    releaseRemove.complete();
    await Future.wait([clearClash, save]);

    expect(await preferences.getClashConfigMap(), isNull);
    expect((await preferences.getConfig())?.davProps?.user, 'new');
  });

  test('clear failure is reported after credential cleanup', () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final storage = MemoryCredentialStorage()
      ..values['webdav_password'] = 'secret';
    final preferences = Preferences.test(
      sharedPreferences,
      storage,
      preferencesClearer: () async => false,
    );

    await expectLater(preferences.clearPreferences(), throwsStateError);

    expect(storage.values['webdav_password'], isNull);
  });
}
