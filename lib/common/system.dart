import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:ffi/ffi.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/input.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';

@visibleForTesting
bool hasSetIdBits(int mode) => mode & 0xC00 != 0;

typedef PrivateFileCreator =
    Future<void> Function(
      Directory directory,
      String name,
      List<int> contents,
      void Function() onCreated,
    );

@visibleForTesting
Future<File> createPrivateFileExclusive({
  required Directory directory,
  required String name,
  required List<int> contents,
  PrivateFileCreator? creator,
}) async {
  if (name.isEmpty || basename(name) != name) {
    throw ArgumentError.value(name, 'name', 'must be a single path segment');
  }
  final file = File(join(directory.path, name));
  var created = false;
  try {
    await (creator ?? _createPrivateFileNative)(
      directory,
      name,
      contents,
      () => created = true,
    );
    final entityType = await FileSystemEntity.type(
      file.path,
      followLinks: false,
    );
    if (entityType != FileSystemEntityType.file) {
      throw StateError('private file is not a regular file');
    }
    final stat = await file.stat();
    if (Platform.isLinux && stat.mode & 0x1FF != 0x180) {
      throw StateError('private file permissions are not 0600');
    }
    final canonicalFile = await file.resolveSymbolicLinks();
    final canonicalDirectory = await directory.resolveSymbolicLinks();
    if (dirname(canonicalFile) != canonicalDirectory) {
      throw StateError('private file escaped its directory');
    }
    return file;
  } catch (_) {
    if (created) {
      await file.safeDelete();
    }
    rethrow;
  }
}

Future<void> _createPrivateFileNative(
  Directory directory,
  String name,
  List<int> contents,
  void Function() onCreated,
) async {
  if (!Platform.isLinux) {
    final file = File(join(directory.path, name));
    await file.create(exclusive: true);
    onCreated();
    final handle = await file.open(mode: FileMode.writeOnly);
    try {
      await handle.writeFrom(contents);
      await handle.flush();
    } finally {
      await handle.close();
    }
    return;
  }
  final libc = DynamicLibrary.open('libc.so.6');
  final open = libc
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32, Uint32),
        int Function(Pointer<Utf8>, int, int)
      >('open');
  final openAt = libc
      .lookupFunction<
        Int32 Function(Int32, Pointer<Utf8>, Int32, Uint32),
        int Function(int, Pointer<Utf8>, int, int)
      >('openat');
  final write = libc
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Void>, IntPtr),
        int Function(int, Pointer<Void>, int)
      >('write');
  final fsync = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
    'fsync',
  );
  final close = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
    'close',
  );
  const oWriteOnly = 0x1;
  const oCreate = 0x40;
  const oExclusive = 0x80;
  const oDirectory = 0x10000;
  const oNoFollow = 0x20000;
  const oCloseOnExec = 0x80000;
  final directoryPath = directory.path.toNativeUtf8();
  final namePath = name.toNativeUtf8();
  final data = calloc<Uint8>(contents.length);
  data.asTypedList(contents.length).setAll(0, contents);
  var directoryFd = -1;
  var fileFd = -1;
  try {
    directoryFd = open(directoryPath, oDirectory | oNoFollow | oCloseOnExec, 0);
    if (directoryFd < 0) {
      throw StateError('failed to open private directory');
    }
    fileFd = openAt(
      directoryFd,
      namePath,
      oWriteOnly | oCreate | oExclusive | oNoFollow | oCloseOnExec,
      0x180,
    );
    if (fileFd < 0) {
      throw StateError('failed to exclusively create private file');
    }
    onCreated();
    var offset = 0;
    while (offset < contents.length) {
      final written = write(
        fileFd,
        (data + offset).cast<Void>(),
        contents.length - offset,
      );
      if (written <= 0) {
        throw StateError('failed to write private file');
      }
      offset += written;
    }
    if (fsync(fileFd) != 0) {
      throw StateError('failed to flush private file');
    }
  } finally {
    if (fileFd >= 0) {
      close(fileFd);
    }
    if (directoryFd >= 0) {
      close(directoryFd);
    }
    calloc.free(data);
    calloc.free(namePath);
    calloc.free(directoryPath);
  }
}

