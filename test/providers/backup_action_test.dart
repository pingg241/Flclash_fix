import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  Map<String, Object?> configMap(Config config) {
    return jsonDecode(jsonEncode(config.toJson())) as Map<String, Object?>;
  }

  group('backup snapshot lifetime', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'flclash-backup-action-test-',
      );
    });

    tearDown(() => directory.safeDelete(recursive: true));

    test('keeps the snapshot until a successful backup completes', () async {
      final snapshot = File(path.join(directory.path, 'database.snapshot'));
      final backupStarted = Completer<void>();
      final releaseBackup = Completer<void>();

      final backup = runBackupWithSnapshot(
        snapshot: snapshot,
        createSnapshot: (snapshotPath) async {
          await File(snapshotPath).writeAsString('database');
        },
        createBackup: (snapshotPath) async {
          expect(await File(snapshotPath).readAsString(), 'database');
          backupStarted.complete();
          await releaseBackup.future;
          expect(await File(snapshotPath).exists(), isTrue);
          return 'archive.zip';
        },
      );

      await backupStarted.future;
      expect(await snapshot.exists(), isTrue);
      releaseBackup.complete();

      expect(await backup, 'archive.zip');
      expect(await snapshot.exists(), isFalse);
    });

    test('cleans the snapshot after the backup task fails', () async {
      final snapshot = File(path.join(directory.path, 'database.snapshot'));
      final backupStarted = Completer<void>();
      final releaseBackup = Completer<void>();

      final backup = runBackupWithSnapshot(
        snapshot: snapshot,
        createSnapshot: (snapshotPath) async {
          await File(snapshotPath).writeAsString('database');
        },
        createBackup: (snapshotPath) async {
          expect(await File(snapshotPath).exists(), isTrue);
          backupStarted.complete();
          await releaseBackup.future;
          throw StateError('backup failed');
        },
      );
      final expectation = expectLater(backup, throwsStateError);

      await backupStarted.future;
      expect(await snapshot.exists(), isTrue);
      releaseBackup.complete();

      await expectation;
      expect(await snapshot.exists(), isFalse);
    });
  });

  test('rejects an unsupported config version before restore', () {
    final data = configMap(const Config(themeProps: defaultThemeProps));
    data['version'] = migration.currentVersion + 1;

    expect(
      () => validateBackupConfig(
        data,
        const Config(themeProps: defaultThemeProps),
      ),
      throwsFormatException,
    );
  });

  test('rejects malformed and plaintext credential configuration', () {
    final malformed = configMap(const Config(themeProps: defaultThemeProps))
      ..addAll({'version': migration.currentVersion, 'davProps': 'invalid'});
    final plaintext = configMap(const Config(themeProps: defaultThemeProps))
      ..addAll({
        'version': migration.currentVersion,
        'davProps': {
          'uri': 'https://dav.example.com',
          'user': 'alice',
          'password': 'plaintext',
        },
      });

    expect(
      () => validateBackupConfig(
        malformed,
        const Config(themeProps: defaultThemeProps),
      ),
      throwsFormatException,
    );
    expect(
      () => validateBackupConfig(
        plaintext,
        const Config(themeProps: defaultThemeProps),
      ),
      throwsFormatException,
    );
  });

  test('reuses only a matching local credential reference', () {
    final restoredMap = configMap(
      const Config(
        themeProps: defaultThemeProps,
        davProps: DAVProps(
          uri: 'https://dav.example.com',
          user: 'alice',
          password: '',
        ),
      ),
    )..['version'] = migration.currentVersion;
    const current = Config(
      themeProps: defaultThemeProps,
      davProps: DAVProps(
        uri: 'https://dav.example.com',
        user: 'alice',
        password: 'local-secret',
      ),
    );

    final restored = validateBackupConfig(restoredMap, current);

    expect(restored.davProps?.password, 'local-secret');
  });

  test('restored profile selection keeps a valid preferred id', () {
    final first = Profile.normal(label: 'first');
    final second = Profile.normal(label: 'second');

    expect(selectRestoredProfileId(second.id, [first, second]), second.id);
  });

  test('restored profile selection replaces a dangling id', () {
    final profile = Profile.normal(label: 'restored');

    expect(selectRestoredProfileId(profile.id + 1, [profile]), profile.id);
    expect(selectRestoredProfileId(profile.id + 1, const []), isNull);
  });
}
