import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/proxy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Linux proxy command builders', () {
    test('builds GNOME commands without duplicate port writes', () {
      final commands = Proxy.buildLinuxStartCommandsForTest(
        port: 7890,
        bypassDomain: ['localhost', '127.0.0.1'],
        desktop: 'GNOME',
        homeDir: '/home/user',
      );

      final portCommands = commands.where(
        (command) => command.args.length == 4 && command.args[2] == 'port',
      );
      final hostCommands = commands.where(
        (command) => command.args.length == 4 && command.args[2] == 'host',
      );

      expect(portCommands, hasLength(3));
      expect(hostCommands, hasLength(3));
      expect(
        commands
            .singleWhere(
              (command) =>
                  command.args.contains('org.gnome.system.proxy') &&
                  command.args.contains('ignore-hosts'),
            )
            .args
            .last,
        "['localhost', '127.0.0.1']",
      );
    });

    test('builds empty GNOME ignore-hosts as an empty list', () {
      final commands = Proxy.buildLinuxStartCommandsForTest(
        port: 7890,
        bypassDomain: const [],
        desktop: 'GNOME',
        homeDir: '/home/user',
      );

      expect(
        commands
            .singleWhere(
              (command) =>
                  command.args.contains('org.gnome.system.proxy') &&
                  command.args.contains('ignore-hosts'),
            )
            .args
            .last,
        '[]',
      );
    });

    test('builds MATE commands with MATE proxy schema', () {
      final commands = Proxy.buildLinuxStartCommandsForTest(
        port: 7890,
        bypassDomain: ['localhost'],
        desktop: 'MATE',
        homeDir: '/home/user',
      );

      expect(
        commands.any(
          (command) => command.args.contains('org.mate.system.proxy'),
        ),
        isTrue,
      );
      expect(
        commands.any(
          (command) => command.args.contains('org.gnome.system.proxy'),
        ),
        isFalse,
      );
    });

    test('falls back to GNOME gsettings commands for XFCE when available', () {
      final commands = Proxy.buildLinuxStartCommandsForTest(
        port: 7890,
        bypassDomain: ['localhost'],
        desktop: 'XFCE',
        homeDir: '/home/user',
        availableExecutables: {'gsettings'},
      );

      expect(commands.map((command) => command.executable).toSet(), {
        'gsettings',
      });
      expect(
        commands.any(
          (command) =>
              command.args.contains('org.gnome.system.proxy') &&
              command.args.contains('manual'),
        ),
        isTrue,
      );
    });

    test('prefers kwriteconfig6 for KDE when available', () {
      final commands = Proxy.buildLinuxStartCommandsForTest(
        port: 7890,
        bypassDomain: ['localhost'],
        desktop: 'KDE',
        homeDir: '/home/user',
        availableExecutables: {'kwriteconfig6', 'kwriteconfig5'},
      );

      expect(commands.map((command) => command.executable).toSet(), {
        'kwriteconfig6',
      });
    });

    test('falls back to kwriteconfig5 for KDE when kwriteconfig6 is missing',
        () {
      final commands = Proxy.buildLinuxStartCommandsForTest(
        port: 7890,
        bypassDomain: ['localhost'],
        desktop: 'KDE',
        homeDir: '/home/user',
        availableExecutables: {'kwriteconfig5'},
      );

      expect(commands.map((command) => command.executable).toSet(), {
        'kwriteconfig5',
      });
    });

    test('uses available backend for unknown desktops', () {
      final commands = Proxy.buildLinuxStartCommandsForTest(
        port: 7890,
        bypassDomain: ['localhost'],
        desktop: 'UNKNOWN',
        homeDir: '/home/user',
        availableExecutables: {'kwriteconfig5'},
      );

      expect(commands.map((command) => command.executable).toSet(), {
        'kwriteconfig5',
      });
    });
  });

  group('macOS proxy command builders', () {
    test(
        'filters networksetup service list headers, disabled services, and blanks',
        () {
      final services = Proxy.parseMacosNetworkServicesForTest('''
An asterisk (*) denotes that a network service is disabled.
Wi-Fi
*Thunderbolt Bridge
USB 10/100/1000 LAN

''');

      expect(services, ['Wi-Fi', 'USB 10/100/1000 LAN']);
    });

    test('passes bypass domains as separate networksetup arguments', () {
      final command = Proxy.buildMacosProxyBypassCommandForTest(
        'Wi-Fi',
        ['localhost', '127.0.0.1'],
      );

      expect(command.executable, '/usr/sbin/networksetup');
      expect(command.args, [
        '-setproxybypassdomains',
        'Wi-Fi',
        'localhost',
        '127.0.0.1',
      ]);
    });

    test('uses Empty when clearing bypass domains', () {
      final command = Proxy.buildMacosProxyBypassCommandForTest(
        'Wi-Fi',
        const [],
      );

      expect(command.args, ['-setproxybypassdomains', 'Wi-Fi', 'Empty']);
    });

    test('explicitly clears empty proxy server and PAC URL fields', () {
      final commands = Proxy.buildMacosRestoreCommandsForTest(
        'Wi-Fi',
        web: {'Server': '', 'Port': '0', 'Enabled': 'No'},
        auto: {'URL': '', 'Enabled': 'No'},
      );

      expect(
        commands.map((command) => command.args),
        containsAll([
          ['-setwebproxy', 'Wi-Fi', '', '0'],
          ['-setwebproxystate', 'Wi-Fi', 'off'],
          ['-setautoproxyurl', 'Wi-Fi', ''],
          ['-setautoproxystate', 'Wi-Fi', 'off'],
        ]),
      );
    });

    test('treats networksetup null output as restored empty fields', () {
      final original = _macosSnapshot(server: '', port: '0', autoUrl: '');
      final applied = _macosSnapshot(
        server: '127.0.0.1',
        port: '7890',
        autoUrl: 'http://127.0.0.1/proxy.pac',
      );
      final restored = _macosSnapshot(
        server: '(null)',
        port: '0',
        autoUrl: '(null)',
      );

      final before = Proxy.buildRestorePlanForTest(
        'macos',
        original,
        applied,
        applied,
      );
      final after = Proxy.buildRestorePlanForTest(
        'macos',
        original,
        applied,
        restored,
      );

      expect((before['services'] as List<Object?>), isNotEmpty);
      expect(after, {'services': <Object?>[]});
    });
  });

  group('Windows proxy session', () {
    const channel = MethodChannel('proxy');
    late Directory tempDirectory;
    late File sessionFile;
    late List<MethodCall> calls;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('proxy_test_');
      sessionFile = File('${tempDirectory.path}/session.json');
      calls = [];
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await tempDirectory.delete(recursive: true);
    });

    test(
      'captures original settings and restores only while still owned',
      () async {
        final original = _windowsSnapshot(
          flags: 5,
          server: 'user-proxy:8080',
          autoConfigUrl: 'https://example.test/proxy.pac',
        );
        final applied = _windowsSnapshot(
          flags: 3,
          server: '127.0.0.1:7890',
        );
        final captures = [original, applied, applied, original];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'CaptureProxy' => captures.removeAt(0),
            'StartProxy' || 'RestoreProxy' => true,
            String() => throw MissingPluginException(),
          };
        });

        final proxy = Proxy(sessionPath: sessionFile.path);
        await proxy.startProxy(7890, ['localhost']);
        expect(await sessionFile.exists(), isTrue);

        await proxy.stopProxy();

        expect(await sessionFile.exists(), isFalse);
        final restore = calls.singleWhere(
          (call) => call.method == 'RestoreProxy',
        );
        expect(restore.arguments, {
          'connections': [
            {
              'connection': null,
              'flags': 5,
              'proxyServer': 'user-proxy:8080',
              'autoConfigUrl': 'https://example.test/proxy.pac',
            },
          ],
        });
      },
      skip: !Platform.isWindows,
    );

    test(
      'does not overwrite settings changed by another application',
      () async {
        final original = _windowsSnapshot(flags: 5, server: 'before:8080');
        final applied = _windowsSnapshot(flags: 3, server: '127.0.0.1:7890');
        final changed = _windowsSnapshot(flags: 1, server: 'after:9090');
        await sessionFile.writeAsString(
          jsonEncode({
            'version': 1,
            'platform': 'windows',
            'original': original,
            'applied': applied,
          }),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'CaptureProxy') {
            return changed;
          }
          return true;
        });

        await Proxy(sessionPath: sessionFile.path).recoverProxy();

        expect(await sessionFile.exists(), isFalse);
        expect(calls.map((call) => call.method), ['CaptureProxy']);
      },
      skip: !Platform.isWindows,
    );

    test(
      'ignores unrelated RAS topology changes when building restore plan',
      () {
        final original = {
          'connections': [
            _windowsConnection(null, flags: 5, server: 'before:8080'),
            _windowsConnection('Work VPN', flags: 5, server: 'vpn:8080'),
          ],
        };
        final applied = {
          'connections': [
            _windowsConnection(null, flags: 3, server: '127.0.0.1:7890'),
            _windowsConnection(
              'Work VPN',
              flags: 3,
              server: '127.0.0.1:7890',
            ),
          ],
        };
        final current = {
          'connections': [
            _windowsConnection(null, flags: 3, server: '127.0.0.1:7890'),
            _windowsConnection(
              'New Dial-up',
              flags: 1,
              server: 'unrelated:3128',
            ),
          ],
        };

        final plan = Proxy.buildRestorePlanForTest(
          'windows',
          original,
          applied,
          current,
        );

        expect(plan, {
          'connections': [
            {
              'connection': null,
              'flags': 5,
              'proxyServer': 'before:8080',
            },
          ],
        });
      },
      skip: !Platform.isWindows,
    );

    test(
      'retains only failed owned fields and retries them later',
      () async {
        final original = {
          'connections': [
            _windowsConnection(null, flags: 5, server: 'before:8080'),
            _windowsConnection('Work VPN', flags: 5, server: 'vpn:8080'),
          ],
        };
        final applied = {
          'connections': [
            _windowsConnection(null, flags: 3, server: '127.0.0.1:7890'),
            _windowsConnection(
              'Work VPN',
              flags: 3,
              server: '127.0.0.1:7890',
            ),
          ],
        };
        final partiallyRestored = {
          'connections': [
            _windowsConnection(null, flags: 5, server: 'before:8080'),
            _windowsConnection(
              'Work VPN',
              flags: 3,
              server: '127.0.0.1:7890',
            ),
          ],
        };
        await sessionFile.writeAsString(
          jsonEncode({
            'version': 1,
            'platform': 'windows',
            'original': original,
            'applied': applied,
          }),
        );
        final captures = [
          applied,
          partiallyRestored,
          partiallyRestored,
          original,
        ];
        var restoreAttempt = 0;
        final restoreArguments = <Object?>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'CaptureProxy') {
            return captures.removeAt(0);
          }
          if (call.method == 'RestoreProxy') {
            restoreArguments.add(call.arguments);
            restoreAttempt++;
            return restoreAttempt > 1;
          }
          return true;
        });
        final proxy = Proxy(sessionPath: sessionFile.path);

        await expectLater(proxy.recoverProxy(), throwsA(isA<StateError>()));
        expect(await sessionFile.exists(), isTrue);
        await proxy.recoverProxy();

        expect(await sessionFile.exists(), isFalse);
        expect(
          restoreArguments[1],
          {
            'connections': [
              {
                'connection': 'Work VPN',
                'flags': 5,
                'proxyServer': 'vpn:8080',
              },
            ],
          },
        );
      },
      skip: !Platform.isWindows,
    );
  });
}

Map<String, Object?> _windowsSnapshot({
  required int flags,
  required String server,
  String autoConfigUrl = '',
}) {
  return {
    'connections': [
      _windowsConnection(
        null,
        flags: flags,
        server: server,
        autoConfigUrl: autoConfigUrl,
      ),
    ],
  };
}

Map<String, Object?> _windowsConnection(
  String? connection, {
  required int flags,
  required String server,
  String autoConfigUrl = '',
}) {
  return {
    'connection': connection,
    'flags': flags,
    'proxyServer': server,
    'proxyBypass': '<local>',
    'autoConfigUrl': autoConfigUrl,
  };
}

Map<String, Object?> _macosSnapshot({
  required String server,
  required String port,
  required String autoUrl,
}) {
  return {
    'services': [
      {
        'service': 'Wi-Fi',
        'web': {'Enabled': 'No', 'Server': server, 'Port': port},
        'secure': {'Enabled': 'No', 'Server': server, 'Port': port},
        'socks': {'Enabled': 'No', 'Server': server, 'Port': port},
        'auto': {'Enabled': 'No', 'URL': autoUrl},
        'bypass': <String>[],
      },
    ],
  };
}
