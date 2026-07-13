import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'path.dart';
import 'print.dart';
import 'utils.dart';

const _transactionDirectoryName = '.restore-transactions';
const _manifestFileName = 'manifest.json';
const _committedMarkerName = 'database-committed';
const _databaseRolledBackMarkerName = 'database-rolled-back';
const _databaseSnapshotName = 'database-before-restore.sqlite';
const _databaseCurrentName = 'database-after-restore.sqlite';
const _manifestVersion = 1;
const _pendingPrefix = 'pending-';
const _committedPrefix = 'committed-';

enum RestoreTransactionCheckpoint {
  manifestPersisted,
  destinationBackedUp,
  fileInstalled,
  databaseApplied,
  externalStateApplied,
  committed,
}

enum RestoreTransactionMutation {
  deleteDestination,
  restorePrevious,
  deleteDatabaseSidecar,
  moveDatabaseAside,
  installDatabaseSnapshot,
  deleteArtifact,
}

typedef RestoreTransactionFaultInjector =
    FutureOr<void> Function(
      RestoreTransactionCheckpoint checkpoint,
      int? index,
    );
typedef RestoreTransactionMutationGuard =
    FutureOr<void> Function(RestoreTransactionMutation mutation, String path);
typedef RestoreExternalStateOperation =
    Future<void> Function(String transactionRootPath);

@visibleForTesting
class RestoreTransactionInterruption implements Exception {
  const RestoreTransactionInterruption();
}

class RestoreRecoveryException implements Exception {
  RestoreRecoveryException(this.errors);

  final List<Object> errors;

  @override
  String toString() =>
      'Restore recovery failed with ${errors.length} error(s): '
      '${errors.join('; ')}';
}

