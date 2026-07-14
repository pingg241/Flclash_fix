import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part '../generated/actions/store_action.g.dart';

typedef ConfigSaver = Future<bool> Function(Config config);

class StoreClearException implements Exception {
  final List<Object> errors;

  const StoreClearException(this.errors);

  @override
  String toString() => 'Failed to clear application data: ${errors.join('; ')}';
}

class StoreClearOperations {
  final Future<ClearFileTransaction> Function() stageFiles;
  final Future<void> Function(String targetPath) createDatabaseSnapshot;
  final Future<void> Function(String transactionRootPath)
  createPreferencesSnapshot;
  final Future<void> Function(String transactionRootPath)
  rollbackPreferencesSnapshot;
  final Future<void> Function(String transactionRootPath)
  finalizePreferencesSnapshot;
  final Future<void> Function() clearPreferences;
  final Future<void> Function() clearDatabase;
  final Future<void> Function() exitApplication;

  const StoreClearOperations({
    required this.stageFiles,
    required this.createDatabaseSnapshot,
    required this.createPreferencesSnapshot,
    required this.rollbackPreferencesSnapshot,
    required this.finalizePreferencesSnapshot,
    required this.clearPreferences,
    required this.clearDatabase,
    required this.exitApplication,
  });
}

final configSaverProvider = Provider<ConfigSaver>(
  (_) => preferences.saveConfig,
);

final storeClearOperationsProvider = Provider<StoreClearOperations>((ref) {
  return StoreClearOperations(
    stageFiles: () async {
      final homePath = await appPath.homeDirPath;
      return stageClearFilesAtomically(
        directoryPaths: [
          await appPath.profilesPath,
          await appPath.scriptsDirPath,
        ],
        transactionRootPath: p.join(
          homePath,
          clearTransactionsDirectoryName,
          'pending-${utils.id}',
        ),
      );
    },
    createDatabaseSnapshot: database.backupTo,
    createPreferencesSnapshot: preferences.createRestoreSnapshot,
    rollbackPreferencesSnapshot: preferences.rollbackRestoreSnapshot,
    finalizePreferencesSnapshot: preferences.finalizeRestoreSnapshot,
    clearPreferences: preferences.clearPreferences,
    clearDatabase: database.clearAllData,
    exitApplication: () =>
        ref.read(systemActionProvider.notifier).handleExit(false),
  );
});

@Riverpod(keepAlive: true)
class StoreAction extends _$StoreAction {
  Future<void> _saveTail = Future<void>.value();
  Future<void>? _clearTask;
  bool _isClearing = false;

  @override
  void build() {}

  Future<void> shakingStore() async {
    final profileIds = ref
        .read(profilesProvider)
        .map((item) => item.id)
        .toSet();
    final scripts = await ref.read(scriptsProvider.future);
    final scriptIds = scripts.map((item) => item.id).toSet();
    final pathsToDelete = await shakingProfileTask(VM2(profileIds, scriptIds));
    var nextIndex = 0;
    final errors = <({Object error, StackTrace stackTrace})>[];
    Future<void> worker() async {
      while (nextIndex < pathsToDelete.length) {
        final path = pathsToDelete[nextIndex++];
        try {
          final error = await coreController.deleteFile(path);
          throwIfFileSystemOperationFailed(error, path);
        } catch (error, stackTrace) {
          errors.add((error: error, stackTrace: stackTrace));
        }
      }
    }

    final workerCount = pathsToDelete.length < 4 ? pathsToDelete.length : 4;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    if (errors.isNotEmpty) {
      final first = errors.first;
      Error.throwWithStackTrace(first.error, first.stackTrace);
    }
  }

  void savePreferencesDebounce() {
    debouncer.call(FunctionTag.savePreferences, savePreferences);
  }

  Future<void> savePreferences() {
    if (_isClearing) {
      return Future<void>.error(
        StateError('Cannot save preferences while clearing application data'),
      );
    }
    final config = ref.read(configProvider);
    final operation = _saveTail.then((_) async {
      if (_isClearing) {
        throw StateError(
          'Cannot save preferences while clearing application data',
        );
      }
      final saved = await ref.read(configSaverProvider)(config);
      if (!saved) {
        throw StateError('Failed to save application preferences');
      }
    });
    _saveTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> flushPreferences() {
    debouncer.cancel(FunctionTag.savePreferences);
    return savePreferences();
  }

  Future<void> handleClear() {
    final clearTask = _clearTask;
    if (clearTask != null) {
      return clearTask;
    }
    final task = _handleClear();
    _clearTask = task;
    return task.whenComplete(() {
      if (identical(_clearTask, task)) {
        _clearTask = null;
      }
    });
  }

  Future<void> _handleClear() async {
    _isClearing = true;
    debouncer.cancel(FunctionTag.savePreferences);
    try {
      await _saveTail;
      final operations = ref.read(storeClearOperationsProvider);
      final fileTransaction = await operations.stageFiles();
      var preferencesSnapshotCreated = false;
      var databaseCleared = false;
      try {
        await operations.createDatabaseSnapshot(
          fileTransaction.databaseSnapshotPath,
        );
        await operations.createPreferencesSnapshot(fileTransaction.rootPath);
        preferencesSnapshotCreated = true;
        await operations.clearPreferences();
        await operations.clearDatabase();
        databaseCleared = true;
        await fileTransaction.markCommitted();
      } catch (error, stackTrace) {
        if (databaseCleared) {
          await operations.exitApplication();
          Error.throwWithStackTrace(error, stackTrace);
        }
        final rollbackErrors = <Object>[];
        var preferencesSettled = !preferencesSnapshotCreated;
        if (preferencesSnapshotCreated) {
          try {
            await operations.rollbackPreferencesSnapshot(
              fileTransaction.rootPath,
            );
            await operations.finalizePreferencesSnapshot(
              fileTransaction.rootPath,
            );
            preferencesSettled = true;
          } catch (rollbackError) {
            rollbackErrors.add(rollbackError);
          }
        }
        rollbackErrors.addAll(
          await fileTransaction.rollback(cleanup: preferencesSettled),
        );
        if (rollbackErrors.isNotEmpty) {
          throw StoreClearException([error, ...rollbackErrors]);
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      var preferencesFinalized = false;
      try {
        await operations.finalizePreferencesSnapshot(fileTransaction.rootPath);
        preferencesFinalized = true;
      } catch (error, stackTrace) {
        commonPrint.log(
          'Clear preferences snapshot cleanup was deferred: '
          '$error\n$stackTrace',
          logLevel: LogLevel.warning,
        );
      }
      if (preferencesFinalized) {
        try {
          await fileTransaction.commit();
        } catch (error, stackTrace) {
          commonPrint.log(
            'Clear file staging cleanup was deferred: $error\n$stackTrace',
            logLevel: LogLevel.warning,
          );
        }
      }
      commonPrint.log('clear preferences');
      await operations.exitApplication();
    } finally {
      _isClearing = false;
    }
  }
}
