import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const appImageToolVersion = '1.9.1';
const appImageToolSha256 =
    'ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0';
const _appImageToolUrl =
    'https://github.com/AppImage/appimagetool/releases/download/'
    '$appImageToolVersion/appimagetool-x86_64.AppImage';
const _downloadConnectionTimeout = Duration(seconds: 15);
const _downloadHeaderTimeout = Duration(seconds: 30);
const _downloadReadTimeout = Duration(seconds: 30);
const _downloadOverallTimeout = Duration(minutes: 5);

const _allTargets = <String, String>{
  'android': 'apk',
  'linux': 'deb', // appimage + rpm added for amd64 only
  'macos': 'dmg',
  'windows': 'exe,zip',
};

const _androidFlutterTarget = {
  'arm': 'android-arm',
  'arm64': 'android-arm64',
  'amd64': 'android-x64',
};

const _hostPlatform = {
  'linux': 'linux',
  'macos': 'macos',
  'windows': 'windows',
};

Future<void> main(List<String> args) async {
  final parser = createSetupArgParser();

  if (args.contains('--help') || args.contains('-h')) {
    _showHelp(parser);
    exit(0);
  }

  final results = parser.parse(args);
  final rest = results.rest;

  final hostOs = Platform.operatingSystem;
  final host = _hostPlatform[hostOs];
  if (host == null) {
    stderr.writeln('Unsupported host platform: $hostOs');
    exit(1);
  }

  final platform = rest.isNotEmpty ? rest.first : host;

  if (platform != host && platform != 'android') {
    stderr.writeln(
      'Cannot build "$platform" on $hostOs. Allowed: $host, android',
    );
    _showHelp(parser);
    exit(1);
  }

  final env = results['env'] as String;
  final rootDir = Directory.current.path;
  final arch = _detectArch();
  final targets = _getTargets(platform, arch, results['targets']);
  final androidArch = results['arch'] as String?;
  final verbose = results['verbose'] as bool;

  final exitCode = await _package(
    platform,
    env,
    targets,
    rootDir,
    arch,
    androidArch: androidArch,
    verbose: verbose,
  );
  exit(exitCode);
}

ArgParser createSetupArgParser() {
  return ArgParser()
    ..addOption(
      'env',
      defaultsTo: 'pre',
      allowed: ['pre', 'stable'],
      help: 'Application environment',
    )
    ..addOption(
      'targets',
      valueHelp: 'exe,zip,dmg,apk,...',
      help: 'Package targets (default: all for platform)',
    )
    ..addOption(
      'arch',
      valueHelp: 'arm,arm64,amd64',
      allowed: ['arm', 'arm64', 'amd64'],
      help: 'Target architecture (Android only)',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Enable verbose Flutter build output',
    );
}

List<String> createFlutterBuildArgs({
  required String platform,
  required bool verbose,
}) {
  final flutterBuildArgs = <String>[
    if (verbose) 'verbose',
    'dart-define-from-file=env.json',
  ];
  if (platform == 'android') {
    flutterBuildArgs.add('split-per-abi');
  }
  return flutterBuildArgs;
}

String _getTargets(String platform, String arch, String? customTargets) {
  if (customTargets != null) return customTargets;
  if (platform == 'linux' && arch == 'amd64') return 'deb,appimage,rpm';
  return _allTargets[platform]!;
}

void _showHelp(ArgParser parser) {
  stderr.writeln('Usage: dart setup.dart [platform] [options]');
  stderr.writeln('Platform: current host platform (default) or android');
  stderr.writeln();
  stderr.writeln('Default package targets:');
  _allTargets.forEach((p, t) => stderr.writeln('  $p: $t'));
  stderr.writeln();
  stderr.writeln(parser.usage);
}