Future<T> applyRestoreFilesAtomically<T>(
  MigrationData data,
  Future<T> Function() applyDatabase, {
  required Future<void> Function(String targetPath) createDatabaseSnapshot,
  String? restoreRootPath,
  String? homeRootPath,
  String? databasePath,
  RestoreTransactionFaultInjector? faultInjector,
  RestoreTransactionMutationGuard? mutationGuard,
  RestoreExternalStateOperation? createExternalStateSnapshot,
  Future<void> Function()? applyExternalState,
  Future<void> Function()? rollbackDatabase,
  RestoreExternalStateOperation? rollbackExternalState,
  RestoreExternalStateOperation? finalizeExternalState,
}) async {
  final restoreRoot = restoreRootPath ?? await appPath.restoreDirPath;
  final homeRoot = homeRootPath ?? await appPath.homeDirPath;
  final targetDatabasePath = databasePath ?? await appPath.databasePath;
  await _prepareForNewRestore(
    homeRoot,
    finalizeExternalState: finalizeExternalState,
  );

  final files = <_RestoreSource>[
    ...data.profiles.map(
      (item) => _RestoreSource(
        source: File(p.join(restoreRoot, 'profiles', '${item.id}.yaml')),
        destinationRelativePath: p.join('profiles', '${item.id}.yaml'),
      ),
    ),
    ...data.scripts.map(
      (item) => _RestoreSource(
        source: File(p.join(restoreRoot, 'scripts', '${item.id}.js')),
        destinationRelativePath: p.join('scripts', '${item.id}.js'),
      ),
    ),
  ];
  await _validateSources(files);

  final transactionId = utils.id.toString();
  final transactionRoot = Directory(
    p.join(
      homeRoot,
      _transactionDirectoryName,
      '$_pendingPrefix$transactionId',
    ),
  );
  final stagedRoot = Directory(p.join(transactionRoot.path, 'staged'));
  final previousRoot = Directory(p.join(transactionRoot.path, 'previous'));
  final manifestFile = File(p.join(transactionRoot.path, _manifestFileName));
  final databaseSnapshot = File(
    p.join(transactionRoot.path, _databaseSnapshotName),
  );
  final operations = <_RestoreOperation>[];

  try {
    await stagedRoot.create(recursive: true);
    await previousRoot.create(recursive: true);
    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      final destination = File(p.join(homeRoot, file.destinationRelativePath));
      final staged = File(p.join(stagedRoot.path, index.toString()));
      await _copyFileDurably(file.source, staged);
      operations.add(
        _RestoreOperation(
          destinationRelativePath: file.destinationRelativePath,
          stagedName: p.join('staged', index.toString()),
          previousName: p.join('previous', index.toString()),
          hadDestination: await destination.exists(),
        ),
      );
    }
    await createDatabaseSnapshot(databaseSnapshot.path);
    await createExternalStateSnapshot?.call(transactionRoot.path);
    final manifest = _RestoreManifest(
      transactionId: transactionId,
      operations: operations,
    );
    await _writeNewFileAtomically(manifestFile, jsonEncode(manifest.toJson()));
    await faultInjector?.call(
      RestoreTransactionCheckpoint.manifestPersisted,
      null,
    );
  } catch (_) {
    if (!await manifestFile.exists()) {
      try {
        await finalizeExternalState?.call(transactionRoot.path);
      } catch (_) {}
      await _cleanupTransactionBestEffort(
        transactionRoot,
        mutationGuard: mutationGuard,
      );
    }
    rethrow;
  }

  final manifest = _RestoreManifest(
    transactionId: transactionId,
    operations: operations,
  );
  late T result;
  var databaseApplied = false;
  try {
    for (var index = 0; index < operations.length; index++) {
      final operation = operations[index];
      final destination = _destinationFile(homeRoot, operation);
      final previous = _transactionFile(
        transactionRoot.path,
        operation.previousName,
      );
      final staged = _transactionFile(
        transactionRoot.path,
        operation.stagedName,
      );
      await destination.parent.create(recursive: true);
      if (operation.hadDestination) {
        await destination.rename(previous.path);
        await faultInjector?.call(
          RestoreTransactionCheckpoint.destinationBackedUp,
          index,
        );
      }
      await staged.rename(destination.path);
      await faultInjector?.call(
        RestoreTransactionCheckpoint.fileInstalled,
        index,
      );
    }
    result = await applyDatabase();
    databaseApplied = true;
    await faultInjector?.call(
      RestoreTransactionCheckpoint.databaseApplied,
      null,
    );
    await applyExternalState?.call();
    await faultInjector?.call(
      RestoreTransactionCheckpoint.externalStateApplied,
      null,
    );
  } on RestoreTransactionInterruption {
    rethrow;
  } catch (error, stackTrace) {
    final compensationErrors = <Object>[];
    if (databaseApplied && rollbackDatabase != null) {
      try {
        await rollbackDatabase();
      } catch (rollbackError) {
        compensationErrors.add(rollbackError);
      }
    }
    final rollbackErrors = await _rollbackTransaction(
      homeRoot: homeRoot,
      databasePath: targetDatabasePath,
      transactionRoot: transactionRoot,
      manifest: manifest,
      restoreDatabase: false,
      rollbackExternalState: rollbackExternalState,
      finalizeExternalState: finalizeExternalState,
    );
    rollbackErrors.addAll(compensationErrors);
    if (rollbackErrors.isNotEmpty) {
      _logRecoveryErrors('Restore rollback was incomplete', rollbackErrors);
    }
    Error.throwWithStackTrace(error, stackTrace);
  }

  Object? markerError;
  try {
    await _writeNewFileAtomically(
      File(p.join(transactionRoot.path, _committedMarkerName)),
      '',
    );
  } catch (error) {
    markerError = error;
  }
  var cleanupRoot = transactionRoot;
  Object? renameError;
  try {
    cleanupRoot = await transactionRoot.rename(
      p.join(transactionRoot.parent.path, '$_committedPrefix$transactionId'),
    );
  } catch (error) {
    renameError = error;
  }
  if (markerError != null && renameError != null) {
    throw RestoreRecoveryException([markerError, renameError]);
  }
  if (markerError != null || renameError != null) {
    commonPrint.log(
      'Restore committed with one redundant journal record unavailable: '
      '${markerError ?? renameError}',
      logLevel: LogLevel.warning,
    );
  }
  await faultInjector?.call(RestoreTransactionCheckpoint.committed, null);

  if (finalizeExternalState != null) {
    try {
      await finalizeExternalState(cleanupRoot.path);
    } catch (error) {
      commonPrint.log(
        'Restore external-state cleanup was deferred: $error',
        logLevel: LogLevel.warning,
      );
      return result;
    }
  }
  final cleanupErrors = await _cleanupTransactionBestEffort(
    cleanupRoot,
    mutationGuard: mutationGuard,
  );
  if (cleanupErrors.isNotEmpty) {
    _logRecoveryErrors('Restore cleanup was deferred', cleanupErrors);
  }
  return result;
}

