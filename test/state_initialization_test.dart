import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'GlobalState loads config only after shared clear and restore recovery',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'flclash-state-recovery-',
      );
      addTearDown(() => root.safeDelete(recursive: true));
      final home = Directory(p.join(root.path, 'home'));
      final restore = Directory(p.join(root.path, 'restore'));
      await home.create(recursive: true);
      await restore.create(recursive: true);
      final database = File(p.join(home.path, 'database.sqlite'));
      await database.writeAsString('old-database');
      final restoredProfile = File(p.join(restore.path, 'profiles', '1.yaml'));
      await restoredProfile.create(recursive: true);
      await restoredProfile.writeAsString('new-profile');
      final currentProfile = File(p.join(home.path, 'profiles', '1.yaml'));
      await currentProfile.create(recursive: true);
      await currentProfile.writeAsString('old-profile');
      var persistedConfig = 'old-config';

      await expectLater(
        applyRestoreFilesAtomically(
          const MigrationData(
            profiles: [Profile(id: 1, autoUpdateDuration: Duration(hours: 1))],
          ),
          () => database.writeAsString('new-database', flush: true),
          createDatabaseSnapshot: database.copy,
          restoreRootPath: restore.path,
          homeRootPath: home.path,
          databasePath: database.path,
          createExternalStateSnapshot: (transactionRoot) => File(
            p.join(transactionRoot, 'external.snapshot'),
          ).writeAsString(persistedConfig, flush: true),
          applyExternalState: () async {
            persistedConfig = 'new-config';
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
      expect(persistedConfig, 'new-config');
      expect(await database.readAsString(), 'new-database');

      final phases = <String>[];
      final coordinator = StorageRecoveryCoordinator(
        recoverClearTransactions: () async {
          phases.add('clear');
        },
        recoverRestoreTransactions: () async {
          phases.add('restore');
          await recoverPendingRestoreTransactions(
            homeRootPath: home.path,
            databasePath: database.path,
            rollbackExternalState: (transactionRoot) async {
              persistedConfig = await File(
                p.join(transactionRoot, 'external.snapshot'),
              ).readAsString();
            },
          );
        },
      );

      final loadedState = loadAfterStorageRecovery(
        recover: coordinator.recover,
        load: () async =>
            (config: persistedConfig, database: await database.readAsString()),
      );
      await Future.wait([coordinator.recover(), coordinator.recover()]);
      final loaded = await loadedState;

      expect(phases, ['clear', 'restore']);
      expect(loaded.config, 'old-config');
      expect(loaded.database, 'old-database');
      expect(persistedConfig, loaded.config);
      expect(await database.readAsString(), loaded.database);
      expect(await currentProfile.readAsString(), 'old-profile');
    },
  );
}
