import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';

import 'proxy_platform_interface.dart';

enum ProxyTypes { http, https, socks }

typedef ProxyProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
});

typedef ProxyExecutableChecker = Future<bool> Function(String executable);

@immutable
class ProxyCommand {
  final String executable;
  final List<String> args;
  final bool runInShell;

  const ProxyCommand(
    this.executable,
    this.args, {
    this.runInShell = false,
  });
}

enum LinuxProxyBackend {
  gnome,
  mate,
  kde,
}

class Proxy extends ProxyPlatform {
  static String url = '127.0.0.1';
  static const _commandTimeout = Duration(seconds: 8);

  final ProxyProcessRunner _processRunner;
  final ProxyExecutableChecker _executableChecker;
  final _ProxySessionStore _sessionStore;
  Future<void> _pendingOperation = Future.value();

  Proxy({
    ProxyProcessRunner? processRunner,
    ProxyExecutableChecker? executableChecker,
    String? sessionPath,
  })  : _processRunner = processRunner ?? Process.run,
        _executableChecker = executableChecker ?? _hasExecutable,
        _sessionStore = _ProxySessionStore(sessionPath);

  @override
  Future<void> startProxy(
    int port, [
    List<String> bypassDomain = const [],
  ]) {
    return _serialize(() => _startProxy(port, bypassDomain));
  }

  Future<void> _startProxy(int port, List<String> bypassDomain) async {
    final existing = await _sessionStore.read();
    if (existing != null) {
      await _restoreSession(existing);
    }
    final original = await _captureProxy();
    try {
      await _applyProxy(port, bypassDomain);
      final applied = await _captureProxy();
      await _sessionStore.write({
        'version': 1,
        'platform': Platform.operatingSystem,
        'original': original,
        'applied': applied,
      });
    } catch (_) {
      final applied = await _captureProxy();
      final session = {
        'version': 1,
        'platform': Platform.operatingSystem,
        'original': original,
        'applied': applied,
      };
      await _sessionStore.write(session);
      await _restoreSession(session);
      rethrow;
    }
  }

  @override
  Future<void> stopProxy() => _serialize(_stopProxy);

  Future<void> _stopProxy() async {
    final session = await _sessionStore.read();
    if (session == null) {
      return;
    }
    await _restoreSession(session);
  }

  Future<void> _restoreSession(Map<String, Object?> session) async {
    if (session['platform'] != Platform.operatingSystem) {
      await _sessionStore.delete();
      return;
    }
    final original = _asStringMap(session['original']);
    final applied = _asStringMap(session['applied']);
    final current = await _captureProxy();
    final plan = _buildRestorePlan(
      Platform.operatingSystem,
      original,
      applied,
      current,
    );
    if (_isRestorePlanEmpty(Platform.operatingSystem, plan)) {
      await _sessionStore.delete();
      return;
    }

    Object? restoreError;
    StackTrace? restoreStackTrace;
    try {
      await _restoreProxy(plan);
    } catch (error, stackTrace) {
      restoreError = error;
      restoreStackTrace = stackTrace;
    }

    final afterRestore = await _captureProxy();
    final remaining = _buildRestorePlan(
      Platform.operatingSystem,
      original,
      applied,
      afterRestore,
    );
    if (_isRestorePlanEmpty(Platform.operatingSystem, remaining)) {
      await _sessionStore.delete();
    } else {
      await _sessionStore.write(session);
    }
    if (restoreError != null) {
      Error.throwWithStackTrace(restoreError, restoreStackTrace!);
    }
    if (!_isRestorePlanEmpty(Platform.operatingSystem, remaining)) {
      throw const ProxyOperationException([
        'system proxy settings remain unrestored',
      ]);
    }
  }

  Future<void> recoverProxy() => stopProxy();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _pendingOperation.then((_) => operation());
    _pendingOperation = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  Future<void> _applyProxy(int port, List<String> bypassDomain) async {
    switch (Platform.operatingSystem) {
      case 'macos':
        await _startProxyWithMacos(port, bypassDomain);
      case 'linux':
        await _startProxyWithLinux(port, bypassDomain);
      case 'windows':
        await ProxyPlatform.instance.startProxy(port, bypassDomain);
      default:
        throw UnsupportedError('system proxy is unsupported');
    }
  }

  Future<Map<String, Object?>> _captureProxy() async {
    return switch (Platform.operatingSystem) {
      'macos' => await _captureMacosProxy(),
      'linux' => await _captureLinuxProxy(),
      'windows' => await ProxyPlatform.instance.captureProxy(),
      String() => throw UnsupportedError('system proxy is unsupported'),
    };
  }