@visibleForTesting
Future<Directory> preparePrivateCoreDirectory(String homeDir) async {
  final canonicalHome = await Directory(homeDir).resolveSymbolicLinks();
  final directory = Directory(join(canonicalHome, '.tmp'));
  final type = await FileSystemEntity.type(directory.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    await directory.create();
  } else if (type != FileSystemEntityType.directory) {
    throw StateError('core private directory must not be a symlink');
  }
  final canonicalDirectory = await directory.resolveSymbolicLinks();
  if (dirname(canonicalDirectory) != canonicalHome) {
    throw StateError('core private directory escaped the trusted home');
  }
  final mode = await Process.run('/bin/chmod', ['700', canonicalDirectory]);
  final stat = await Directory(canonicalDirectory).stat();
  if (mode.exitCode != 0 || stat.mode & 0x1FF != 0x1C0) {
    throw StateError('failed to secure core private directory');
  }
  return Directory(canonicalDirectory);
}

String _randomPrivateFileName(String prefix, String suffix) {
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  return '$prefix${base64Url.encode(bytes).replaceAll('=', '')}$suffix';
}

@visibleForTesting
Future<T> transferCoreLaunchFileOwnership<T>({
  required Future<File> Function() createTokenFile,
  required Future<File> Function() createLaunchFile,
  required Future<T> Function(File tokenFile, File launchFile) start,
}) async {
  File? tokenFile;
  File? launchFile;
  var ownershipTransferred = false;
  try {
    tokenFile = await createTokenFile();
    launchFile = await createLaunchFile();
    final result = await start(tokenFile, launchFile);
    ownershipTransferred = true;
    return result;
  } finally {
    if (!ownershipTransferred) {
      await Future.wait([
        if (tokenFile != null) tokenFile.safeDelete(),
        if (launchFile != null) launchFile.safeDelete(),
      ]);
    }
  }
}

class CoreProcessHandle {
  final Process process;
  final Future<bool> Function()? _terminatePrivileged;
  final Future<void> Function()? _cleanupFiles;
  Future<void>? _cleanupFuture;

  CoreProcessHandle({
    required this.process,
    Future<bool> Function()? terminatePrivileged,
    Future<void> Function()? cleanupFiles,
  }) : _terminatePrivileged = terminatePrivileged,
       _cleanupFiles = cleanupFiles;

  Stream<List<int>> get stdout => process.stdout;

  Stream<List<int>> get stderr => process.stderr;

  Future<int> get exitCode => process.exitCode;

  bool get isPrivileged => _terminatePrivileged != null;

  Future<bool> terminate() async {
    final terminatePrivileged = _terminatePrivileged;
    if (terminatePrivileged != null) {
      return terminatePrivileged();
    }
    return process.kill();
  }

  Future<void> cleanup() {
    final cleanupFuture = _cleanupFuture;
    if (cleanupFuture != null) {
      return cleanupFuture;
    }
    final future = _cleanupFiles?.call() ?? Future<void>.value();
    _cleanupFuture = future;
    return future;
  }
}

class System {
  static System? _instance;

  bool _elevateCore = false;

  System._internal();

  factory System() {
    _instance ??= System._internal();
    return _instance!;
  }

  bool get isDesktop => isWindows || isMacOS || isLinux;

  bool get isWindows => Platform.isWindows;

  bool get isMacOS => Platform.isMacOS;

  bool get isAndroid => Platform.isAndroid;

  bool get isLinux => Platform.isLinux;

  Future<int> get version async {
    final deviceInfo = await DeviceInfoPlugin().deviceInfo;
    return switch (Platform.operatingSystem) {
      'macos' => (deviceInfo as MacOsDeviceInfo).majorVersion,
      'android' => (deviceInfo as AndroidDeviceInfo).version.sdkInt,
      'windows' => (deviceInfo as WindowsDeviceInfo).majorVersion,
      String() => 0,
    };
  }