Future<void> _prepareForNewRestore(
  String homeRoot, {
  RestoreExternalStateOperation? finalizeExternalState,
}) async {
  final transactionsRoot = Directory(
    p.join(homeRoot, _transactionDirectoryName),
  );
  if (!await transactionsRoot.exists()) {
    return;
  }
  final entities = await transactionsRoot
      .list(followLinks: false)
      .where((entity) => entity is Directory)
      .cast<Directory>()
      .toList();
  for (final transactionRoot in entities) {
    final committed =
        p.basename(transactionRoot.path).startsWith(_committedPrefix) ||
        await File(p.join(transactionRoot.path, _committedMarkerName)).exists();
    if (!committed) {
      throw RestoreRecoveryException([
        StateError(
          'An interrupted restore must be recovered before opening the '
          'database',
        ),
      ]);
    }
    if (finalizeExternalState != null) {
      try {
        await finalizeExternalState(transactionRoot.path);
      } catch (error) {
        commonPrint.log(
          'Committed restore external-state cleanup was deferred: $error',
          logLevel: LogLevel.warning,
        );
        continue;
      }
    }
    final cleanupErrors = await _cleanupTransactionBestEffort(transactionRoot);
    if (cleanupErrors.isNotEmpty) {
      _logRecoveryErrors(
        'Committed restore cleanup was deferred',
        cleanupErrors,
      );
    }
  }
}

Future<void> recoverPendingRestoreTransactions({
  required String homeRootPath,
  required String databasePath,
  RestoreTransactionMutationGuard? mutationGuard,
  RestoreExternalStateOperation? rollbackExternalState,
  RestoreExternalStateOperation? finalizeExternalState,
}) async {
  final transactionsRoot = Directory(
    p.join(homeRootPath, _transactionDirectoryName),
  );
  if (!await transactionsRoot.exists()) {
    return;
  }
  final errors = <Object>[];
  final entities = await transactionsRoot
      .list(followLinks: false)
      .where((entity) => entity is Directory)
      .cast<Directory>()
      .toList();
  entities.sort((left, right) => left.path.compareTo(right.path));
  for (final transactionRoot in entities) {
    if (p.basename(transactionRoot.path).startsWith(_committedPrefix)) {
      if (finalizeExternalState != null) {
        try {
          await finalizeExternalState(transactionRoot.path);
        } catch (error) {
          errors.add(error);
          continue;
        }
      }
      final cleanupErrors = await _cleanupTransactionBestEffort(
        transactionRoot,
        mutationGuard: mutationGuard,
      );
      if (cleanupErrors.isNotEmpty) {
        _logRecoveryErrors(
          'Committed restore cleanup was deferred',
          cleanupErrors,
        );
      }
      continue;
    }
    final manifestFile = File(p.join(transactionRoot.path, _manifestFileName));
    if (!await manifestFile.exists()) {
      if (finalizeExternalState != null) {
        try {
          await finalizeExternalState(transactionRoot.path);
        } catch (error) {
          errors.add(error);
          continue;
        }
      }
      final cleanupErrors = await _cleanupTransactionBestEffort(
        transactionRoot,
        mutationGuard: mutationGuard,
      );
      if (cleanupErrors.isNotEmpty) {
        _logRecoveryErrors(
          'Orphaned restore staging cleanup was deferred',
          cleanupErrors,
        );
      }
      continue;
    }

    late _RestoreManifest manifest;
    try {
      final raw = jsonDecode(await manifestFile.readAsString());
      manifest = _RestoreManifest.fromJson(raw);
      _validateManifest(transactionRoot, manifest, homeRootPath);
    } catch (error) {
      errors.add(error);
      continue;
    }

    final committed = await File(
      p.join(transactionRoot.path, _committedMarkerName),
    ).exists();
    if (committed) {
      if (finalizeExternalState != null) {
        try {
          await finalizeExternalState(transactionRoot.path);
        } catch (error) {
          errors.add(error);
          continue;
        }
      }
      final cleanupErrors = await _cleanupTransactionBestEffort(
        transactionRoot,
        mutationGuard: mutationGuard,
      );
      if (cleanupErrors.isNotEmpty) {
        _logRecoveryErrors(
          'Committed restore cleanup was deferred',
          cleanupErrors,
        );
      }
      continue;
    }

    errors.addAll(
      await _rollbackTransaction(
        homeRoot: homeRootPath,
        databasePath: databasePath,
        transactionRoot: transactionRoot,
        manifest: manifest,
        restoreDatabase: true,
        mutationGuard: mutationGuard,
        rollbackExternalState: rollbackExternalState,
        finalizeExternalState: finalizeExternalState,
      ),
    );
  }
  if (errors.isNotEmpty) {
    throw RestoreRecoveryException(errors);
  }

  try {
    if (await transactionsRoot.exists() &&
        await transactionsRoot.list(followLinks: false).isEmpty) {
      await transactionsRoot.delete();
    }
  } catch (error) {
    commonPrint.log(
      'Restore transaction directory cleanup was deferred: $error',
      logLevel: LogLevel.warning,
    );
  }
}