  Future<void> _restoreProxy(Map<String, Object?> snapshot) async {
    switch (Platform.operatingSystem) {
      case 'macos':
        await _restoreMacosProxy(snapshot);
      case 'linux':
        await _restoreLinuxProxy(snapshot);
      case 'windows':
        await ProxyPlatform.instance.restoreProxy(snapshot);
      default:
        throw UnsupportedError('system proxy is unsupported');
    }
  }

  Future<void> _startProxyWithLinux(int port, List<String> bypassDomain) async {
    final homeDir = Platform.environment['HOME'];
    if (homeDir == null || homeDir.isEmpty) {
      throw StateError('HOME is unavailable');
    }
    final commands = await _resolveLinuxStartCommands(
      port,
      bypassDomain,
      desktop: Platform.environment['XDG_CURRENT_DESKTOP'],
      homeDir: homeDir,
    );
    if (commands.isEmpty) {
      throw UnsupportedError('no supported Linux proxy backend');
    }
    await _runCommands(commands);
  }

  Future<void> _startProxyWithMacos(int port, List<String> bypassDomain) async {
    final devices = await _getNetworkDeviceListWithMacos();
    final commands = devices.expand(
      (dev) => _buildMacosStartCommands(
        dev,
        port,
        bypassDomain,
      ),
    );
    await _runCommands(commands);
  }

  Future<List<String>> _getNetworkDeviceListWithMacos() async {
    final res = await _run('/usr/sbin/networksetup', [
      '-listallnetworkservices',
    ]);
    if (res.exitCode != 0) {
      throw ProcessException(
        '/usr/sbin/networksetup',
        const ['-listallnetworkservices'],
        res.stderr.toString(),
        res.exitCode,
      );
    }
    return _parseMacosNetworkServices(res.stdout.toString());
  }

  Future<void> _runCommands(Iterable<ProxyCommand> commands) async {
    final failures = <String>[];
    for (final command in commands) {
      try {
        final result = await _run(
          command.executable,
          command.args,
          runInShell: command.runInShell,
        );
        if (result.exitCode != 0) {
          failures.add('${command.executable} exited ${result.exitCode}');
        }
      } on TimeoutException {
        failures.add('${command.executable} timed out');
      } catch (_) {
        failures.add('${command.executable} could not be started');
      }
    }
    if (failures.isNotEmpty) {
      throw ProxyOperationException(failures);
    }
  }

  Future<ProcessResult> _run(
    String executable,
    List<String> arguments, {
    bool runInShell = false,
  }) {
    return _processRunner(
      executable,
      arguments,
      runInShell: runInShell,
    ).timeout(_commandTimeout);
  }

  Future<List<ProxyCommand>> _resolveLinuxStartCommands(
    int port,
    List<String> bypassDomain, {
    required String? desktop,
    required String homeDir,
  }) async {
    final backend = await _resolveLinuxBackend(desktop);
    if (backend == null) {
      return [];
    }
    return _buildLinuxStartCommands(
      port: port,
      bypassDomain: bypassDomain,
      desktop: desktop,
      homeDir: homeDir,
      backend: backend,
      kdeConfigWriter: await _resolveKdeConfigWriter(),
    );
  }

  Future<Map<String, Object?>> _captureLinuxProxy() async {
    final homeDir = Platform.environment['HOME'];
    if (homeDir == null || homeDir.isEmpty) {
      throw StateError('HOME is unavailable');
    }
    final backend = await _resolveLinuxBackend(
      Platform.environment['XDG_CURRENT_DESKTOP'],
    );
    if (backend == null) {
      throw UnsupportedError('no supported Linux proxy backend');
    }
    if (backend == LinuxProxyBackend.kde) {
      return _captureKdeProxy(homeDir);
    }
    final prefix = backend == LinuxProxyBackend.mate
        ? 'org.mate.system.proxy'
        : 'org.gnome.system.proxy';
    final entries = <Map<String, String>>[];
    final keys = <(String, String)>[
      (prefix, 'mode'),
      (prefix, 'autoconfig-url'),
      (prefix, 'ignore-hosts'),
      for (final type in ProxyTypes.values) ...[
        ('$prefix.${type.name}', 'host'),
        ('$prefix.${type.name}', 'port'),
      ],
    ];
    for (final (schema, key) in keys) {
      final result = await _run('gsettings', ['get', schema, key]);
      if (result.exitCode != 0) {
        throw ProcessException(
          'gsettings',
          ['get', schema, key],
          result.stderr.toString(),
          result.exitCode,
        );
      }
      entries.add({
        'schema': schema,
        'key': key,
        'value': result.stdout.toString().trim(),
      });
    }
    return {'backend': backend.name, 'entries': entries};
  }

