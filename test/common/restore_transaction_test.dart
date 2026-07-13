import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory home;
  late Directory restore;
  late File databaseFile;

  Profile profile(int id) {
    return Profile(id: id, autoUpdateDuration: const Duration(hours: 1));
  }

  Future<void> writeFixture({int profileCount = 2}) async {
    home = Directory(p.join(root.path, 'home'));
    restore = Directory(p.join(root.path, 'restore'));
    await home.create(recursive: true);
    await restore.create(recursive: true);
    for (var id = 1; id <= profileCount; id++) {
      final relative = p.join('profiles', '$id.yaml');
      await File(
        p.join(home.path, relative),
      ).create(recursive: true).then((file) => file.writeAsString('old-$id'));
      await File(
        p.join(restore.path, relative),
      ).create(recursive: true).then((file) => file.writeAsString('new-$id'));
    }
    databaseFile = File(p.join(home.path, 'database.sqlite'));
    await databaseFile.writeAsString('old-database');
  }

  Future<void> snapshotDatabase(String targetPath) async {
    await databaseFile.copy(targetPath);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'flclash-restore-transaction-',
    );
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'startup recovery rolls back a process interrupted during install',
    () async {
      await writeFixture(profileCount: 1);

      await expectLater(
        applyRestoreFilesAtomically(
          MigrationData(profiles: [profile(1)]),
          () async => databaseFile.writeAsString('new-database'),
          createDatabaseSnapshot: snapshotDatabase,
          restoreRootPath: restore.path,
          homeRootPath: home.path,
          databasePath: databaseFile.path,
          faultInjector: (checkpoint, _) {
            if (checkpoint == RestoreTransactionCheckpoint.fileInstalled) {
              throw const RestoreTransactionInterruption();
            }
          },
        ),
        throwsA(isA<RestoreTransactionInterruption>()),
      );
      expect(
        await File(p.join(home.path, 'profiles', '1.yaml')).readAsString(),
        'new-1',
      );

      await recoverPendingRestoreTransactions(
        homeRootPath: home.path,
        databasePath: databaseFile.path,
      );

      expect(
        await File(p.join(home.path, 'profiles', '1.yaml')).readAsString(),
        'old-1',
      );
      expect(await databaseFile.readAsString(), 'old-database');
    },
  );

  test(
    'startup recovery rolls back files and database after DB commit window',
    () async {
      await writeFixture();

      await expectLater(
        applyRestoreFilesAtomically(
          MigrationData(profiles: [profile(1), profile(2)]),
          () async {
            await databaseFile.writeAsString('new-database', flush: true);
          },
          createDatabaseSnapshot: snapshotDatabase,
          restoreRootPath: restore.path,
          homeRootPath: home.path,
          databasePath: databaseFile.path,
          faultInjector: (checkpoint, _) {
            if (checkpoint == RestoreTransactionCheckpoint.databaseApplied) {
              throw const RestoreTransactionInterruption();
            }
          },
        ),
        throwsA(isA<RestoreTransactionInterruption>()),
      );
      expect(await databaseFile.readAsString(), 'new-database');

      await recoverPendingRestoreTransactions(
        homeRootPath: home.path,
        databasePath: databaseFile.path,
      );

      expect(await databaseFile.readAsString(), 'old-database');
      expect(
        await File(p.join(home.path, 'profiles', '1.yaml')).readAsString(),
        'old-1',
      );
      expect(
        await File(p.join(home.path, 'profiles', '2.yaml')).readAsString(),
        'old-2',
      );
    },
  );

  test(
    'committed marker keeps new state after an interrupted cleanup',
    () async {
      await writeFixture(profileCount: 1);

      await expectLater(
        applyRestoreFilesAtomically(
          MigrationData(profiles: [profile(1)]),
          () async => databaseFile.writeAsString('new-database', flush: true),
          createDatabaseSnapshot: snapshotDatabase,
          restoreRootPath: restore.path,
          homeRootPath: home.path,
          databasePath: databaseFile.path,
          faultInjector: (checkpoint, _) {
            if (checkpoint == RestoreTransactionCheckpoint.committed) {
              throw const RestoreTransactionInterruption();
            }
          },
        ),
        throwsA(isA<RestoreTransactionInterruption>()),
      );

      await recoverPendingRestoreTransactions(
        homeRootPath: home.path,
        databasePath: databaseFile.path,
      );

      expect(await databaseFile.readAsString(), 'new-database');
      expect(
        await File(p.join(home.path, 'profiles', '1.yaml')).readAsString(),
        'new-1',
      );
    },
  );

  test(
    'committed cleanup failure is deferred without reporting false failure',
    () async {
      await writeFixture(profileCount: 1);
      var failedCleanup = false;

      final result = await applyRestoreFilesAtomically(
        MigrationData(profiles: [profile(1)]),
        () async {
          await databaseFile.writeAsString('new-database', flush: true);
          return 'restored';
        },
        createDatabaseSnapshot: snapshotDatabase,
        restoreRootPath: restore.path,
        homeRootPath: home.path,
        databasePath: databaseFile.path,
        mutationGuard: (mutation, path) {
          if (!failedCleanup &&
              mutation == RestoreTransactionMutation.deleteArtifact &&
              p.basename(path) == '0' &&
              p.basename(p.dirname(path)) == 'previous') {
            failedCleanup = true;
            throw FileSystemException('file is locked', path);
          }
        },
      );

      expect(result, 'restored');
      expect(failedCleanup, isTrue);
      expect(await databaseFile.readAsString(), 'new-database');
      await recoverPendingRestoreTransactions(
        homeRootPath: home.path,
        databasePath: databaseFile.path,
      );
      expect(
        await File(p.join(home.path, 'profiles', '1.yaml')).readAsString(),
        'new-1',
      );
    },
  );

  test(
    'a locked previous file does not stop remaining rollback work',
    () async {
      await writeFixture();
      await expectLater(
        applyRestoreFilesAtomically(
          MigrationData(profiles: [profile(1), profile(2)]),
          () async => databaseFile.writeAsString('new-database', flush: true),
          createDatabaseSnapshot: snapshotDatabase,
          restoreRootPath: restore.path,
          homeRootPath: home.path,
          databasePath: databaseFile.path,
          faultInjector: (checkpoint, _) {
            if (checkpoint == RestoreTransactionCheckpoint.databaseApplied) {
              throw const RestoreTransactionInterruption();
            }
          },
        ),
        throwsA(isA<RestoreTransactionInterruption>()),
      );

      await expectLater(
        recoverPendingRestoreTransactions(
          homeRootPath: home.path,
          databasePath: databaseFile.path,
          mutationGuard: (mutation, path) {
            if (mutation == RestoreTransactionMutation.restorePrevious &&
                p.basename(path) == '1') {
              throw FileSystemException('file is locked', path);
            }
          },
        ),
        throwsA(isA<RestoreRecoveryException>()),
      );

      expect(
        await File(p.join(home.path, 'profiles', '1.yaml')).readAsString(),
        'old-1',
      );
      expect(await databaseFile.readAsString(), 'old-database');
      await recoverPendingRestoreTransactions(
        homeRootPath: home.path,
        databasePath: databaseFile.path,
      );
      expect(
        await File(p.join(home.path, 'profiles', '2.yaml')).readAsString(),
        'old-2',
      );
    },
  );

  test('external persistence failure compensates database and files', () async {
    await writeFixture(profileCount: 1);
    var externalState = 'old-external';

    await expectLater(
      applyRestoreFilesAtomically(
        MigrationData(profiles: [profile(1)]),
        () async => databaseFile.writeAsString('new-database', flush: true),
        createDatabaseSnapshot: snapshotDatabase,
        restoreRootPath: restore.path,
        homeRootPath: home.path,
        databasePath: databaseFile.path,
        createExternalStateSnapshot: (transactionRoot) => File(
          p.join(transactionRoot, 'external.snapshot'),
        ).writeAsString(externalState, flush: true),
        applyExternalState: () async {
          externalState = 'new-external';
          throw StateError('preferences write failed');
        },
        rollbackDatabase: () =>
            databaseFile.writeAsString('old-database', flush: true),
        rollbackExternalState: (transactionRoot) async {
          externalState = await File(
            p.join(transactionRoot, 'external.snapshot'),
          ).readAsString();
        },
      ),
      throwsStateError,
    );

    expect(await databaseFile.readAsString(), 'old-database');
    expect(externalState, 'old-external');
    expect(
      await File(p.join(home.path, 'profiles', '1.yaml')).readAsString(),
      'old-1',
    );
  });

  test(
    'startup recovery rolls back external state after persistence crash',
    () async {
      await writeFixture(profileCount: 1);
      var externalState = 'old-external';

      await expectLater(
        applyRestoreFilesAtomically(
          MigrationData(profiles: [profile(1)]),
          () async => databaseFile.writeAsString('new-database', flush: true),
          createDatabaseSnapshot: snapshotDatabase,
          restoreRootPath: restore.path,
          homeRootPath: home.path,
          databasePath: databaseFile.path,
          createExternalStateSnapshot: (transactionRoot) => File(
            p.join(transactionRoot, 'external.snapshot'),
          ).writeAsString(externalState, flush: true),
          applyExternalState: () async {
            externalState = 'new-external';
          },
          rollbackExternalState: (transactionRoot) async {
            externalState = await File(
              p.join(transactionRoot, 'external.snapshot'),
            ).readAsString();
          },
          faultInjector: (checkpoint, _) {
            if (checkpoint ==
                RestoreTransactionCheckpoint.externalStateApplied) {
              throw const RestoreTransactionInterruption();
            }
          },
        ),
        throwsA(isA<RestoreTransactionInterruption>()),
      );
      expect(externalState, 'new-external');

      await recoverPendingRestoreTransactions(
        homeRootPath: home.path,
        databasePath: databaseFile.path,
        rollbackExternalState: (transactionRoot) async {
          externalState = await File(
            p.join(transactionRoot, 'external.snapshot'),
          ).readAsString();
        },
      );

      expect(await databaseFile.readAsString(), 'old-database');
      expect(externalState, 'old-external');
      expect(
        await File(p.join(home.path, 'profiles', '1.yaml')).readAsString(),
        'old-1',
      );
    },
  );
}
