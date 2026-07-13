import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

/// An extension on `Map<String, String>` to add support for specific
/// configuration options related to backward compatibility.
@visibleForTesting
extension OptionsExtension on Map<String, String> {
  /// Checks whether the `useBackwardCompatibility` flag is enabled in the map.
  ///
  /// Returns:
  /// - `true` if the value associated with the `useBackwardCompatibility` key
  ///   is not `'false'`.
  /// - `false` otherwise.
  bool get useBackwardCompatibility =>
      this['useBackwardCompatibility'] != 'false';
}

/// Serialises async critical sections without external dependencies.
///
/// Each [run] call waits for the previous one to finish (including error cases)
/// before starting the next, preventing concurrent read-modify-write races.
class _AsyncLock {
  Future<void> _last = Future.value();

  Future<T> run<T>(Future<T> Function() fn) {
    final next = _last.then((_) => fn());
    // Swallow errors so a failed operation does not poison future callers.
    _last = next.then<void>((_) {}, onError: (_) {});
    return next;
  }
}

/// The `FlutterSecureStorageWindows` class provides a Windows-specific
/// implementation of the `FlutterSecureStoragePlatform` interface.
///
/// This implementation uses a combination of a backward-compatible storage
/// mechanism and a platform-specific storage backend.
class FlutterSecureStorageWindows extends FlutterSecureStoragePlatform {
  /// Creates an instance of `FlutterSecureStorageWindows` with default
  /// configurations for both backward compatibility and platform-specific
  /// storage.
  FlutterSecureStorageWindows()
      : this._(
          MethodChannelFlutterSecureStorage(),
          DpapiJsonFileMapStorage(),
        );

  /// Internal constructor to initialize `FlutterSecureStorageWindows` with
  /// custom implementations for backward compatibility and platform-specific
  /// storage.
  ///
  /// Parameters:
  /// - [_backwardCompatible]: The storage mechanism used for backward
  ///   compatibility.
  /// - [_storage]: The platform-specific storage backend for Windows.
  FlutterSecureStorageWindows._(
    this._backwardCompatible,
    this._storage,
  );

  /// The storage implementation used for backward compatibility.
  final FlutterSecureStoragePlatform _backwardCompatible;

  /// The platform-specific storage implementation for Windows, using DPAPI.
  final MapStorage _storage;

  final _lock = _AsyncLock();

  /// Registers this plugin.
  static void registerWith() {
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageWindows();
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) =>
      _lock.run(() async {
        final map = await _storage.load(options);
        if (map.containsKey(key)) {
          return true;
        }

        if (options.useBackwardCompatibility) {
          return _backwardCompatible.containsKey(key: key, options: options);
        }

        return false;
      });

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) =>
      _lock.run(() async {
        final map = await _storage.load(options);
        final initialSize = map.length;
        map.remove(key);
        if (map.length != initialSize) {
          await _storage.save(map, options);
        }

        if (options.useBackwardCompatibility) {
          await _backwardCompatible.delete(key: key, options: options);
        }
      });

  @override
  Future<void> deleteAll({required Map<String, String> options}) =>
      _lock.run(() async {
        await _storage.clear(options);

        if (options.useBackwardCompatibility) {
          await _backwardCompatible.deleteAll(options: options);
        }
      });

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) =>
      _lock.run(() async {
        final map = await _storage.load(options);

        var result = map[key];
        if (options.useBackwardCompatibility) {
          if (result == null) {
            final compatible =
                await _backwardCompatible.read(key: key, options: options);
            if (compatible != null) {
              // Write back now, so the value should be retrieved from JSON file
              // next.
              result = map[key] = compatible;
              await _storage.save(map, options);
            }
          }

          // Clear old entry.
          await _backwardCompatible.delete(key: key, options: options);
        }

        return result;
      });

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) =>
      _lock.run(() async {
        final map = await _storage.load(options);
        if (!options.useBackwardCompatibility) {
          // Just return a map.
          return map;
        }

        final compatible = await _backwardCompatible.readAll(options: options);

        if (compatible.isEmpty) {
          return map;
        }

        for (final entry in compatible.entries) {
          map.putIfAbsent(entry.key, () => entry.value);
        }

        // Write back now, so the value should be retrieved from JSON file next.
        await _storage.save(map, options);

        // Clear old entries.
        await _backwardCompatible.deleteAll(options: options);

        return map;
      });

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) =>
      _lock.run(() async {
        final map = await _storage.load(options);
        map[key] = value;
        await _storage.save(map, options);

        if (options.useBackwardCompatibility) {
          // Clear old entry.
          await _backwardCompatible.delete(key: key, options: options);
        }
      });
}