  Future<bool> checkIsAdmin() async {
    if (system.isWindows) {
      final result = await windows?.checkService();
      return result == WindowsHelperServiceStatus.running;
    }
    if (system.isLinux && _elevateCore) {
      _elevateCore = await validateSudoCredential();
    }
    return system.isLinux && _elevateCore;
  }

  Future<AuthorizeCode> authorizeCore() async {
    if (system.isAndroid) {
      return AuthorizeCode.error;
    }
    final isAdmin = await checkIsAdmin();
    if (isAdmin) {
      return AuthorizeCode.none;
    }

    if (system.isWindows) {
      final result = await windows?.registerService();
      if (result == true) {
        return AuthorizeCode.success;
      }
      return AuthorizeCode.error;
    }

    if (system.isMacOS) {
      try {
        await coreController.prepareTunHelper();
      } catch (error) {
        commonPrint.log(
          'Failed to authorize the macOS TUN helper: $error',
          logLevel: LogLevel.error,
        );
        return AuthorizeCode.error;
      }
      // The core stays unprivileged; only the narrow TUN helper is authorized.
      return AuthorizeCode.none;
    } else if (Platform.isLinux) {
      final password = await globalState.showCommonDialog<String>(
        child: InputDialog(
          obscureText: true,
          title: currentAppLocalizations.pleaseInputAdminPassword,
          value: '',
          inputFormatters: TextInputLimits.limit(TextInputLimits.password),
        ),
      );
      if (password == null || password.isEmpty) {
        return AuthorizeCode.error;
      }
      final process = await Process.start('/usr/bin/sudo', [
        '-S',
        '-p',
        '',
        '-v',
      ]);
      process.stdout.listen((_) {});
      process.stderr.listen((_) {});
      process.stdin.writeln(password);
      await process.stdin.close();
      if (await process.exitCode != 0) {
        return AuthorizeCode.error;
      }
      _elevateCore = true;
      return AuthorizeCode.success;
    }
    return AuthorizeCode.error;
  }

  Future<CoreProcessHandle> startCoreProcess({
    required List<String> arguments,
    required Map<String, String> environment,
  }) async {
    if (system.isLinux && _elevateCore) {
      _elevateCore = await validateSudoCredential();
      if (!_elevateCore) {
        throw StateError('sudo authorization expired');
      }
    }
    if (!_elevateCore || !system.isLinux) {
      await _removeLegacySetIdBits();
      return CoreProcessHandle(
        process: await Process.start(
          appPath.corePath,
          arguments,
          environment: environment,
        ),
      );
    }
    final token = environment['FLCLASH_IPC_TOKEN'];
    if (token == null || token.length < 32 || arguments.length != 2) {
      throw ArgumentError('invalid privileged core launch parameters');
    }
    await _removeLegacySetIdBits();
    final launchNonce = base64Url.encode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    return transferCoreLaunchFileOwnership(
      createTokenFile: () => _createCoreTokenFile(arguments[1], token),
      createLaunchFile: () => _createCoreLaunchFile(arguments[1]),
      start: (tokenFile, launchFile) async {
        final originalUID = await _readOriginalUID();
        final privilegedEnvironment = Map<String, String>.from(environment)
          ..remove('FLCLASH_IPC_TOKEN')
          ..['FLCLASH_IPC_TOKEN_FILE'] = tokenFile.path
          ..['FLCLASH_LAUNCH_FILE'] = launchFile.path
          ..['FLCLASH_LAUNCH_NONCE'] = launchNonce
          ..['FLCLASH_ORIGINAL_UID'] = originalUID;
        final process = await Process.start('/usr/bin/sudo', [
          '-n',
          '--',
          '/usr/bin/env',
          'FLCLASH_IPC_TOKEN_FILE=${tokenFile.path}',
          'FLCLASH_LAUNCH_FILE=${launchFile.path}',
          'FLCLASH_LAUNCH_NONCE=$launchNonce',
          'FLCLASH_ORIGINAL_UID=$originalUID',
          appPath.corePath,
          ...arguments,
        ], environment: privilegedEnvironment);
        return CoreProcessHandle(
          process: process,
          terminatePrivileged: () => _terminatePrivilegedCore(
            launchFile: launchFile,
            launchNonce: launchNonce,
            originalUID: originalUID,
          ),
          cleanupFiles: () =>
              Future.wait([tokenFile.safeDelete(), launchFile.safeDelete()]),
        );
      },
    );
  }