Future<List<Object>> _rollbackTransaction({
  required String homeRoot,
  required String databasePath,
  required Directory transactionRoot,
  required _RestoreManifest manifest,
  required bool restoreDatabase,
  RestoreTransactionMutationGuard? mutationGuard,
  RestoreExternalStateOperation? rollbackExternalState,
  RestoreExternalStateOperation? finalizeExternalState,
}) async {
  final errors = <Object>[];
  for (final operation in manifest.operations.reversed) {
    final destination = _destinationFile(homeRoot, operation);
    final staged = _transactionFile(transactionRoot.path, operation.stagedName);
    final previous = _transactionFile(
      transactionRoot.path,
      operation.previousName,
    );
    if (operation.hadDestination) {
      if (await previous.exists()) {
        try {
          if (await destination.exists()) {
            await mutationGuard?.call(
              RestoreTransactionMutation.deleteDestination,
              destination.path,
            );
            await destination.delete();
          }
          await mutationGuard?.call(
            RestoreTransactionMutation.restorePrevious,
            previous.path,
          );
          await previous.rename(destination.path);
        } catch (error) {
          errors.add(error);
        }
      }
    } else if (!await staged.exists() && await destination.exists()) {
      try {
        await mutationGuard?.call(
          RestoreTransactionMutation.deleteDestination,
          destination.path,
        );
        await destination.delete();
      } catch (error) {
        errors.add(error);
      }
    }
  }

  if (restoreDatabase) {
    errors.addAll(
      await _restoreDatabaseSnapshot(
        databasePath: databasePath,
        transactionRoot: transactionRoot,
        mutationGuard: mutationGuard,
      ),
    );
  }
  if (rollbackExternalState != null) {
    try {
      await rollbackExternalState(transactionRoot.path);
    } catch (error) {
      errors.add(error);
    }
  }
  if (errors.isEmpty && finalizeExternalState != null) {
    try {
      await finalizeExternalState(transactionRoot.path);
    } catch (error) {
      errors.add(error);
    }
  }
  if (errors.isEmpty) {
    final cleanupErrors = await _cleanupTransactionBestEffort(
      transactionRoot,
      mutationGuard: mutationGuard,
    );
    if (cleanupErrors.isNotEmpty) {
      _logRecoveryErrors(
        'Rolled back restore cleanup was deferred',
        cleanupErrors,
      );
    }
  }
  return errors;
}