/// Creates a custom instance of `FlutterSecureStorageWindows` for testing.
///
/// This factory function is annotated with `@visibleForTesting` to indicate
/// its intended use in testing scenarios. It allows specifying custom
/// implementations for backward compatibility and platform-specific storage.
///
/// Parameters:
/// - [backwardCompatible]: A custom implementation of
///   `FlutterSecureStoragePlatform` for backward-compatible storage behavior.
/// - [mapStorage]: A custom implementation of `MapStorage` for Windows secure
///   storage functionality.
///
/// Returns:
/// - An instance of `FlutterSecureStorageWindows` configured with the given
///   `backwardCompatible` and `mapStorage` implementations.
@visibleForTesting
FlutterSecureStorageWindows createFlutterSecureStorageWindows(
  FlutterSecureStoragePlatform backwardCompatible,
  MapStorage mapStorage,
) =>
    FlutterSecureStorageWindows._(backwardCompatible, mapStorage);

@visibleForTesting

/// An abstract class that defines the interface for map-based storage
/// implementations.
abstract class MapStorage {
  /// Loads a map of key-value pairs from the storage medium.
  ///
  /// Parameters:
  /// - [options]: A map of options to customize the load operation.
  FutureOr<Map<String, String>> load(Map<String, String> options);

  /// Saves a map of key-value pairs to the storage medium.
  ///
  /// Parameters:
  /// - [data]: A map containing the data to save.
  /// - [options]: A map of options to customize the save operation.
  FutureOr<void> save(Map<String, String> data, Map<String, String> options);

  /// Clears all key-value pairs from the storage medium.
  ///
  /// Parameters:
  /// - [options]: A map of options to customize the clear operation.
  FutureOr<void> clear(Map<String, String> options);
}

/// The file name used to store encrypted JSON data.
///
/// This constant is exposed for testing purposes.
@visibleForTesting
const String encryptedJsonFileName = 'flutter_secure_storage.dat';

/// File operations used by the Windows secure storage backend.
///
/// This boundary keeps persistence failures deterministic in tests while the
/// production implementation continues to use [File] directly.
@visibleForTesting
abstract interface class SecureStorageFileSystem {
  /// Returns whether [filePath] exists.
  Future<bool> exists(String filePath);

  /// Reads all bytes from [filePath].
  Future<Uint8List> read(String filePath);

  /// Writes and flushes [bytes] to [filePath].
  Future<void> write(String filePath, Uint8List bytes);

  /// Renames [sourcePath] to [destinationPath].
  Future<void> rename(String sourcePath, String destinationPath);

  /// Deletes [filePath].
  Future<void> delete(String filePath);
}

class _IoSecureStorageFileSystem implements SecureStorageFileSystem {
  const _IoSecureStorageFileSystem();

  @override
  Future<void> delete(String filePath) => File(filePath).delete();

  @override
  Future<bool> exists(String filePath) => File(filePath).exists();

  @override
  Future<Uint8List> read(String filePath) => File(filePath).readAsBytes();

  @override
  Future<void> rename(String sourcePath, String destinationPath) async {
    await File(sourcePath).rename(destinationPath);
  }

  @override
  Future<void> write(String filePath, Uint8List bytes) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }
}

/// A `MapStorage` implementation that uses DPAPI (Data Protection API) for
/// encryption and stores data in a JSON file on disk.
///
/// This implementation is specific to Windows platforms.
@visibleForTesting
class DpapiJsonFileMapStorage extends MapStorage {
  /// Creates an instance of `DpapiJsonFileMapStorage`.
  DpapiJsonFileMapStorage({
    SecureStorageFileSystem? fileSystem,
    FutureOr<String> Function()? filePathProvider,
    Future<void> Function(Duration)? retryDelay,
    int maxAttempts = 4,
  })  : assert(maxAttempts > 0),
        _fileSystem = fileSystem ?? const _IoSecureStorageFileSystem(),
        _filePathProvider = filePathProvider,
        _retryDelay = retryDelay ?? Future<void>.delayed,
        _maxAttempts = maxAttempts;

  final SecureStorageFileSystem _fileSystem;
  final FutureOr<String> Function()? _filePathProvider;
  final Future<void> Function(Duration) _retryDelay;
  final int _maxAttempts;

  /// Retrieves the canonical path to the encrypted JSON file used for storage.
  ///
  /// This method constructs the file path based on the application's support
  /// directory.
  ///
  /// Returns:
  /// - A [FutureOr] resolving to the canonical file path as a string.
  FutureOr<String> _getJsonFilePath() async {
    final filePathProvider = _filePathProvider;
    if (filePathProvider != null) {
      return path.canonicalize(await filePathProvider());
    }

    final appDataDirectory = await getApplicationSupportDirectory();

    return path.canonicalize(
      path.join(
        appDataDirectory.path,
        encryptedJsonFileName,
      ),
    );
  }