  Future<Map<String, Object?>> _captureKdeProxy(String homeDir) async {
    final writer = await _resolveKdeConfigWriter();
    final reader = writer.endsWith('6') ? 'kreadconfig6' : 'kreadconfig5';
    final file = join(homeDir, '.config', 'kioslaverc');
    const keys = [
      'ProxyType',
      'NoProxyFor',
      'httpProxy',
      'httpsProxy',
      'socksProxy',
    ];
    final values = <String, Object?>{};
    for (final key in keys) {
      final result = await _run(reader, [
        '--file',
        file,
        '--group',
        'Proxy Settings',
        '--key',
        key,
      ]);
      values[key] =
          result.exitCode == 0 ? result.stdout.toString().trim() : null;
    }
    return {
      'backend': LinuxProxyBackend.kde.name,
      'writer': writer,
      'file': file,
      'values': values,
    };
  }

  Future<void> _restoreLinuxProxy(Map<String, Object?> snapshot) async {
    final backend = snapshot['backend'];
    if (backend == LinuxProxyBackend.kde.name) {
      final writer = snapshot['writer'] as String;
      final file = snapshot['file'] as String;
      final values = _asStringMap(snapshot['values']);
      final commands = <ProxyCommand>[];
      for (final entry in values.entries) {
        commands.add(
          ProxyCommand(writer, [
            '--file',
            file,
            '--group',
            'Proxy Settings',
            '--key',
            entry.key,
            if (entry.value == null) '--delete' else entry.value.toString(),
          ]),
        );
      }
      await _runCommands(commands);
      return;
    }
    final entries = snapshot['entries'];
    if (entries is! List<Object?>) {
      throw const FormatException('invalid Linux proxy snapshot');
    }
    await _runCommands(
      entries.map((entry) {
        final value = _asStringMap(entry);
        return ProxyCommand('gsettings', [
          'set',
          value['schema'] as String,
          value['key'] as String,
          value['value'] as String,
        ]);
      }),
    );
  }

  Future<Map<String, Object?>> _captureMacosProxy() async {
    final services = await _getNetworkDeviceListWithMacos();
    final snapshots = <Map<String, Object?>>[];
    for (final service in services) {
      snapshots.add({
        'service': service,
        'web': await _readMacosProxySetting('-getwebproxy', service),
        'secure': await _readMacosProxySetting(
          '-getsecurewebproxy',
          service,
        ),
        'socks': await _readMacosProxySetting(
          '-getsocksfirewallproxy',
          service,
        ),
        'auto': await _readMacosProxySetting('-getautoproxyurl', service),
        'bypass': await _readMacosBypassDomains(service),
      });
    }
    return {'services': snapshots};
  }