Future<List<Object>> _restoreDatabaseSnapshot({
  required String databasePath,
  required Directory transactionRoot,
  RestoreTransactionMutationGuard? mutationGuard,
}) async {
  final errors = <Object>[];
  final rolledBackMarker = File(
    p.join(transactionRoot.path, _databaseRolledBackMarkerName),
  );
  if (await rolledBackMarker.exists()) {
    return errors;
  }
  final snapshot = File(p.join(transactionRoot.path, _databaseSnapshotName));
  if (!await snapshot.exists()) {
    return [StateError('Restore transaction database snapshot is missing')];
  }

  var sidecarsDeleted = true;
  for (final suffix in ['-wal', '-shm', '-journal']) {
    final sidecar = File('$databasePath$suffix');
    try {
      if (await sidecar.exists()) {
        await mutationGuard?.call(
          RestoreTransactionMutation.deleteDatabaseSidecar,
          sidecar.path,
        );
        await sidecar.delete();
      }
    } catch (error) {
      sidecarsDeleted = false;
      errors.add(error);
    }
  }
  if (!sidecarsDeleted) {
    return errors;
  }

  final destination = File(databasePath);
  final current = File(p.join(transactionRoot.path, _databaseCurrentName));
  final staged = File(
    '$databasePath.restore-${p.basename(transactionRoot.path)}',
  );
  try {
    await staged.parent.create(recursive: true);
    if (await staged.exists()) {
      await staged.delete();
    }
    await _copyFileDurably(snapshot, staged);
    if (await current.exists()) {
      await current.delete();
    }
    if (await destination.exists()) {
      await mutationGuard?.call(
        RestoreTransactionMutation.moveDatabaseAside,
        destination.path,
      );
      await destination.rename(current.path);
    }
    await mutationGuard?.call(
      RestoreTransactionMutation.installDatabaseSnapshot,
      destination.path,
    );
    await staged.rename(destination.path);
    await _writeNewFileAtomically(rolledBackMarker, '');
  } catch (error) {
    errors.add(error);
  }
  return errors;
}

Future<void> _validateSources(List<_RestoreSource> files) async {
  for (final file in files) {
    if (!await file.source.exists()) {
      throw const FormatException('Backup is missing referenced files');
    }
  }
}

void _validateManifest(
  Directory transactionRoot,
  _RestoreManifest manifest,
  String homeRoot,
) {
  final directoryName = p.basename(transactionRoot.path);
  final expectedPendingName = '$_pendingPrefix${manifest.transactionId}';
  final expectedCommittedName = '$_committedPrefix${manifest.transactionId}';
  if (manifest.version != _manifestVersion ||
      (directoryName != expectedPendingName &&
          directoryName != expectedCommittedName)) {
    throw const FormatException('Invalid restore transaction manifest');
  }
  for (final operation in manifest.operations) {
    final normalized = p.normalize(operation.destinationRelativePath);
    final portable = normalized.replaceAll('\\', '/');
    final isAllowed =
        RegExp(r'^profiles/[0-9]+\.yaml$').hasMatch(portable) ||
        RegExp(r'^scripts/[0-9]+\.js$').hasMatch(portable);
    final destination = p.normalize(p.join(homeRoot, normalized));
    if (!isAllowed || !p.isWithin(p.normalize(homeRoot), destination)) {
      throw const FormatException('Unsafe restore transaction destination');
    }
    for (final relative in [operation.stagedName, operation.previousName]) {
      final artifact = p.normalize(p.join(transactionRoot.path, relative));
      if (!p.isWithin(p.normalize(transactionRoot.path), artifact)) {
        throw const FormatException('Unsafe restore transaction artifact');
      }
    }
  }
}

File _destinationFile(String homeRoot, _RestoreOperation operation) {
  return File(p.join(homeRoot, operation.destinationRelativePath));
}

