import 'dart:io';

void throwIfFileSystemOperationFailed(String error, String path) {
  if (error.isNotEmpty) {
    throw FileSystemException(error, path);
  }
}

extension FileExt on File {
  Future<void> safeCopy(String newPath) async {
    if (!await exists()) {
      await create(recursive: true);
      return;
    }
    final targetFile = File(newPath);
    if (!await targetFile.exists()) {
      await targetFile.create(recursive: true);
    }
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