  Future<File> _createCoreTokenFile(String homeDir, String token) async {
    final tokenDir = await preparePrivateCoreDirectory(homeDir);
    return createPrivateFileExclusive(
      directory: tokenDir,
      name: _randomPrivateFileName('ipc-', '.token'),
      contents: utf8.encode(token),
    );
  }

  Future<File> _createCoreLaunchFile(String homeDir) async {
    final launchDir = await preparePrivateCoreDirectory(homeDir);
    return createPrivateFileExclusive(
      directory: launchDir,
      name: _randomPrivateFileName('core-', '.launch'),
      contents: utf8.encode('{}'),
    );
  }

  Future<String> _readOriginalUID() async {
    final result = await Process.run('/usr/bin/id', ['-u']);
    final uid = result.stdout.toString().trim();
    if (result.exitCode != 0 || int.tryParse(uid) == null) {
      throw StateError('failed to resolve the current user identity');
    }
    return uid;
  }

  Future<void> _removeLegacySetIdBits() async {
    final coreFile = File(appPath.corePath);
    final stat = await coreFile.stat();
    if (!hasSetIdBits(stat.mode)) {
      return;
    }
    ProcessResult result;
    if (system.isLinux && _elevateCore) {
      result = await Process.run('/usr/bin/sudo', [
        '-n',
        '--',
        '/bin/chmod',
        'u-s,g-s',
        coreFile.path,
      ]);
    } else if (system.isMacOS) {
      const script = '''
set corePath to system attribute "FLCLASH_CORE_PATH"
do shell script "/bin/chmod u-s,g-s " & quoted form of corePath with administrator privileges
''';
      result = await Process.run(
        '/usr/bin/osascript',
        ['-e', script],
        environment: {'FLCLASH_CORE_PATH': coreFile.path},
      );
    } else {
      result = await Process.run('/bin/chmod', ['u-s,g-s', coreFile.path]);
    }
    final updated = await coreFile.stat();
    if (result.exitCode != 0 || hasSetIdBits(updated.mode)) {
      throw StateError('refusing to launch a legacy setuid core executable');
    }
  }

  Future<bool> _terminatePrivilegedCore({
    required File launchFile,
    required String launchNonce,
    required String originalUID,
  }) async {
    if (system.isLinux) {
      final result = await Process.run('/usr/bin/sudo', [
        '-n',
        '--',
        '/usr/bin/env',
        'FLCLASH_ORIGINAL_UID=$originalUID',
        appPath.corePath,
        '--terminate',
        launchFile.path,
        launchNonce,
      ]);
      return result.exitCode == 0;
    }
    return false;
  }

  Future<void> back() async {
    await app?.moveTaskToBack();
    await window?.hide();
  }

  Future<void> exit() async {
    if (system.isAndroid) {
      await SystemNavigator.pop();
    }
    await window?.close();
    window?.forceExit();
  }
}