File _transactionFile(String transactionRoot, String relativePath) {
  return File(p.join(transactionRoot, relativePath));
}

Future<void> _copyFileDurably(File source, File destination) async {
  await destination.parent.create(recursive: true);
  final input = source.openRead();
  final output = destination.openWrite(mode: FileMode.writeOnly);
  try {
    await output.addStream(input);
    await output.flush();
  } finally {
    await output.close();
  }
}

Future<void> _writeNewFileAtomically(File target, String content) async {
  await target.parent.create(recursive: true);
  final temporary = File('${target.path}.tmp-${utils.id}');
  try {
    await temporary.writeAsString(content, flush: true);
    await temporary.rename(target.path);
  } finally {
    try {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    } catch (_) {}
  }
}

Future<List<Object>> _cleanupTransactionBestEffort(
  Directory transactionRoot, {
  RestoreTransactionMutationGuard? mutationGuard,
}) async {
  final errors = <Object>[];
  if (!await transactionRoot.exists()) {
    return errors;
  }
  final entities = await transactionRoot
      .list(recursive: true, followLinks: false)
      .toList();
  entities.sort((left, right) => right.path.length.compareTo(left.path.length));
  for (final entity in entities) {
    try {
      if (await entity.exists()) {
        await mutationGuard?.call(
          RestoreTransactionMutation.deleteArtifact,
          entity.path,
        );
        await entity.delete();
      }
    } catch (error) {
      errors.add(error);
    }
  }
  try {
    if (await transactionRoot.exists()) {
      await mutationGuard?.call(
        RestoreTransactionMutation.deleteArtifact,
        transactionRoot.path,
      );
      await transactionRoot.delete();
    }
  } catch (error) {
    errors.add(error);
  }
  return errors;
}

void _logRecoveryErrors(String message, List<Object> errors) {
  commonPrint.log(
    '$message (${errors.length} error(s)): ${errors.join('; ')}',
    logLevel: LogLevel.warning,
  );
}

class _RestoreSource {
  const _RestoreSource({
    required this.source,
    required this.destinationRelativePath,
  });

  final File source;
  final String destinationRelativePath;
}

class _RestoreManifest {
  const _RestoreManifest({
    required this.transactionId,
    required this.operations,
    this.version = _manifestVersion,
  });

  factory _RestoreManifest.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid restore transaction manifest');
    }
    final operations = raw['operations'];
    if (operations is! List) {
      throw const FormatException('Invalid restore transaction operations');
    }
    return _RestoreManifest(
      version: raw['version'] as int? ?? -1,
      transactionId: raw['transactionId'] as String? ?? '',
      operations: operations.map(_RestoreOperation.fromJson).toList(),
    );
  }

  final int version;
  final String transactionId;
  final List<_RestoreOperation> operations;

  Map<String, Object?> toJson() => {
    'version': version,
    'transactionId': transactionId,
    'operations': operations.map((operation) => operation.toJson()).toList(),
  };
}

class _RestoreOperation {
  const _RestoreOperation({
    required this.destinationRelativePath,
    required this.stagedName,
    required this.previousName,
    required this.hadDestination,
  });

  factory _RestoreOperation.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid restore transaction operation');
    }
    final destinationRelativePath = raw['destinationRelativePath'];
    final stagedName = raw['stagedName'];
    final previousName = raw['previousName'];
    final hadDestination = raw['hadDestination'];
    if (destinationRelativePath is! String ||
        stagedName is! String ||
        previousName is! String ||
        hadDestination is! bool) {
      throw const FormatException('Invalid restore transaction operation');
    }
    return _RestoreOperation(
      destinationRelativePath: destinationRelativePath,
      stagedName: stagedName,
      previousName: previousName,
      hadDestination: hadDestination,
    );
  }

  final String destinationRelativePath;
  final String stagedName;
  final String previousName;
  final bool hadDestination;

  Map<String, Object?> toJson() => {
    'destinationRelativePath': destinationRelativePath,
    'stagedName': stagedName,
    'previousName': previousName,
    'hadDestination': hadDestination,
  };
}
