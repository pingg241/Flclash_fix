import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'file.dart';
import 'durable_file.dart';

const clearTransactionsDirectoryName = '.clear-transactions';
const _manifestName = 'manifest.json';
const _committedName = 'committed';
const clearDatabaseSnapshotName = 'database-before-clear.sqlite';

typedef ClearStageFaultInjector = FutureOr<void> Function(int index);
typedef ClearExternalStateOperation = Future<void> Function(String rootPath);

class ClearRecoveryException implements Exception {
  final List<Object> errors;

  const ClearRecoveryException(this.errors);

  @override
  String toString() => 'Clear recovery failed: ${errors.join('; ')}';
}

class ClearFileTransaction {
  final Directory root;
  final List<({Directory original, Directory staged})> _moves;
  bool _settled = false;

  ClearFileTransaction._(this.root, this._moves);

  String get rootPath => root.path;
  String get databaseSnapshotPath =>
      p.join(root.path, clearDatabaseSnapshotName);

  Future<void> markCommitted() =>
      _writeDurably(File(p.join(root.path, _committedName)), '');

  Future<List<Object>> rollback({bool cleanup = true}) async {
    if (_settled) return const [];
    final errors = await _restoreMoves(_moves);
    if (errors.isEmpty) {
      _settled = true;
      if (cleanup) await root.safeDelete(recursive: true);
    }
    return errors;
  }

  Future<void> commit() async {
    if (_settled) return;
    _settled = true;
    await root.safeDelete(recursive: true);
  }
}

Future<ClearFileTransaction> stageClearFilesAtomically({
  required List<String> directoryPaths,
  required String transactionRootPath,
  ClearStageFaultInjector? faultInjector,
}) async {
  final root = Directory(transactionRootPath);
  final moves = <({Directory original, Directory staged})>[];
  final transaction = ClearFileTransaction._(root, moves);
  try {
    await root.create(recursive: true);
    final manifest = <String, Object?>{
      'version': 1,
      'directories': directoryPaths,
    };
    await _writeDurably(
      File(p.join(root.path, _manifestName)),
      jsonEncode(manifest),
    );
    for (var index = 0; index < directoryPaths.length; index++) {
      final original = Directory(directoryPaths[index]);
      if (!await original.exists()) continue;
      final staged = Directory(p.join(root.path, 'data-$index'));
      await original.rename(staged.path);
      moves.add((original: original, staged: staged));
      await faultInjector?.call(index);
    }
    return transaction;
  } catch (error, stackTrace) {
    final rollbackErrors = await transaction.rollback();
    if (rollbackErrors.isNotEmpty) {
      throw ClearRecoveryException([error, ...rollbackErrors]);
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
}

Future<void> recoverPendingClearTransactions({
  required String homeRootPath,
  required String databasePath,
  required ClearExternalStateOperation rollbackExternalState,
  required ClearExternalStateOperation finalizeExternalState,
}) async {
  final transactionsRoot = Directory(
    p.join(homeRootPath, clearTransactionsDirectoryName),
  );
  if (!await transactionsRoot.exists()) return;
  final roots = await transactionsRoot
      .list(followLinks: false)
      .where((entity) => entity is Directory)
      .cast<Directory>()
      .toList();
  roots.sort((left, right) => left.path.compareTo(right.path));
  final errors = <Object>[];
  for (final root in roots) {
    try {
      final manifest = File(p.join(root.path, _manifestName));
      if (!await manifest.exists()) {
        await root.safeDelete(recursive: true);
        continue;
      }
      final moves = await _readMoves(root, homeRootPath);
      final committed = await File(p.join(root.path, _committedName)).exists();
      if (!committed) {
        await _restoreDatabaseSnapshot(root, databasePath);
        await rollbackExternalState(root.path);
        final moveErrors = await _restoreMoves(moves);
        if (moveErrors.isNotEmpty) throw ClearRecoveryException(moveErrors);
      }
      await finalizeExternalState(root.path);
      await root.safeDelete(recursive: true);
    } catch (error) {
      errors.add(error);
    }
  }
  if (errors.isNotEmpty) throw ClearRecoveryException(errors);
  if (await transactionsRoot.list(followLinks: false).isEmpty) {
    await transactionsRoot.delete();
  }
}

Future<List<({Directory original, Directory staged})>> _readMoves(
  Directory root,
  String homeRootPath,
) async {
  final manifestFile = File(p.join(root.path, _manifestName));
  final raw = jsonDecode(await manifestFile.readAsString());
  if (raw is! Map<String, dynamic> || raw['version'] != 1) {
    throw const FormatException('Invalid clear transaction manifest');
  }
  final directories = raw['directories'];
  if (directories is! List || directories.any((item) => item is! String)) {
    throw const FormatException('Invalid clear transaction directories');
  }
  final home = p.canonicalize(homeRootPath);
  final moves = <({Directory original, Directory staged})>[];
  for (var index = 0; index < directories.length; index++) {
    final originalPath = p.canonicalize(directories[index] as String);
    if (!p.isWithin(home, originalPath)) {
      throw const FormatException('Clear transaction path escapes home');
    }
    moves.add((
      original: Directory(originalPath),
      staged: Directory(p.join(root.path, 'data-$index')),
    ));
  }
  return moves;
}

Future<List<Object>> _restoreMoves(
  List<({Directory original, Directory staged})> moves,
) async {
  final errors = <Object>[];
  for (final move in moves.reversed) {
    try {
      if (!await move.staged.exists()) continue;
      if (await move.original.exists()) {
        throw FileSystemException(
          'Cannot restore staged data over an existing directory',
          move.original.path,
        );
      }
      await move.staged.rename(move.original.path);
    } catch (error) {
      errors.add(error);
    }
  }
  return errors;
}

Future<void> _restoreDatabaseSnapshot(
  Directory root,
  String databasePath,
) async {
  final snapshot = File(p.join(root.path, clearDatabaseSnapshotName));
  if (!await snapshot.exists()) return;
  for (final suffix in ['-wal', '-shm', '-journal']) {
    await File('$databasePath$suffix').safeDelete();
  }
  final staged = File('$databasePath.clear-restore');
  await staged.safeDelete();
  await snapshot.copy(staged.path);
  await File(databasePath).safeDelete();
  await staged.rename(databasePath);
}

Future<void> _writeDurably(File target, String value) async {
  await writeFileAtomicallyDurable(target, value);
}
