import 'dart:io';

import 'package:flutter/foundation.dart';

typedef DirectorySync = Future<void> Function(Directory directory);

/// Persists a rename and its containing directory entry where the platform
/// exposes directory fsync. Windows does not support opening directories for
/// fsync; in that case the file flush and atomic rename remain the fallback.
@visibleForTesting
Future<void> syncDirectoryDurably(
  Directory directory, {
  DirectorySync? sync,
}) async {
  if (sync != null) {
    await sync(directory);
    return;
  }
  if (Platform.isWindows) return;
  RandomAccessFile? handle;
  try {
    handle = await File(directory.path).open(mode: FileMode.read);
    await handle.flush();
  } on FileSystemException {
    // Some platforms/filesystems reject directory handles. The atomic rename
    // is still the strongest portable fallback available to Dart.
  } finally {
    await handle?.close();
  }
}

Future<void> writeFileAtomicallyDurable(
  File target,
  String content, {
  DirectorySync? syncDirectory,
}) async {
  await target.parent.create(recursive: true);
  final temporary = File('${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
  try {
    await temporary.writeAsString(content, flush: true);
    await temporary.rename(target.path);
    await syncDirectoryDurably(target.parent, sync: syncDirectory);
  } finally {
    try {
      if (await temporary.exists()) await temporary.delete();
    } catch (_) {}
  }
}