  Future<Map<String, String>> _readMacosProxySetting(
    String operation,
    String service,
  ) async {
    final result = await _run('/usr/sbin/networksetup', [operation, service]);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/usr/sbin/networksetup',
        [operation, service],
        result.stderr.toString(),
        result.exitCode,
      );
    }
    return {
      for (final line in result.stdout.toString().split('\n'))
        if (line.contains(':'))
          line.substring(0, line.indexOf(':')).trim():
              line.substring(line.indexOf(':') + 1).trim(),
    };
  }

  Future<List<String>> _readMacosBypassDomains(String service) async {
    final result = await _run('/usr/sbin/networksetup', [
      '-getproxybypassdomains',
      service,
    ]);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/usr/sbin/networksetup',
        ['-getproxybypassdomains', service],
        result.stderr.toString(),
        result.exitCode,
      );
    }
    return result.stdout
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !line.startsWith('There aren'))
        .toList();
  }

  Future<void> _restoreMacosProxy(Map<String, Object?> snapshot) async {
    final services = snapshot['services'];
    if (services is! List<Object?>) {
      throw const FormatException('invalid macOS proxy snapshot');
    }
    final commands = <ProxyCommand>[];
    for (final item in services) {
      final service = _asStringMap(item);
      final name = service['service'] as String;
      commands.addAll(
        _buildMacosRestoreCommands(
          name,
          web: service.containsKey('web')
              ? _asStringMap(service['web'])
              : const {},
          secure: service.containsKey('secure')
              ? _asStringMap(service['secure'])
              : const {},
          socks: service.containsKey('socks')
              ? _asStringMap(service['socks'])
              : const {},
          auto: service.containsKey('auto')
              ? _asStringMap(service['auto'])
              : const {},
          bypass: service['bypass'] is List<Object?>
              ? (service['bypass'] as List<Object?>).cast<String>()
              : null,
        ),
      );
    }
    await _runCommands(commands);
  }

  static List<ProxyCommand> _buildMacosRestoreCommands(
    String service, {
    required Map<String, Object?> web,
    required Map<String, Object?> secure,
    required Map<String, Object?> socks,
    required Map<String, Object?> auto,
    required List<String>? bypass,
  }) {
    final commands = <ProxyCommand>[];
    void addProxy(
      String setter,
      String stateSetter,
      Map<String, Object?> value,
    ) {
      if (value.isEmpty) {
        return;
      }
      final server = value['Server']?.toString() ?? '';
      final port = value['Port']?.toString() ?? '0';
      if (value.containsKey('Server') || value.containsKey('Port')) {
        final restoredServer = server == '(null)' ? '' : server;
        final restoredPort = port == '(null)' || port.isEmpty ? '0' : port;
        commands.add(
          ProxyCommand(
            '/usr/sbin/networksetup',
            [setter, service, restoredServer, restoredPort],
          ),
        );
      }
      if (value.containsKey('Enabled')) {
        commands.add(
          ProxyCommand('/usr/sbin/networksetup', [
            stateSetter,
            service,
            value['Enabled'] == 'Yes' ? 'on' : 'off',
          ]),
        );
      }
    }

    addProxy('-setwebproxy', '-setwebproxystate', web);
    addProxy('-setsecurewebproxy', '-setsecurewebproxystate', secure);
    addProxy('-setsocksfirewallproxy', '-setsocksfirewallproxystate', socks);
    if (auto.containsKey('URL')) {
      final autoUrl = auto['URL']?.toString() ?? '';
      commands.add(
        ProxyCommand('/usr/sbin/networksetup', [
          '-setautoproxyurl',
          service,
          autoUrl == '(null)' ? '' : autoUrl,
        ]),
      );
    }
    if (auto.containsKey('Enabled')) {
      commands.add(
        ProxyCommand('/usr/sbin/networksetup', [
          '-setautoproxystate',
          service,
          auto['Enabled'] == 'Yes' ? 'on' : 'off',
        ]),
      );
    }
    if (bypass != null) {
      commands.add(_buildMacosProxyBypassCommand(service, bypass));
    }
    return commands;
  }

  Future<LinuxProxyBackend?> _resolveLinuxBackend(String? desktop) async {
    final preferredBackend = _preferredLinuxBackend(desktop);
    if (preferredBackend != null) {
      return preferredBackend;
    }
    for (final backend in LinuxProxyBackend.values) {
      if (await _isLinuxBackendAvailable(backend)) {
        return backend;
      }
    }
    return null;
  }

  Future<bool> _isLinuxBackendAvailable(LinuxProxyBackend backend) async {
    return switch (backend) {
      LinuxProxyBackend.gnome => await _executableChecker('gsettings'),
      LinuxProxyBackend.mate => await _executableChecker('gsettings'),
      LinuxProxyBackend.kde => await _executableChecker('kwriteconfig6') ||
          await _executableChecker('kwriteconfig5'),
    };
  }

  Future<String> _resolveKdeConfigWriter() async {
    if (await _executableChecker('kwriteconfig6')) {
      return 'kwriteconfig6';
    }
    return 'kwriteconfig5';
  }

  static Future<bool> _hasExecutable(String executable) async {
    final result = await Process.run('which', [executable]);
    return result.exitCode == 0;
  }

  static LinuxProxyBackend? _preferredLinuxBackend(String? desktop) {
    final desktops = _linuxDesktops(desktop);
    if (desktops.contains('KDE')) {
      return LinuxProxyBackend.kde;
    }
    if (desktops.contains('MATE')) {
      return LinuxProxyBackend.mate;
    }
    if (desktops.any(
      (desktop) =>
          const {'GNOME', 'CINNAMON', 'BUDGIE', 'UNITY'}.contains(desktop),
    )) {
      return LinuxProxyBackend.gnome;
    }
    return null;
  }

  static Set<String> _linuxDesktops(String? desktop) {
    if (desktop == null || desktop.isEmpty) {
      return {};
    }
    return desktop
        .split(':')
        .map((value) => value.trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  static List<ProxyCommand> _buildLinuxStartCommands({
    required int port,
    required List<String> bypassDomain,
    required String? desktop,
    required String homeDir,
    LinuxProxyBackend? backend,
    String kdeConfigWriter = 'kwriteconfig5',
    Set<String>? availableExecutables,
  }) {
    final resolvedBackend = backend ??
        _resolveLinuxBackendForBuild(
          desktop: desktop,
          availableExecutables: availableExecutables,
        );
    if (resolvedBackend == null) {
      return [];
    }
    return switch (resolvedBackend) {
      LinuxProxyBackend.gnome => _buildGSettingsStartCommands(
          port: port,
          bypassDomain: bypassDomain,
          schemaPrefix: 'org.gnome.system.proxy',
        ),
      LinuxProxyBackend.mate => _buildGSettingsStartCommands(
          port: port,
          bypassDomain: bypassDomain,
          schemaPrefix: 'org.mate.system.proxy',
        ),
      LinuxProxyBackend.kde => _buildKdeStartCommands(
          port: port,
          bypassDomain: bypassDomain,
          homeDir: homeDir,
          executable: _resolveKdeConfigWriterForBuild(
            availableExecutables,
            fallback: kdeConfigWriter,
          ),
        ),
    };
  }

  static LinuxProxyBackend? _resolveLinuxBackendForBuild({
    required String? desktop,
    required Set<String>? availableExecutables,
  }) {
    final preferredBackend = _preferredLinuxBackend(desktop);
    if (preferredBackend != null) {
      return preferredBackend;
    }
    if (availableExecutables == null) {
      return LinuxProxyBackend.gnome;
    }
    for (final backend in LinuxProxyBackend.values) {
      if (_isLinuxBackendAvailableForBuild(backend, availableExecutables)) {
        return backend;
      }
    }
    return null;
  }

  static bool _isLinuxBackendAvailableForBuild(
    LinuxProxyBackend backend,
    Set<String> availableExecutables,
  ) {
    return switch (backend) {
      LinuxProxyBackend.gnome => availableExecutables.contains('gsettings'),
      LinuxProxyBackend.mate => availableExecutables.contains('gsettings'),
      LinuxProxyBackend.kde => availableExecutables.contains('kwriteconfig6') ||
          availableExecutables.contains('kwriteconfig5'),
    };
  }

  static String _resolveKdeConfigWriterForBuild(
    Set<String>? availableExecutables, {
    required String fallback,
  }) {
    if (availableExecutables?.contains('kwriteconfig6') ?? false) {
      return 'kwriteconfig6';
    }
    if (availableExecutables?.contains('kwriteconfig5') ?? false) {
      return 'kwriteconfig5';
    }
    return fallback;
  }

  static List<ProxyCommand> _buildGSettingsStartCommands({
    required int port,
    required List<String> bypassDomain,
    required String schemaPrefix,
  }) {
    final commands = <ProxyCommand>[
      ProxyCommand(
        'gsettings',
        [
          'set',
          schemaPrefix,
          'ignore-hosts',
          _formatGSettingsStringList(bypassDomain),
        ],
      ),
    ];
    for (final type in ProxyTypes.values) {
      commands.addAll([
        ProxyCommand(
          'gsettings',
          [
            'set',
            '$schemaPrefix.${type.name}',
            'host',
            url,
          ],
        ),
        ProxyCommand(
          'gsettings',
          [
            'set',
            '$schemaPrefix.${type.name}',
            'port',
            '$port',
          ],
        ),
      ]);
    }
    commands.add(
      ProxyCommand(
        'gsettings',
        ['set', schemaPrefix, 'mode', 'manual'],
      ),
    );
    return commands;
  }

  static List<ProxyCommand> _buildKdeStartCommands({
    required int port,
    required List<String> bypassDomain,
    required String homeDir,
    required String executable,
  }) {
    final configDir = join(homeDir, '.config');
    final commands = <ProxyCommand>[];
    commands.addAll([
      ProxyCommand(
        executable,
        [
          '--file',
          join(configDir, 'kioslaverc'),
          '--group',
          'Proxy Settings',
          '--key',
          'ProxyType',
          '1',
        ],
      ),
      ProxyCommand(
        executable,
        [
          '--file',
          join(configDir, 'kioslaverc'),
          '--group',
          'Proxy Settings',
          '--key',
          'NoProxyFor',
          bypassDomain.join(','),
        ],
      ),
    ]);
    for (final type in ProxyTypes.values) {
      commands.add(
        ProxyCommand(
          executable,
          [
            '--file',
            join(configDir, 'kioslaverc'),
            '--group',
            'Proxy Settings',
            '--key',
            '${type.name}Proxy',
            '${type.name}://$url:$port',
          ],
        ),
      );
    }
    return commands;
  }

  static String _formatGSettingsStringList(List<String> values) {
    if (values.isEmpty) {
      return '[]';
    }
    final escaped = values.map((value) => "'${value.replaceAll("'", "\\'")}'");
    return '[${escaped.join(', ')}]';
  }

  static List<ProxyCommand> _buildMacosStartCommands(
    String dev,
    int port,
    List<String> bypassDomain,
  ) {
    return [
      ProxyCommand(
        '/usr/sbin/networksetup',
        ['-setautoproxystate', dev, 'off'],
      ),
      ProxyCommand(
        '/usr/sbin/networksetup',
        ['-setwebproxy', dev, url, '$port'],
      ),
      ProxyCommand(
        '/usr/sbin/networksetup',
        ['-setwebproxystate', dev, 'on'],
      ),
      ProxyCommand(
        '/usr/sbin/networksetup',
        ['-setsecurewebproxy', dev, url, '$port'],
      ),
      ProxyCommand(
        '/usr/sbin/networksetup',
        ['-setsecurewebproxystate', dev, 'on'],
      ),
      ProxyCommand(
        '/usr/sbin/networksetup',
        ['-setsocksfirewallproxy', dev, url, '$port'],
      ),
      ProxyCommand(
        '/usr/sbin/networksetup',
        ['-setsocksfirewallproxystate', dev, 'on'],
      ),
      _buildMacosProxyBypassCommand(dev, bypassDomain),
    ];
  }

  static ProxyCommand _buildMacosProxyBypassCommand(
    String dev,
    List<String> bypassDomain,
  ) {
    return ProxyCommand(
      '/usr/sbin/networksetup',
      [
        '-setproxybypassdomains',
        dev,
        if (bypassDomain.isEmpty) 'Empty' else ...bypassDomain,
      ],
    );
  }

  static List<String> _parseMacosNetworkServices(String stdout) {
    return stdout
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !line.startsWith('*'))
        .where((line) => !line.startsWith('An asterisk '))
        .toList();
  }

  static Map<String, Object?> _asStringMap(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('invalid proxy snapshot map');
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static Map<String, Object?> _buildRestorePlan(
    String platform,
    Map<String, Object?> original,
    Map<String, Object?> applied,
    Map<String, Object?> current,
  ) {
    return switch (platform) {
      'windows' => _buildWindowsRestorePlan(original, applied, current),
      'macos' => _buildMacosRestorePlan(original, applied, current),
      'linux' => _buildLinuxRestorePlan(original, applied, current),
      String() => <String, Object?>{},
    };
  }

  static Map<String, Object?> _buildWindowsRestorePlan(
    Map<String, Object?> original,
    Map<String, Object?> applied,
    Map<String, Object?> current,
  ) {
    final originals = _indexRecords(original['connections'], 'connection');
    final currents = _indexRecords(current['connections'], 'connection');
    final connections = <Map<String, Object?>>[];
    for (final appliedRecord
        in _records(applied['connections']).map(_asStringMap)) {
      final id = _recordId(appliedRecord['connection']);
      final originalRecord = originals[id];
      final currentRecord = currents[id];
      if (originalRecord == null || currentRecord == null) {
        continue;
      }
      final restore = <String, Object?>{
        'connection': originalRecord['connection'],
      };
      for (final field in const [
        'flags',
        'proxyServer',
        'proxyBypass',
        'autoConfigUrl',
      ]) {
        if (!_valuesEqual(originalRecord[field], appliedRecord[field]) &&
            _valuesEqual(currentRecord[field], appliedRecord[field])) {
          restore[field] = originalRecord[field];
        }
      }
      if (restore.length > 1) {
        connections.add(restore);
      }
    }
    return {'connections': connections};
  }

  static Map<String, Object?> _buildLinuxRestorePlan(
    Map<String, Object?> original,
    Map<String, Object?> applied,
    Map<String, Object?> current,
  ) {
    if (original['backend'] != applied['backend'] ||
        applied['backend'] != current['backend']) {
      return {'backend': applied['backend']};
    }
    if (applied['backend'] == LinuxProxyBackend.kde.name) {
      final originalValues = _asStringMap(original['values']);
      final appliedValues = _asStringMap(applied['values']);
      final currentValues = _asStringMap(current['values']);
      final values = <String, Object?>{};
      for (final entry in appliedValues.entries) {
        if (!_valuesEqual(originalValues[entry.key], entry.value) &&
            _valuesEqual(currentValues[entry.key], entry.value)) {
          values[entry.key] = originalValues[entry.key];
        }
      }
      return {
        'backend': LinuxProxyBackend.kde.name,
        'writer': original['writer'],
        'file': original['file'],
        'values': values,
      };
    }
    final originals = _indexLinuxEntries(original['entries']);
    final currents = _indexLinuxEntries(current['entries']);
    final entries = <Map<String, Object?>>[];
    for (final appliedEntry in _records(applied['entries']).map(_asStringMap)) {
      final id = '${appliedEntry['schema']}\u0000${appliedEntry['key']}';
      final originalEntry = originals[id];
      final currentEntry = currents[id];
      if (originalEntry == null || currentEntry == null) {
        continue;
      }
      if (!_valuesEqual(originalEntry['value'], appliedEntry['value']) &&
          _valuesEqual(currentEntry['value'], appliedEntry['value'])) {
        entries.add(originalEntry);
      }
    }
    return {'backend': applied['backend'], 'entries': entries};
  }

  static Map<String, Object?> _buildMacosRestorePlan(
    Map<String, Object?> original,
    Map<String, Object?> applied,
    Map<String, Object?> current,
  ) {
    final originals = _indexRecords(original['services'], 'service');
    final currents = _indexRecords(current['services'], 'service');
    final services = <Map<String, Object?>>[];
    for (final appliedService
        in _records(applied['services']).map(_asStringMap)) {
      final id = _recordId(appliedService['service']);
      final originalService = originals[id];
      final currentService = currents[id];
      if (originalService == null || currentService == null) {
        continue;
      }
      final restore = <String, Object?>{'service': originalService['service']};
      for (final group in const ['web', 'secure', 'socks']) {
        final originalGroup = _asStringMap(originalService[group]);
        final appliedGroup = _asStringMap(appliedService[group]);
        final currentGroup = _asStringMap(currentService[group]);
        final groupRestore = <String, Object?>{};
        final originalEndpoint = [
          _normalizeMacosEmptyValue(originalGroup['Server']),
          _normalizeMacosPort(originalGroup['Port']),
        ];
        final appliedEndpoint = [
          _normalizeMacosEmptyValue(appliedGroup['Server']),
          _normalizeMacosPort(appliedGroup['Port']),
        ];
        final currentEndpoint = [
          _normalizeMacosEmptyValue(currentGroup['Server']),
          _normalizeMacosPort(currentGroup['Port']),
        ];
        if (!_valuesEqual(originalEndpoint, appliedEndpoint) &&
            _valuesEqual(currentEndpoint, appliedEndpoint)) {
          groupRestore['Server'] = originalGroup['Server'];
          groupRestore['Port'] = originalGroup['Port'];
        }
        if (!_valuesEqual(originalGroup['Enabled'], appliedGroup['Enabled']) &&
            _valuesEqual(currentGroup['Enabled'], appliedGroup['Enabled'])) {
          groupRestore['Enabled'] = originalGroup['Enabled'];
        }
        if (groupRestore.isNotEmpty) {
          restore[group] = groupRestore;
        }
      }

      final originalAuto = _asStringMap(originalService['auto']);
      final appliedAuto = _asStringMap(appliedService['auto']);
      final currentAuto = _asStringMap(currentService['auto']);
      final autoRestore = <String, Object?>{};
      final originalUrl = _normalizeMacosEmptyValue(originalAuto['URL']);
      final appliedUrl = _normalizeMacosEmptyValue(appliedAuto['URL']);
      final currentUrl = _normalizeMacosEmptyValue(currentAuto['URL']);
      if (!_valuesEqual(originalUrl, appliedUrl) &&
          _valuesEqual(currentUrl, appliedUrl)) {
        autoRestore['URL'] = originalAuto['URL'];
      }
      if (!_valuesEqual(originalAuto['Enabled'], appliedAuto['Enabled']) &&
          _valuesEqual(currentAuto['Enabled'], appliedAuto['Enabled'])) {
        autoRestore['Enabled'] = originalAuto['Enabled'];
      }
      if (autoRestore.isNotEmpty) {
        restore['auto'] = autoRestore;
      }

      if (!_valuesEqual(originalService['bypass'], appliedService['bypass']) &&
          _valuesEqual(currentService['bypass'], appliedService['bypass'])) {
        restore['bypass'] = originalService['bypass'];
      }
      if (restore.length > 1) {
        services.add(restore);
      }
    }
    return {'services': services};
  }

  static List<Object?> _records(Object? value) {
    return value is List<Object?> ? value : const [];
  }

  static Map<String, Map<String, Object?>> _indexRecords(
    Object? value,
    String idField,
  ) {
    return {
      for (final record in _records(value).map(_asStringMap))
        _recordId(record[idField]): record,
    };
  }

  static Map<String, Map<String, Object?>> _indexLinuxEntries(Object? value) {
    return {
      for (final entry in _records(value).map(_asStringMap))
        '${entry['schema']}\u0000${entry['key']}': entry,
    };
  }

  static String _recordId(Object? value) => value?.toString() ?? '<default>';

  static String _normalizeMacosEmptyValue(Object? value) {
    final text = value?.toString() ?? '';
    return text == '(null)' ? '' : text;
  }

  static String _normalizeMacosPort(Object? value) {
    final text = _normalizeMacosEmptyValue(value);
    return text.isEmpty ? '0' : text;
  }

  static bool _isRestorePlanEmpty(
    String platform,
    Map<String, Object?> plan,
  ) {
    return switch (platform) {
      'windows' => _records(plan['connections']).isEmpty,
      'macos' => _records(plan['services']).isEmpty,
      'linux' when plan['backend'] == LinuxProxyBackend.kde.name =>
        _asStringMap(plan['values']).isEmpty,
      'linux' => _records(plan['entries']).isEmpty,
      String() => true,
    };
  }

  static bool _valuesEqual(Object? first, Object? second) {
    return _canonicalJson(first) == _canonicalJson(second);
  }

  static String _canonicalJson(Object? value) {
    Object? sort(Object? item) {
      if (item is Map<Object?, Object?>) {
        final entries = item.entries
            .map((entry) => MapEntry(entry.key.toString(), entry.value))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return {for (final entry in entries) entry.key: sort(entry.value)};
      }
      if (item is List<Object?>) {
        final values = item.map(sort).toList();
        if (values.every((value) => value is String || value is num)) {
          values.sort((a, b) => a.toString().compareTo(b.toString()));
        } else if (values.every((value) => value is Map<String, Object?>)) {
          values.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
        }
        return values;
      }
      return item;
    }

    return jsonEncode(sort(value));
  }

  @visibleForTesting
  static Map<String, Object?> buildRestorePlanForTest(
    String platform,
    Map<String, Object?> original,
    Map<String, Object?> applied,
    Map<String, Object?> current,
  ) {
    return _buildRestorePlan(platform, original, applied, current);
  }

  @visibleForTesting
  static List<ProxyCommand> buildMacosRestoreCommandsForTest(
    String service, {
    Map<String, Object?> web = const {},
    Map<String, Object?> secure = const {},
    Map<String, Object?> socks = const {},
    Map<String, Object?> auto = const {},
    List<String>? bypass,
  }) {
    return _buildMacosRestoreCommands(
      service,
      web: web,
      secure: secure,
      socks: socks,
      auto: auto,
      bypass: bypass,
    );
  }

  @visibleForTesting
  static List<ProxyCommand> buildLinuxStartCommandsForTest({
    required int port,
    required List<String> bypassDomain,
    required String? desktop,
    required String homeDir,
    Set<String>? availableExecutables,
  }) {
    return _buildLinuxStartCommands(
      port: port,
      bypassDomain: bypassDomain,
      desktop: desktop,
      homeDir: homeDir,
      availableExecutables: availableExecutables,
    );
  }

  @visibleForTesting
  static List<String> parseMacosNetworkServicesForTest(String stdout) {
    return _parseMacosNetworkServices(stdout);
  }

  @visibleForTesting
  static ProxyCommand buildMacosProxyBypassCommandForTest(
    String dev,
    List<String> bypassDomain,
  ) {
    return _buildMacosProxyBypassCommand(dev, bypassDomain);
  }
}

class _ProxySessionStore {
  final String? _overridePath;

  const _ProxySessionStore(this._overridePath);

  File get _file {
    if (_overridePath case final path?) {
      return File(path);
    }
    final environment = Platform.environment;
    final String baseDir;
    if (Platform.isWindows) {
      baseDir = environment['LOCALAPPDATA'] ?? environment['APPDATA'] ?? '.';
    } else if (Platform.isMacOS) {
      baseDir = join(
        environment['HOME'] ?? '.',
        'Library',
        'Application Support',
      );
    } else {
      baseDir = environment['XDG_STATE_HOME'] ??
          join(environment['HOME'] ?? '.', '.local', 'state');
    }
    return File(join(baseDir, 'FlClash', 'system_proxy_session.json'));
  }

  Future<Map<String, Object?>?> read() async {
    final file = await _recoverFile();
    if (!await file.exists()) {
      return null;
    }
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<Object?, Object?> || value['version'] != 1) {
        throw const FormatException('invalid system proxy session');
      }
      return value.map((key, value) => MapEntry(key.toString(), value));
    } catch (_) {
      await delete();
      rethrow;
    }
  }

  Future<void> write(Map<String, Object?> value) async {
    final file = _file;
    await file.parent.create(recursive: true);
    if (!Platform.isWindows) {
      final directoryMode = await Process.run('chmod', [
        '700',
        file.parent.path,
      ]).timeout(const Duration(seconds: 5));
      if (directoryMode.exitCode != 0) {
        throw StateError('failed to secure system proxy session directory');
      }
    }
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(value), flush: true);
    if (!Platform.isWindows) {
      final fileMode = await Process.run('chmod', [
        '600',
        temp.path,
      ]).timeout(const Duration(seconds: 5));
      if (fileMode.exitCode != 0) {
        await temp.delete();
        throw StateError('failed to secure system proxy session file');
      }
    }
    final backup = File('${file.path}.bak');
    if (await backup.exists()) {
      await backup.delete();
    }
    if (await file.exists()) {
      await file.rename(backup.path);
    }
    try {
      await temp.rename(file.path);
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
    if (await backup.exists()) {
      await backup.delete();
    }
  }

  Future<void> delete() async {
    final file = _file;
    if (await file.exists()) {
      await file.delete();
    }
    final temp = File('${file.path}.tmp');
    if (await temp.exists()) {
      await temp.delete();
    }
    final backup = File('${file.path}.bak');
    if (await backup.exists()) {
      await backup.delete();
    }
  }

  Future<File> _recoverFile() async {
    final file = _file;
    if (await file.exists()) {
      return file;
    }
    final backup = File('${file.path}.bak');
    if (await backup.exists()) {
      await file.parent.create(recursive: true);
      await backup.rename(file.path);
    }
    return file;
  }
}

class ProxyOperationException implements Exception {
  final List<String> failures;

  const ProxyOperationException(this.failures);

  @override
  String toString() => 'system proxy operation failed: ${failures.join(', ')}';
}