  @override
  FutureOr<Map<String, String>> load(Map<String, String> options) async {
    final filePath = await _getJsonFilePath();
    final backupPath = '$filePath.bak';
    final temporaryPath = '$filePath.tmp';

    await _restoreMissingPrimary(filePath, backupPath, temporaryPath);
    if (!await _fileSystem.exists(filePath)) {
      return {};
    }

    try {
      final result = await _loadMap(filePath);
      await _deleteBestEffort(backupPath);
      await _deleteBestEffort(temporaryPath);
      return result;
    } catch (error, stackTrace) {
      if (error is! FormatException && error is! WindowsException) {
        rethrow;
      }

      final recovered = await _recoverCorruptPrimary(
        filePath,
        backupPath,
        temporaryPath,
      );
      if (recovered != null) {
        return recovered;
      }

      debugPrint('Failed to load secure storage: $error');
      await _deleteBestEffort(filePath);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  FutureOr<void> save(
    Map<String, String> data,
    Map<String, String> options,
  ) async {
    final filePath = await _getJsonFilePath();
    final encryptedText = _encrypt(utf8.encode(jsonEncode(data)));
    await _atomicWrite(filePath, encryptedText);
  }

  @override
  FutureOr<void> clear(Map<String, String> options) async {
    final filePath = await _getJsonFilePath();
    for (final candidate in [filePath, '$filePath.tmp', '$filePath.bak']) {
      await _deleteIfExists(candidate);
    }
  }

  Uint8List _encrypt(List<int> plainText) => using((alloc) {
        final pPlainText = alloc<Uint8>(plainText.length);
        pPlainText.asTypedList(plainText.length).setAll(0, plainText);

        final plainTextBlob =
            alloc.allocate<CRYPT_INTEGER_BLOB>(sizeOf<CRYPT_INTEGER_BLOB>());
        plainTextBlob.ref.cbData = plainText.length;
        plainTextBlob.ref.pbData = pPlainText;

        final encryptedTextBlob =
            alloc.allocate<CRYPT_INTEGER_BLOB>(sizeOf<CRYPT_INTEGER_BLOB>());
        final Win32Result(value: isProtected, error: protectError) =
            CryptProtectData(
          plainTextBlob,
          null,
          null,
          null,
          0,
          encryptedTextBlob,
        );
        if (!isProtected) {
          throw WindowsException(
            protectError.toHRESULT(),
            message: 'Failure on CryptProtectData()',
          );
        }
        if (encryptedTextBlob.ref.pbData.address == NULL) {
          throw WindowsException(
            ERROR_OUTOFMEMORY.toHRESULT(),
            message: 'Failure on CryptProtectData()',
          );
        }

        try {
          return Uint8List.fromList(
            encryptedTextBlob.ref.pbData.asTypedList(
              encryptedTextBlob.ref.cbData,
            ),
          );
        } finally {
          _localFree(encryptedTextBlob, 'save');
        }
      });

  Map<String, String> _decrypt(Uint8List encryptedText) => using((alloc) {
        final pEncryptedText = alloc<Uint8>(encryptedText.length);
        pEncryptedText
            .asTypedList(encryptedText.length)
            .setAll(0, encryptedText);

        final encryptedTextBlob =
            alloc.allocate<CRYPT_INTEGER_BLOB>(sizeOf<CRYPT_INTEGER_BLOB>());
        encryptedTextBlob.ref.cbData = encryptedText.length;
        encryptedTextBlob.ref.pbData = pEncryptedText;

        final plainTextBlob =
            alloc.allocate<CRYPT_INTEGER_BLOB>(sizeOf<CRYPT_INTEGER_BLOB>());
        final Win32Result(value: isUnprotected, error: unprotectError) =
            CryptUnprotectData(
          encryptedTextBlob,
          null,
          null,
          null,
          0,
          plainTextBlob,
        );
        if (!isUnprotected) {
          throw WindowsException(
            unprotectError.toHRESULT(),
            message: 'Failure on CryptUnprotectData()',
          );
        }
        if (plainTextBlob.ref.pbData.address == NULL) {
          throw WindowsException(
            ERROR_OUTOFMEMORY.toHRESULT(),
            message: 'Failure on CryptUnprotectData()',
          );
        }

        try {
          final plainText = utf8.decoder.convert(
            plainTextBlob.ref.pbData.asTypedList(plainTextBlob.ref.cbData),
          );
          final decoded = jsonDecode(plainText);
          if (decoded is! Map) {
            throw const FormatException('JSON is not an object.');
          }

          return {
            for (final entry in decoded.entries.where(
              (entry) => entry.key is String && entry.value is String,
            ))
              entry.key as String: entry.value as String,
          };
        } finally {
          _localFree(plainTextBlob, 'load');
        }
      });

  void _localFree(Pointer<CRYPT_INTEGER_BLOB> blob, String operation) {
    if (blob.ref.pbData.address == NULL) {
      return;
    }
    final Win32Result(value: result, error: error) =
        LocalFree(HLOCAL(blob.ref.pbData.cast()));
    if (!result.isNull) {
      debugPrint(
        '$operation: Failed to LocalFree with: '
        '${error.toHRESULT().toHexString()}',
      );
    }
  }

  Future<Map<String, String>> _loadMap(String filePath) async {
    final encryptedText = await _retryTransient(
      () => _fileSystem.read(filePath),
    );
    return _decrypt(encryptedText);
  }

  Future<void> _atomicWrite(String filePath, Uint8List bytes) async {
    final temporaryPath = '$filePath.tmp';
    final backupPath = '$filePath.bak';
    await _retryTransient(() => _fileSystem.write(temporaryPath, bytes));

    if (await _fileSystem.exists(filePath)) {
      await _deleteIfExists(backupPath);
      await _retryTransient(
        () => _fileSystem.rename(filePath, backupPath),
      );
    }

    try {
      await _retryTransient(
        () => _fileSystem.rename(temporaryPath, filePath),
      );
    } catch (_) {
      if (!await _fileSystem.exists(filePath) &&
          await _fileSystem.exists(backupPath)) {
        try {
          await _retryTransient(
            () => _fileSystem.rename(backupPath, filePath),
          );
        } on FileSystemException catch (error) {
          debugPrint('Failed to roll back secure storage: $error');
        }
      }
      rethrow;
    }

    await _deleteBestEffort(backupPath);
  }

  Future<void> _restoreMissingPrimary(
    String filePath,
    String backupPath,
    String temporaryPath,
  ) async {
    if (await _fileSystem.exists(filePath)) {
      return;
    }
    if (await _fileSystem.exists(backupPath)) {
      await _retryTransient(
        () => _fileSystem.rename(backupPath, filePath),
      );
      await _deleteBestEffort(temporaryPath);
      return;
    }
    if (await _fileSystem.exists(temporaryPath)) {
      await _retryTransient(
        () => _fileSystem.rename(temporaryPath, filePath),
      );
    }
  }

  Future<Map<String, String>?> _recoverCorruptPrimary(
    String filePath,
    String backupPath,
    String temporaryPath,
  ) async {
    if (!await _fileSystem.exists(backupPath)) {
      return null;
    }

    try {
      final backup = await _loadMap(backupPath);
      await _deleteIfExists(filePath);
      await _retryTransient(
        () => _fileSystem.rename(backupPath, filePath),
      );
      await _deleteBestEffort(temporaryPath);
      debugPrint('Recovered secure storage from backup.');
      return backup;
    } catch (error) {
      if (error is FormatException || error is WindowsException) {
        debugPrint('Failed to recover secure storage backup: $error');
        return null;
      }
      rethrow;
    }
  }

  Future<void> _deleteIfExists(String filePath) async {
    if (!await _fileSystem.exists(filePath)) {
      return;
    }
    try {
      await _retryTransient(() => _fileSystem.delete(filePath));
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (code == ERROR_FILE_NOT_FOUND || code == ERROR_PATH_NOT_FOUND) {
        return;
      }
      rethrow;
    }
  }

  Future<void> _deleteBestEffort(String filePath) async {
    try {
      await _deleteIfExists(filePath);
    } on FileSystemException catch (error) {
      debugPrint('Failed to delete stale secure storage file: $error');
    }
  }

  Future<T> _retryTransient<T>(Future<T> Function() operation) async {
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        return await operation();
      } on FileSystemException catch (error) {
        if (!_isTransient(error) || attempt + 1 >= _maxAttempts) {
          rethrow;
        }
        await _retryDelay(
          Duration(milliseconds: 10 * (1 << attempt)),
        );
      }
    }
    throw StateError('Unreachable retry state.');
  }

  bool _isTransient(FileSystemException error) {
    final code = error.osError?.errorCode;
    return code == ERROR_FILE_NOT_FOUND ||
        code == ERROR_PATH_NOT_FOUND ||
        code == ERROR_SHARING_VIOLATION ||
        code == ERROR_LOCK_VIOLATION;
  }
}