@visibleForTesting
Future<bool> validateSudoCredential({
  Future<ProcessResult> Function(String executable, List<String> arguments)?
  runProcess,
}) async {
  try {
    final result = await (runProcess ?? Process.run)('/usr/bin/sudo', [
      '-n',
      '-v',
    ]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

final system = System();

class Windows {
  static Windows? _instance;
  late DynamicLibrary _shell32;

  Windows._internal() {
    _shell32 = DynamicLibrary.open('shell32.dll');
  }

  factory Windows() {
    _instance ??= Windows._internal();
    return _instance!;
  }

  bool runas(String command, String arguments) {
    final commandPtr = command.toNativeUtf16();
    final argumentsPtr = arguments.toNativeUtf16();
    final operationPtr = 'runas'.toNativeUtf16();

    final shellExecute = _shell32
        .lookupFunction<
          Int32 Function(
            Pointer<Utf16> hwnd,
            Pointer<Utf16> lpOperation,
            Pointer<Utf16> lpFile,
            Pointer<Utf16> lpParameters,
            Pointer<Utf16> lpDirectory,
            Int32 nShowCmd,
          ),
          int Function(
            Pointer<Utf16> hwnd,
            Pointer<Utf16> lpOperation,
            Pointer<Utf16> lpFile,
            Pointer<Utf16> lpParameters,
            Pointer<Utf16> lpDirectory,
            int nShowCmd,
          )
        >('ShellExecuteW');

    final result = shellExecute(
      nullptr,
      operationPtr,
      commandPtr,
      argumentsPtr,
      nullptr,
      1,
    );

    calloc.free(commandPtr);
    calloc.free(argumentsPtr);
    calloc.free(operationPtr);

    commonPrint.log(
      'windows runas: $command $arguments resultCode:$result',
      logLevel: LogLevel.warning,
    );

    if (result <= 32) {
      return false;
    }
    return true;
  }

  // Future<void> _killProcess(int port) async {
  //   final result = await Process.run('netstat', ['-ano']);
  //   final lines = result.stdout.toString().trim().split('\n');
  //   for (final line in lines) {
  //     if (!line.contains(':$port') || !line.contains('LISTENING')) {
  //       continue;
  //     }
  //     final parts = line.trim().split(RegExp(r'\s+'));
  //     final pid = int.tryParse(parts.last);
  //     if (pid != null) {
  //      await Process.run('taskkill', ['/PID', pid.toString(), '/F']);
  //     }
  //   }
  // }

  Future<WindowsHelperServiceStatus> checkService() async {
    // final qcResult = await Process.run('sc', ['qc', appHelperService]);
    // final qcOutput = qcResult.stdout.toString();
    // if (qcResult.exitCode != 0 || !qcOutput.contains(appPath.helperPath)) {
    //   return WindowsHelperServiceStatus.none;
    // }
    final result = await Process.run('sc', ['query', appHelperService]);
    if (result.exitCode != 0) {
      return WindowsHelperServiceStatus.none;
    }
    final output = result.stdout.toString();
    if (output.contains('RUNNING') && await request.pingHelper()) {
      return WindowsHelperServiceStatus.running;
    }
    return WindowsHelperServiceStatus.presence;
  }

  Future<bool> registerService() async {
    final status = await checkService();

    if (status == WindowsHelperServiceStatus.running) {
      return true;
    }

    final command = [
      '/c',
      if (status == WindowsHelperServiceStatus.presence) ...[
        'taskkill',
        '/F',
        '/IM',
        '$appHelperService.exe'
            ' & '
            'sc',
        'delete',
        appHelperService,
        '&',
      ],
      'sc',
      'create',
      appHelperService,
      'binPath= "${appPath.helperPath}"',
      'start= auto',
      '&&',
      'sc',
      'start',
      appHelperService,
    ].join(' ');

    final res = runas('cmd.exe', command);

    await Future.delayed(const Duration(milliseconds: 300));
    final retryStatus = await retry(
      task: checkService,
      maxAttempts: 5,
      retryIf: (status) => status != WindowsHelperServiceStatus.running,
      delay: const Duration(seconds: 1),
    );
    return res && retryStatus == WindowsHelperServiceStatus.running;
  }

  Future<bool> registerTask(String appName) async {
    final taskXml =
        '''
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Triggers>
    <LogonTrigger/>
  </Triggers>
  <Settings>
    <MultipleInstancesPolicy>Parallel</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>false</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>"${Platform.resolvedExecutable}"</Command>
    </Exec>
  </Actions>
</Task>''';
    final taskPath = join(await appPath.tempPath, 'task.xml');
    await File(taskPath).create(recursive: true);
    await File(
      taskPath,
    ).writeAsBytes(taskXml.encodeUtf16LeWithBom, flush: true);
    final commandLine = [
      '/Create',
      '/TN',
      appName,
      '/XML',
      '%s',
      '/F',
    ].join(' ');
    return runas('schtasks', commandLine.replaceFirst('%s', taskPath));
  }
}

final windows = system.isWindows ? Windows() : null;

@visibleForTesting
class DnsUpdateCoordinator {
  final Future<void> Function(bool restore) _update;
  Future<void> _tail = Future<void>.value();

  DnsUpdateCoordinator(this._update);

  Future<void> update(bool restore) {
    final operation = _tail.then((_) => _update(restore));
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }
}

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

@visibleForTesting
String? parseMacOSDefaultInterface(String output) {
  final match = RegExp(
    r'^\s*interface:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(output);
  return match?.group(1);
}

@visibleForTesting
String? parseMacOSNetworkServiceName(String output, String device) {
  final escapedDevice = RegExp.escape(device);
  final blocks = output.split(RegExp(r'\r?\n\s*\r?\n'));
  for (final block in blocks) {
    if (!RegExp('Device:\\s*$escapedDevice(?:\\s|\\))').hasMatch(block)) {
      continue;
    }
    final match = RegExp(
      r'^\s*\(\d+\)\s+(.+?)\s*$',
      multiLine: true,
    ).firstMatch(block);
    final name = match?.group(1)?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
  }
  return null;
}

class MacOS {
  static MacOS? _instance;

  List<String>? originDns;
  final ProcessRunner _runProcess;
  late final DnsUpdateCoordinator _dnsUpdates;

  MacOS._internal({ProcessRunner runProcess = Process.run})
    : _runProcess = runProcess {
    _dnsUpdates = DnsUpdateCoordinator(_updateDns);
  }

  @visibleForTesting
  MacOS.test({required ProcessRunner runProcess}) : _runProcess = runProcess {
    _dnsUpdates = DnsUpdateCoordinator(_updateDns);
  }

  factory MacOS() {
    _instance ??= MacOS._internal();
    return _instance!;
  }

  Future<String?> get defaultServiceName async {
    final result = await _runProcess('/sbin/route', ['-n', 'get', 'default']);
    final device = parseMacOSDefaultInterface(result.stdout.toString());
    if (device == null) {
      return null;
    }
    final serviceResult = await _runProcess('/usr/sbin/networksetup', [
      '-listnetworkserviceorder',
    ]);
    return parseMacOSNetworkServiceName(
      serviceResult.stdout.toString(),
      device,
    );
  }

  Future<List<String>?> get systemDns async {
    final deviceServiceName = await defaultServiceName;
    if (deviceServiceName == null) {
      return null;
    }
    final result = await _runProcess('/usr/sbin/networksetup', [
      '-getdnsservers',
      deviceServiceName,
    ]);
    final output = result.stdout.toString().trim();
    if (output.startsWith("There aren't any DNS Servers set on")) {
      originDns = [];
    } else {
      originDns = output.split('\n');
    }
    return originDns;
  }

  Future<void> updateDns(bool restore) => _dnsUpdates.update(restore);

  Future<void> _updateDns(bool restore) async {
    final serviceName = await defaultServiceName;
    if (serviceName == null) {
      return;
    }
    List<String>? nextDns;
    if (restore) {
      nextDns = originDns;
    } else {
      final originDns = await systemDns;
      if (originDns == null) {
        return;
      }
      const needAddDns = '223.5.5.5';
      if (originDns.contains(needAddDns)) {
        return;
      }
      nextDns = List.from(originDns)..add(needAddDns);
    }
    if (nextDns == null) {
      return;
    }
    await _runProcess('/usr/sbin/networksetup', [
      '-setdnsservers',
      serviceName,
      if (nextDns.isNotEmpty) ...nextDns,
      if (nextDns.isEmpty) 'Empty',
    ]);
  }
}

final macOS = system.isMacOS ? MacOS() : null;