Future<int> _package(
  String platform,
  String env,
  String targets,
  String rootDir,
  String arch, {
  String? androidArch,
  required bool verbose,
}) async {
  String? coreSha256;
  if (platform == 'windows') {
    final coreBuild = await _buildGoCore(rootDir);
    if (coreBuild.exitCode != 0) return coreBuild.exitCode;
    coreSha256 = coreBuild.sha256;
  }

  final file = File(p.join(rootDir, 'env.json'));

  await file.writeAsString(
    jsonEncode({'APP_ENV': env, 'CORE_SHA256': ?coreSha256}),
  );

  final flutterBuildArgs = createFlutterBuildArgs(
    platform: platform,
    verbose: verbose,
  );
  final descriptionArgs = <String>[];
  if (platform != 'android') {
    descriptionArgs.addAll(['--description', arch]);
  }

  final dependencies = await _ensureDependencies(platform, arch, rootDir);
  if (dependencies.exitCode != 0) return dependencies.exitCode;

  final activateResult = await Process.run('dart', [
    'pub',
    'global',
    'activate',
    '-s',
    'git',
    'https://github.com/chen08209/flutter_distributor.git',
    '--git-ref',
    'FlClash',
    '--git-path',
    'packages/flutter_distributor',
  ]);
  if (activateResult.exitCode != 0) {
    stderr.write(activateResult.stderr);
    return activateResult.exitCode;
  }

  final process = await Process.start(
    'flutter_distributor',
    [
      'package',
      '--skip-clean',
      '--platform',
      platform,
      '--targets',
      targets,
      if (androidArch != null)
        '--build-target-platform=${_androidFlutterTarget[androidArch]!}',
      if (flutterBuildArgs.isNotEmpty)
        '--flutter-build-args=${flutterBuildArgs.join(',')}',
      ...descriptionArgs,
    ],
    includeParentEnvironment: true,
    environment: {
      'ANDROID_ARCH': ?androidArch,
      if (dependencies.executablePath != null)
        'PATH': prependExecutablePath(
          dependencies.executablePath!,
          Platform.environment['PATH'] ?? '',
        ),
    },
    runInShell: Platform.isWindows,
  );

  process.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  process.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });
  final exitCode = await process.exitCode;
  return exitCode;
}

Future<({int exitCode, String? sha256})> _buildGoCore(String rootDir) async {
  final buildToolDir = p.join(
    rootDir,
    'plugins',
    'setup',
    'buildkit',
    'build_tool',
  );
  final result = await Process.run('dart', [
    'run',
    'build_tool',
    'windows',
    '--root-dir',
    rootDir,
  ], workingDirectory: buildToolDir);
  if (result.exitCode != 0) {
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    return (exitCode: result.exitCode, sha256: null);
  }
  final shaFile = File(p.join(rootDir, 'core_sha256.json'));
  final coreFile = File(
    p.join(rootDir, 'libclash', 'windows', 'FlClashCore.exe'),
  );
  try {
    return (
      exitCode: 0,
      sha256: await validateCoreBuildHash(shaFile, coreFile),
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    return (exitCode: 1, sha256: null);
  }
}

Future<String> validateCoreBuildHash(File shaFile, File coreFile) async {
  final expected = readCoreSha256(shaFile);
  await verifyFileSha256(coreFile, expected);
  return expected;
}

String readCoreSha256(File shaFile) {
  if (!shaFile.existsSync()) {
    throw FormatException('Missing core hash file: ${shaFile.path}');
  }
  final content = jsonDecode(shaFile.readAsStringSync());
  if (content is! Map<String, dynamic>) {
    throw FormatException('Invalid core hash file: ${shaFile.path}');
  }
  final sha256 = content['CORE_SHA256'];
  if (sha256 is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256)) {
    throw FormatException('Invalid CORE_SHA256 in ${shaFile.path}');
  }
  return sha256.toLowerCase();
}

String _detectArch() {
  if (Platform.isWindows) {
    final pa = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'AMD64';
    return pa.toUpperCase() == 'ARM64' ? 'arm64' : 'amd64';
  }
  final result = Process.runSync('uname', ['-m']);
  final machine = (result.stdout as String).trim();
  if (machine == 'aarch64') return 'arm64';
  if (machine == 'x86_64') return 'amd64';
  return machine;
}

Future<bool> _hasCommand(String cmd) async {
  final which = Platform.isWindows ? 'where' : 'command';
  final args = Platform.isWindows ? [cmd] : ['-v', cmd];
  final result = await Process.run(which, args);
  return result.exitCode == 0;
}

