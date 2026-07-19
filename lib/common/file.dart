import 'dart:io';

import 'package:flutter/foundation.dart';

void throwIfFileSystemOperationFailed(String error, String path) {
  if (error.isNotEmpty) {
    throw FileSystemException(error, path);
  }
}

typedef StagedFileCopier = Future<void> Function(File source, File staged);

Future<void> replaceFileFromSourceAtomically(
  File source,
  File target, {
  @visibleForTesting StagedFileCopier? copyToStage,
}) async {
  if (!await source.exists()) {
    throw FileSystemException('Source file does not exist', source.path);
  }
  if (source.absolute.path == target.absolute.path) {
    return;
  }
  await target.parent.create(recursive: true);
  final suffix = DateTime.now().microsecondsSinceEpoch;
  final staged = File('${target.path}.staged-$suffix');
  final previous = File('${target.path}.previous-$suffix');
  var previousMoved = false;
  try {
    await (copyToStage ?? _copyFileFlushed)(source, staged);
    if (await target.exists()) {
      await target.rename(previous.path);
      previousMoved = true;
    }
    await staged.rename(target.path);
    await previous.safeDelete();
    previousMoved = false;
  } catch (_) {
    if (previousMoved) {
      await target.safeDelete();
      await previous.rename(target.path);
      previousMoved = false;
    }
    rethrow;
  } finally {
    await staged.safeDelete();
    if (!previousMoved) {
      await previous.safeDelete();
    }
  }
}

Future<void> _copyFileFlushed(File source, File staged) async {
  final output = await staged.open(mode: FileMode.write);
  try {
    await for (final chunk in source.openRead()) {
      await output.writeFrom(chunk);
    }
    await output.flush();
  } finally {
    await output.close();
  }
}

extension FileExt on File {
  Future<void> safeCopy(String newPath) async {
    if (!await exists()) {
      throw FileSystemException('Source file does not exist', path);
    }
    final targetFile = File(newPath);
    await targetFile.parent.create(recursive: true);
    await copy(newPath);
  }

  Future<File> safeWriteAsString(String str) async {
    if (!await exists()) {
      await create(recursive: true);
    }
    return writeAsString(str);
  }

  Future<File> safeWriteAsBytes(List<int> bytes) async {
    if (!await exists()) {
      await create(recursive: true);
    }
    return writeAsBytes(bytes);
  }
}

extension FileSystemEntityExt on FileSystemEntity {
  Future<void> safeDelete({bool recursive = false}) async {
    try {
      await delete(recursive: recursive);
    } on FileSystemException catch (error) {
      final errorCode = error.osError?.errorCode;
      final isNotFound =
          errorCode == 2 || (Platform.isWindows && errorCode == 3);
      if (!isNotFound) {
        rethrow;
      }
    }
  }
}
