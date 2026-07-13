import 'dart:io';

import 'error.dart';

String _require(String key) {
  final value = Platform.environment[key];
  if (value == null || value.isEmpty) {
    throw BuildException('Required environment variable not set: $key');
  }
  return value;
}

String _get(String key, {String? defaultValue}) {
  return Platform.environment[key] ?? defaultValue ?? '';
}

class Environment {
  /// Resolve Android NDK path from common env vars / SDK layouts.
  ///
  /// Order: ANDROID_NDK → ANDROID_NDK_HOME → ANDROID_HOME|ANDROID_SDK_ROOT/ndk/*
  static String get androidNdk {
    final direct = _get('ANDROID_NDK');
    if (direct.isNotEmpty && Directory(direct).existsSync()) {
      return direct;
    }
    final home = _get('ANDROID_NDK_HOME');
    if (home.isNotEmpty && Directory(home).existsSync()) {
      return home;
    }
    final sdk = _get('ANDROID_HOME').isNotEmpty
        ? _get('ANDROID_HOME')
        : _get('ANDROID_SDK_ROOT');
    if (sdk.isNotEmpty) {
      final ndkRoot = Directory('$sdk${Platform.pathSeparator}ndk');
      if (ndkRoot.existsSync()) {
        final versions = ndkRoot
            .listSync()
            .whereType<Directory>()
            .where((d) => !d.uri.pathSegments.last.startsWith('.'))
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));
        if (versions.isNotEmpty) {
          return versions.first.path;
        }
      }
      final bundled = Directory(
        '$sdk${Platform.pathSeparator}ndk-bundle',
      );
      if (bundled.existsSync()) {
        return bundled.path;
      }
    }
    throw BuildException(
      'Android NDK not found. Set ANDROID_NDK (preferred) or ANDROID_NDK_HOME, '
      'or install an NDK under ANDROID_HOME/ndk/.',
    );
  }

  static String get appEnv => _get('APP_ENV', defaultValue: 'pre');
  static String get configuration =>
      _get('BUILDKIT_CONFIGURATION', defaultValue: 'Release').toLowerCase();
  static bool get isDebug => configuration == 'debug';

  static String get hostOs {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'darwin';
    return 'unknown';
  }

  static Future<String> get hostArch async {
    if (Platform.isWindows) {
      return Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'AMD64';
    }
    final result = await Process.run('uname', ['-m']);
    return (result.stdout as String).trim();
  }
}
