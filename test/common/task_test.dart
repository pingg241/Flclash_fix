import 'dart:io';

import 'package:archive/archive.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

MakeRealProfileState makeState({
  required Map<String, dynamic> rawConfig,
  bool appendSystemDns = false,
  PatchClashConfig patchConfig = const PatchClashConfig(),
}) {
  return MakeRealProfileState(
    profilesPath: 'profiles',
    profileId: 1,
    rawConfig: rawConfig,
    realPatchConfig: patchConfig,
    overrideDns: false,
    appendSystemDns: appendSystemDns,
    proxyGroups: const [],
    rules: const [],
    addedRules: const [],
    defaultUA: 'FlClash/Test',
  );
}

void main() {
  group('extractBackupArchive', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flclash-backup-test-');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    Future<File> writeArchive(Archive archive) async {
      final file = File('${tempDir.path}/backup.zip');
      await file.writeAsBytes(ZipEncoder().encode(archive));
      return file;
    }

    test('extracts an allowlisted backup entry', () async {
      final archive = Archive()
        ..addFile(ArchiveFile.string(configJsonName, '{"version":1}'));
      final file = await writeArchive(archive);
      final output = '${tempDir.path}/output';

      await extractBackupArchive(file.path, output);

      expect(
        await File('$output/$configJsonName').readAsString(),
        '{"version":1}',
      );
    });

    test('rejects traversal before writing any entry', () async {
      final archive = Archive()
        ..addFile(ArchiveFile.string(configJsonName, '{"version":1}'))
        ..addFile(ArchiveFile.string('../escaped.txt', 'owned'));
      final file = await writeArchive(archive);
      final output = '${tempDir.path}/output';

      await expectLater(
        extractBackupArchive(file.path, output),
        throwsFormatException,
      );

      expect(await Directory(output).exists(), isFalse);
      expect(await File('${tempDir.path}/escaped.txt').exists(), isFalse);
    });
  });

  group('makeRealProfileTask', () {
    test('custom overwrite can explicitly clear rules and groups', () async {
      final result = await makeRealProfileTask(
        makeState(
          rawConfig: {
            'rules': ['DOMAIN,original.example,DIRECT'],
            'proxy-groups': [
              {
                'name': 'original-group',
                'type': 'select',
                'proxies': ['DIRECT'],
              },
            ],
          },
        ),
        overrideProfileData: true,
      );

      expect(result.a, contains('rules: []'));
      expect(result.a, contains('proxy-groups: []'));
      expect(result.a, isNot(contains('original.example')));
      expect(result.a, isNot(contains('original-group')));
    });

    test('non-custom overwrite keeps source rules and groups', () async {
      final result = await makeRealProfileTask(
        makeState(
          rawConfig: {
            'rules': ['DOMAIN,original.example,DIRECT'],
            'proxy-groups': [
              {
                'name': 'original-group',
                'type': 'select',
                'proxies': ['DIRECT'],
              },
            ],
          },
        ),
      );

      expect(result.a, contains('DOMAIN,original.example,DIRECT'));
      expect(result.a, contains('original-group'));
    });

    test('only appends system DNS when enabled', () async {
      final withoutSystemDns = await makeRealProfileTask(
        makeState(
          rawConfig: {
            'dns': {'enable': false},
          },
        ),
      );
      final withSystemDns = await makeRealProfileTask(
        makeState(
          rawConfig: {
            'dns': {'enable': false},
          },
          appendSystemDns: true,
        ),
      );

      expect(withoutSystemDns.a, isNot(contains('system://')));
      expect(withSystemDns.a, contains('system://'));
    });

    test('full setup overrides subscription GEO update settings', () async {
      final result = await makeRealProfileTask(
        makeState(
          rawConfig: {'geo-auto-update': true, 'geo-update-interval': 168},
          patchConfig: const PatchClashConfig(
            geoAutoUpdate: false,
            geoUpdateInterval: 0,
          ),
        ),
      );

      expect(result.a, contains('geo-auto-update: false'));
      expect(result.a, contains('geo-update-interval: 0'));
    });

    test('full setup fingerprint includes valid GEO update settings', () async {
      final daily = await makeRealProfileTask(
        makeState(
          rawConfig: const {},
          patchConfig: const PatchClashConfig(
            geoAutoUpdate: true,
            geoUpdateInterval: 24,
          ),
        ),
      );
      final weekly = await makeRealProfileTask(
        makeState(
          rawConfig: const {},
          patchConfig: const PatchClashConfig(
            geoAutoUpdate: true,
            geoUpdateInterval: 168,
          ),
        ),
      );

      expect(weekly.a, contains('geo-auto-update: true'));
      expect(weekly.a, contains('geo-update-interval: 168'));
      expect(weekly.b, isNot(daily.b));
    });
  });
}
