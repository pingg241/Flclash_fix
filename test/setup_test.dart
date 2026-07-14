import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../setup.dart' as setup;

void main() {
  group('setup.dart', () {
    test('parses -v as verbose mode', () {
      final results = setup.createSetupArgParser().parse(['android', '-v']);

      expect(results['verbose'], isTrue);
      expect(results.rest, ['android']);
    });

    test('omits verbose from flutter build args by default', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        verbose: false,
      );

      expect(args, ['dart-define-from-file=env.json', 'split-per-abi']);
    });

    test('adds verbose to flutter build args with -v', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        verbose: true,
      );

      expect(args, [
        'verbose',
        'dart-define-from-file=env.json',
        'split-per-abi',
      ]);
    });

    group('core hash', () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('flclash_setup_test_');
      });

      tearDown(() {
        tempDir.deleteSync(recursive: true);
      });

      test('accepts a complete SHA-256 value', () {
        final file = File('${tempDir.path}${Platform.pathSeparator}core.json')
          ..writeAsStringSync('{"CORE_SHA256":"${'A' * 64}"}');

        expect(setup.readCoreSha256(file), 'a' * 64);
      });

      test('rejects a missing hash file', () {
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}missing.json',
        );

        expect(() => setup.readCoreSha256(file), throwsFormatException);
      });

      test('rejects a malformed or incomplete hash', () {
        final file = File('${tempDir.path}${Platform.pathSeparator}core.json')
          ..writeAsStringSync('{"CORE_SHA256":"abc"}');

        expect(() => setup.readCoreSha256(file), throwsFormatException);
      });

      test('rejects a stale hash that does not match the built core', () async {
        final core = File('${tempDir.path}${Platform.pathSeparator}core.exe')
          ..writeAsStringSync('current core');
        final hash = File('${tempDir.path}${Platform.pathSeparator}core.json')
          ..writeAsStringSync('{"CORE_SHA256":"${'0' * 64}"}');

        await expectLater(
          setup.validateCoreBuildHash(hash, core),
          throwsFormatException,
        );
      });

      test('accepts a hash matching the built core', () async {
        final core = File('${tempDir.path}${Platform.pathSeparator}core.exe')
          ..writeAsStringSync('current core');
        final expected = sha256.convert(core.readAsBytesSync()).toString();
        final hash = File('${tempDir.path}${Platform.pathSeparator}core.json')
          ..writeAsStringSync('{"CORE_SHA256":"$expected"}');

        expect(await setup.validateCoreBuildHash(hash, core), expected);
      });
    });

    group('appimagetool', () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('flclash_tool_test_');
      });

      tearDown(() {
        tempDir.deleteSync(recursive: true);
      });

      test('uses a versioned project-local cache path', () {
        expect(
          setup.appImageToolPath(tempDir.path),
          '${tempDir.path}${Platform.pathSeparator}build'
          '${Platform.pathSeparator}toolcache'
          '${Platform.pathSeparator}appimagetool'
          '${Platform.pathSeparator}${setup.appImageToolVersion}'
          '${Platform.pathSeparator}appimagetool',
        );
      });

      test('prepends only the tool directory to a child PATH', () {
        final executable = setup.appImageToolPath(tempDir.path);

        expect(
          setup.prependExecutablePath(executable, '/usr/bin', separator: ':'),
          '${File(executable).parent.path}:/usr/bin',
        );
      });

      test('rejects a downloaded file with the wrong checksum', () async {
        final file = File(setup.appImageToolPath(tempDir.path));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('not appimagetool');

        await expectLater(
          setup.verifyFileSha256(file, setup.appImageToolSha256),
          throwsFormatException,
        );
      });

      test('times out while waiting for response headers', () async {
        final release = Completer<void>();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          await release.future;
          await request.response.close();
        });
        addTearDown(() async {
          if (!release.isCompleted) release.complete();
          await server.close(force: true);
        });
        final target = File(
          '${tempDir.path}${Platform.pathSeparator}header-timeout',
        );

        await expectLater(
          setup.downloadVerifiedFile(
            uri: Uri.parse('http://127.0.0.1:${server.port}/tool'),
            target: target,
            expectedSha256: setup.appImageToolSha256,
            connectionTimeout: const Duration(seconds: 1),
            headerTimeout: const Duration(milliseconds: 50),
            readTimeout: const Duration(seconds: 1),
            overallTimeout: const Duration(seconds: 1),
          ),
          throwsA(isA<TimeoutException>()),
        );
        expect(await target.exists(), isFalse);
      });

      test('times out and removes a stalled partial download', () async {
        final release = Completer<void>();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          request.response.contentLength = 4;
          request.response.add([1]);
          await request.response.flush();
          await release.future;
          await request.response.close();
        });
        addTearDown(() async {
          if (!release.isCompleted) release.complete();
          await server.close(force: true);
        });
        final target = File(
          '${tempDir.path}${Platform.pathSeparator}read-timeout',
        );

        await expectLater(
          setup.downloadVerifiedFile(
            uri: Uri.parse('http://127.0.0.1:${server.port}/tool'),
            target: target,
            expectedSha256: setup.appImageToolSha256,
            connectionTimeout: const Duration(seconds: 1),
            headerTimeout: const Duration(seconds: 1),
            readTimeout: const Duration(milliseconds: 50),
            overallTimeout: const Duration(seconds: 1),
          ),
          throwsA(isA<TimeoutException>()),
        );
        expect(await target.exists(), isFalse);
      });
    });
  });
}