Future<({int exitCode, String? executablePath})> _ensureDependencies(
  String platform,
  String arch,
  String rootDir,
) async {
  switch (platform) {
    case 'macos':
      return (exitCode: await _ensureMacosDependencies(), executablePath: null);
    case 'linux':
      return _ensureLinuxDependencies(arch, rootDir);
    default:
      return (exitCode: 0, executablePath: null);
  }
}

Future<int> _ensureMacosDependencies() async {
  if (await _hasCommand('appdmg')) {
    stdout.writeln('appdmg already installed, skipping.');
    return 0;
  }
  stdout.writeln('Installing appdmg (DMG creator)...');
  final result = await Process.run('npm', ['install', '-g', 'appdmg']);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
  }
  return result.exitCode;
}

Future<({int exitCode, String? executablePath})> _ensureLinuxDependencies(
  String arch,
  String rootDir,
) async {
  final pkgGroups = <List<String>>[
    ['ninja-build', 'libgtk-3-dev'],
    ['libayatana-appindicator3-dev'],
    ['libkeybinder-3.0-dev'],
    ['locate'],
  ];
  if (arch == 'amd64') {
    pkgGroups.addAll([
      ['rpm', 'patchelf'],
      ['libfuse2'],
    ]);
  }

  final missingGroups = <List<String>>[];
  for (final group in pkgGroups) {
    final missingPkgs = <String>[];
    for (final pkg in group) {
      if (!await _isDebianPackageInstalled(pkg)) {
        missingPkgs.add(pkg);
      }
    }
    if (missingPkgs.isNotEmpty) {
      missingGroups.add(missingPkgs);
    }
  }

  if (missingGroups.isEmpty) {
    stdout.writeln('All Linux build dependencies already installed, skipping.');
  } else {
    stdout.writeln('Updating apt package lists...');
    final updateExit = await _runLinuxDependencyCommand([
      'apt-get',
      'update',
      '-y',
    ]);
    if (updateExit != 0) {
      stderr.writeln(
        'apt-get update exited with $updateExit; continuing and verifying '
        'dependency installation directly.',
      );
    }

    for (final missingPkgs in missingGroups) {
      stdout.writeln(
        'Installing Linux build dependencies: ${missingPkgs.join(', ')}...',
      );
      final installExit = await _installLinuxPackages(missingPkgs);
      if (installExit != 0) {
        return (exitCode: installExit, executablePath: null);
      }
    }
  }

  if (arch == 'amd64') {
    try {
      final appImageTool = await ensureAppImageTool(rootDir);
      return (exitCode: 0, executablePath: appImageTool);
    } on Exception catch (error) {
      stderr.writeln('Failed to prepare appimagetool: $error');
      return (exitCode: 1, executablePath: null);
    }
  }

  return (exitCode: 0, executablePath: null);
}

String appImageToolPath(String rootDir) => p.join(
  rootDir,
  'build',
  'toolcache',
  'appimagetool',
  appImageToolVersion,
  'appimagetool',
);

String prependExecutablePath(
  String executablePath,
  String currentPath, {
  String? separator,
}) {
  final directory = p.dirname(executablePath);
  if (currentPath.isEmpty) return directory;
  return '$directory${separator ?? (Platform.isWindows ? ';' : ':')}$currentPath';
}

Future<void> verifyFileSha256(File file, String expectedSha256) async {
  if (!await file.exists()) {
    throw FormatException('Missing downloaded file: ${file.path}');
  }
  final actual = (await sha256.bind(file.openRead()).first).toString();
  if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
    throw FormatException(
      'SHA-256 mismatch for ${file.path}: expected $expectedSha256, got $actual',
    );
  }
}

