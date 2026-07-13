import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/system.dart';
import 'package:test/test.dart';

void main() {
  Future<void> testExclusiveCreator(
    Directory directory,
    String name,
    List<int> contents,
    void Function() onCreated,
  ) async {
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    await file.create(exclusive: true);
    onCreated();
    await file.writeAsBytes(contents, flush: true);
  }

  group('macOS DNS update queue', () {
    test('restore waits for a slow enable', () async {
      final enableStarted = Completer<void>();
      final releaseEnable = Completer<void>();
      final updates = <bool>[];
      final coordinator = DnsUpdateCoordinator((restore) async {
        updates.add(restore);
        if (!restore) {
          enableStarted.complete();
          await releaseEnable.future;
        }
      });

      final enable = coordinator.update(false);
      await enableStarted.future;
      final restore = coordinator.update(true);
      await Future<void>.delayed(Duration.zero);
      expect(updates, [false]);

      releaseEnable.complete();
      await Future.wait([enable, restore]);
      expect(updates, [false, true]);
    });

    test('continuous toggles execute in arrival order', () async {
      final updates = <bool>[];
      final coordinator = DnsUpdateCoordinator((restore) async {
        updates.add(restore);
      });

      await Future.wait([
        coordinator.update(false),
        coordinator.update(true),
        coordinator.update(false),
        coordinator.update(true),
      ]);

      expect(updates, [false, true, false, true]);
    });

    test('a failed enable does not break restore or later updates', () async {
      final updates = <bool>[];
      var first = true;
      final coordinator = DnsUpdateCoordinator((restore) async {
        updates.add(restore);
        if (first) {
          first = false;
          throw StateError('enable failed');
        }
      });

      final failed = coordinator.update(false);
      final restore = coordinator.update(true);
      final nextEnable = coordinator.update(false);

      await expectLater(failed, throwsStateError);
      await Future.wait([restore, nextEnable]);
      expect(updates, [false, true, false]);
    });
  });

  group('macOS network service discovery', () {
    const serviceOrder = '''
An asterisk (*) denotes that a network service is disabled.

(1) USB 10/100/1000 LAN
(Hardware Port: USB 10/100/1000 LAN, Device: en7)

(2) Office Wi-Fi Network
(Hardware Port: Wi-Fi, Device: en0)
''';

    test('parses interfaces and complete service names', () {
      expect(
        parseMacOSDefaultInterface('gateway: 192.0.2.1\ninterface: en0\n'),
        'en0',
      );
      expect(
        parseMacOSNetworkServiceName(serviceOrder, 'en0'),
        'Office Wi-Fi Network',
      );
      expect(parseMacOSNetworkServiceName(serviceOrder, 'en9'), isNull);
    });

    test(
      'uses absolute tools and passes service name as one argument',
      () async {
        final calls = <(String, List<String>)>[];
        final macOS = MacOS.test(
          runProcess: (executable, arguments) async {
            calls.add((executable, List<String>.of(arguments)));
            if (executable == '/sbin/route') {
              return ProcessResult(1, 0, 'interface: en0\n', '');
            }
            if (arguments.length == 1 &&
                arguments.first == '-listnetworkserviceorder') {
              return ProcessResult(2, 0, serviceOrder, '');
            }
            return ProcessResult(3, 0, '1.1.1.1\n', '');
          },
        );

        expect(await macOS.systemDns, ['1.1.1.1']);
        expect(calls.map((call) => call.$1), [
          '/sbin/route',
          '/usr/sbin/networksetup',
          '/usr/sbin/networksetup',
        ]);
        expect(calls[0].$2, ['-n', 'get', 'default']);
        expect(calls[1].$2, ['-listnetworkserviceorder']);
        expect(calls[2].$2, ['-getdnsservers', 'Office Wi-Fi Network']);
      },
    );
  });

  test('sudo validation uses non-interactive credential refresh', () async {
    String? executable;
    List<String>? arguments;

    final valid = await validateSudoCredential(
      runProcess: (command, args) async {
        executable = command;
        arguments = args;
        return ProcessResult(1, 0, '', '');
      },
    );

    expect(valid, isTrue);
    expect(executable, '/usr/bin/sudo');
    expect(arguments, ['-n', '-v']);
  });

  test(
    'sudo validation rejects expired credentials and spawn failures',
    () async {
      expect(
        await validateSudoCredential(
          runProcess: (_, _) async => ProcessResult(1, 1, '', 'expired'),
        ),
        isFalse,
      );
      expect(
        await validateSudoCredential(
          runProcess: (_, _) => throw const ProcessException('sudo', []),
        ),
        isFalse,
      );
    },
  );

  test('legacy setuid and setgid bits are detected', () {
    expect(hasSetIdBits(0x800), isTrue);
    expect(hasSetIdBits(0x400), isTrue);
    expect(hasSetIdBits(0xC00), isTrue);
    expect(hasSetIdBits(0x1ED), isFalse);
  });

  group('privileged core launch files', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('flclash-core-launch-');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('does not continue when token creation fails', () async {
      var launchCreated = false;
      var started = false;

      await expectLater(
        transferCoreLaunchFileOwnership<void>(
          createTokenFile: () => throw StateError('token creation failed'),
          createLaunchFile: () async {
            launchCreated = true;
            return File('${root.path}/launch');
          },
          start: (_, _) async {
            started = true;
          },
        ),
        throwsStateError,
      );

      expect(launchCreated, isFalse);
      expect(started, isFalse);
    });

    test('deletes token when launch file creation fails', () async {
      final token = File('${root.path}/token')..writeAsStringSync('secret');

      await expectLater(
        transferCoreLaunchFileOwnership<void>(
          createTokenFile: () async => token,
          createLaunchFile: () => throw StateError('launch creation failed'),
          start: (_, _) async {},
        ),
        throwsStateError,
      );

      expect(await token.exists(), isFalse);
    });

    test('deletes both files when process start fails', () async {
      final token = File('${root.path}/token')..writeAsStringSync('secret');
      final launch = File('${root.path}/launch')..writeAsStringSync('{}');

      await expectLater(
        transferCoreLaunchFileOwnership<void>(
          createTokenFile: () async => token,
          createLaunchFile: () async => launch,
          start: (_, _) => throw const ProcessException('sudo', []),
        ),
        throwsA(isA<ProcessException>()),
      );

      expect(await token.exists(), isFalse);
      expect(await launch.exists(), isFalse);
    });

    test('leaves successful launch files with the returned owner', () async {
      final token = File('${root.path}/token')..writeAsStringSync('secret');
      final launch = File('${root.path}/launch')..writeAsStringSync('{}');

      final cleanup =
          await transferCoreLaunchFileOwnership<Future<void> Function()>(
            createTokenFile: () async => token,
            createLaunchFile: () async => launch,
            start: (ownedToken, ownedLaunch) async {
              return () async {
                await Future.wait([ownedToken.delete(), ownedLaunch.delete()]);
              };
            },
          );

      expect(await token.exists(), isTrue);
      expect(await launch.exists(), isTrue);
      await cleanup();
      expect(await token.exists(), isFalse);
      expect(await launch.exists(), isFalse);
    });
  });

  group('exclusive private files', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('flclash-private-file-');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('rejects collisions without deleting the existing file', () async {
      final existing = File(
        '${root.path}${Platform.pathSeparator}collision.token',
      );
      await existing.writeAsString('original');

      await expectLater(
        createPrivateFileExclusive(
          directory: root,
          name: 'collision.token',
          contents: [1, 2, 3],
          creator: testExclusiveCreator,
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(await existing.readAsString(), 'original');
    });

    test('rejects a symlink occupying the target name', () async {
      final victim = File('${root.path}${Platform.pathSeparator}victim')
        ..writeAsStringSync('unchanged');
      final link = Link('${root.path}${Platform.pathSeparator}link.token');
      try {
        await link.create(victim.path);
      } on FileSystemException {
        markTestSkipped('symbolic links are unavailable on this host');
        return;
      }

      await expectLater(
        createPrivateFileExclusive(
          directory: root,
          name: 'link.token',
          contents: [4, 5, 6],
          creator: testExclusiveCreator,
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(await victim.readAsString(), 'unchanged');
      expect(await link.exists(), isTrue);
    });

    test('removes a newly created partial file after write failure', () async {
      final file = File('${root.path}${Platform.pathSeparator}partial.launch');

      await expectLater(
        createPrivateFileExclusive(
          directory: root,
          name: 'partial.launch',
          contents: [7, 8, 9],
          creator: (directory, name, contents, onCreated) async {
            await file.create(exclusive: true);
            onCreated();
            throw StateError('write failed');
          },
        ),
        throwsStateError,
      );

      expect(await file.exists(), isFalse);
    });

    test('rejects a symlink used as the private directory', () async {
      final target = Directory('${root.path}${Platform.pathSeparator}target')
        ..createSync();
      final home = Directory('${root.path}${Platform.pathSeparator}home')
        ..createSync();
      final link = Link('${home.path}${Platform.pathSeparator}.tmp');
      try {
        await link.create(target.path);
      } on FileSystemException {
        markTestSkipped('symbolic links are unavailable on this host');
        return;
      }

      await expectLater(
        preparePrivateCoreDirectory(home.path),
        throwsStateError,
      );
    });

    test('creates a canonical 0700 private directory on Linux', () async {
      if (!Platform.isLinux) {
        markTestSkipped('Linux permission semantics required');
        return;
      }
      final home = Directory('${root.path}${Platform.pathSeparator}home')
        ..createSync();

      final directory = await preparePrivateCoreDirectory(home.path);
      final stat = await directory.stat();

      expect(stat.mode & 0x1FF, 0x1C0);
      expect(
        await directory.resolveSymbolicLinks(),
        '${await home.resolveSymbolicLinks()}${Platform.pathSeparator}.tmp',
      );
    });
  });
}
