import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory home;
  late Directory profiles;
  late Directory scripts;
  late File database;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('flclash-clear-recovery-');
    profiles = Directory(p.join(home.path, 'profiles'));
    scripts = Directory(p.join(home.path, 'scripts'));
    database = File(p.join(home.path, 'database.sqlite'));
    await profiles.create();
    await scripts.create();
    await File(p.join(profiles.path, '1.yaml')).writeAsString('profile');
    await File(p.join(scripts.path, '2.js')).writeAsString('script');
    await database.writeAsString('old-database');
  });

  tearDown(() => home.safeDelete(recursive: true));

  Future<ClearFileTransaction> stage(String name) {
    return stageClearFilesAtomically(
      directoryPaths: [profiles.path, scripts.path],
      transactionRootPath: p.join(
        home.path,
        clearTransactionsDirectoryName,
        name,
      ),
    );
  }

  Future<void> recover({
    Future<void> Function(String path)? rollback,
    Future<void> Function(String path)? finalize,
  }) {
    return recoverPendingClearTransactions(
      homeRootPath: home.path,
      databasePath: database.path,
      rollbackExternalState: rollback ?? (_) async {},
      finalizeExternalState: finalize ?? (_) async {},
    );
  }

  test('restart after staging restores profiles and scripts', () async {
    await stage('pending-stage');

    await recover();

    expect(
      await File(p.join(profiles.path, '1.yaml')).readAsString(),
      'profile',
    );
    expect(await File(p.join(scripts.path, '2.js')).readAsString(), 'script');
    expect(await database.readAsString(), 'old-database');
  });

  test('restart after preferences clear rolls external state back', () async {
    final transaction = await stage('pending-preferences');
    await File(transaction.databaseSnapshotPath).writeAsString('old-database');
    var rolledBack = false;

    await recover(rollback: (_) async => rolledBack = true);

    expect(rolledBack, isTrue);
    expect(await profiles.exists(), isTrue);
    expect(await scripts.exists(), isTrue);
  });

  test(
    'restart after database clear but before marker restores snapshot',
    () async {
      final transaction = await stage('pending-database');
      await File(
        transaction.databaseSnapshotPath,
      ).writeAsString('old-database');
      await database.writeAsString('cleared-database');

      await recover();

      expect(await database.readAsString(), 'old-database');
      expect(await profiles.exists(), isTrue);
      expect(await scripts.exists(), isTrue);
    },
  );

  test('committed restart keeps clear state and only cleans journal', () async {
    final transaction = await stage('pending-committed');
    await File(transaction.databaseSnapshotPath).writeAsString('old-database');
    await database.writeAsString('cleared-database');
    await transaction.markCommitted();
    var finalized = false;

    await recover(finalize: (_) async => finalized = true);

    expect(finalized, isTrue);
    expect(await database.readAsString(), 'cleared-database');
    expect(await profiles.exists(), isFalse);
    expect(await scripts.exists(), isFalse);
    expect(await transaction.root.exists(), isFalse);
  });

  test('cleanup failure remains recoverable on the next restart', () async {
    final transaction = await stage('pending-cleanup');
    await transaction.markCommitted();

    await expectLater(
      recover(finalize: (_) async => throw StateError('cleanup failed')),
      throwsA(isA<ClearRecoveryException>()),
    );
    expect(await transaction.root.exists(), isTrue);

    await recover();
    expect(await transaction.root.exists(), isFalse);
    expect(await profiles.exists(), isFalse);
    expect(await scripts.exists(), isFalse);
  });
}