Future<void> downloadVerifiedFile({
  required Uri uri,
  required File target,
  required String expectedSha256,
  Duration connectionTimeout = _downloadConnectionTimeout,
  Duration headerTimeout = _downloadHeaderTimeout,
  Duration readTimeout = _downloadReadTimeout,
  Duration overallTimeout = _downloadOverallTimeout,
}) async {
  final client = HttpClient()..connectionTimeout = connectionTimeout;
  Future<void> download() async {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(
      headerTimeout,
      onTimeout: () {
        client.close(force: true);
        throw TimeoutException(
          'Download response headers timed out',
          headerTimeout,
        );
      },
    );
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Download returned HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    await target.parent.create(recursive: true);
    var readTimedOut = false;
    final body = response.timeout(
      readTimeout,
      onTimeout: (sink) {
        readTimedOut = true;
        client.close(force: true);
        sink
          ..addError(TimeoutException('Download stalled', readTimeout))
          ..close();
      },
    );
    try {
      await body.pipe(target.openWrite());
    } catch (_) {
      if (readTimedOut) {
        throw TimeoutException('Download stalled', readTimeout);
      }
      rethrow;
    }
    await verifyFileSha256(target, expectedSha256);
  }

  try {
    await download().timeout(
      overallTimeout,
      onTimeout: () {
        client.close(force: true);
        throw TimeoutException(
          'Download exceeded total timeout',
          overallTimeout,
        );
      },
    );
  } catch (_) {
    try {
      if (await target.exists()) await target.delete();
    } catch (_) {}
    rethrow;
  } finally {
    client.close(force: true);
  }
}

Future<String> ensureAppImageTool(String rootDir) async {
  final tool = File(appImageToolPath(rootDir));
  if (await tool.exists()) {
    try {
      await verifyFileSha256(tool, appImageToolSha256);
      await _makeExecutable(tool);
      stdout.writeln('Using cached appimagetool $appImageToolVersion.');
      return tool.path;
    } on FormatException {
      stderr.writeln(
        'Cached appimagetool failed verification; downloading again.',
      );
    }
  }

  await tool.parent.create(recursive: true);
  final temporary = File(
    '${tool.path}.download-$pid-${DateTime.now().microsecondsSinceEpoch}',
  );
  try {
    stdout.writeln('Downloading appimagetool $appImageToolVersion...');
    await downloadVerifiedFile(
      uri: Uri.parse(_appImageToolUrl),
      target: temporary,
      expectedSha256: appImageToolSha256,
    );
    await temporary.rename(tool.path);
    await _makeExecutable(tool);
    return tool.path;
  } finally {
    if (await temporary.exists()) {
      await temporary.delete();
    }
  }
}

Future<void> _makeExecutable(File file) async {
  final result = await Process.run('chmod', ['0755', file.path]);
  if (result.exitCode != 0) {
    throw ProcessException(
      'chmod',
      ['0755', file.path],
      result.stderr as String,
      result.exitCode,
    );
  }
}

Future<bool> _isDebianPackageInstalled(String pkg) async {
  final result = await Process.run('dpkg', ['-s', pkg]);
  return result.exitCode == 0 &&
      (result.stdout as String).contains('Status: install ok installed');
}

Future<bool> _areDebianPackagesInstalled(List<String> pkgs) async {
  for (final pkg in pkgs) {
    if (!await _isDebianPackageInstalled(pkg)) {
      return false;
    }
  }
  return true;
}

Future<int> _installLinuxPackages(List<String> pkgs) async {
  final exitCode = await _runLinuxDependencyCommand([
    'apt-get',
    'install',
    '-y',
    ...pkgs,
  ]);
  if (exitCode == 0) return 0;

  if (await _areDebianPackagesInstalled(pkgs)) {
    stderr.writeln(
      'apt-get install exited with $exitCode, but all requested packages are '
      'installed; continuing.',
    );
    return 0;
  }

  return exitCode;
}

Future<int> _runLinuxDependencyCommand(List<String> command) async {
  final sudoCommand = [
    'env',
    'DEBIAN_FRONTEND=noninteractive',
    'NEEDRESTART_MODE=a',
    ...command,
  ];
  stdout.writeln('exec: sudo ${sudoCommand.join(' ')}');
  final result = await Process.start('sudo', sudoCommand);
  result.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  result.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });
  final exitCode = await result.exitCode;
  if (exitCode != 0) {
    stderr.writeln('Linux dependency command failed with exit code $exitCode.');
  }
  return exitCode;
}
