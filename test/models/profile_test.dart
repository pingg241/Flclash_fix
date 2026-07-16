import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  group('SubscriptionInfo', () {
    test('parses subscription-userinfo header values', () {
      final info = SubscriptionInfo.formHString(
        'upload=10; download=20; total=100; expire=200',
      );

      expect(info.upload, 10);
      expect(info.download, 20);
      expect(info.total, 100);
      expect(info.expire, 200);
    });

    test('falls back to zero for null and invalid values', () {
      expect(SubscriptionInfo.formHString(null), const SubscriptionInfo());

      final info = SubscriptionInfo.formHString(
        'upload=bad; download=20; total=; expire=abc',
      );

      expect(info.upload, 0);
      expect(info.download, 20);
      expect(info.total, 0);
      expect(info.expire, 0);
    });

    test('ignores empty, malformed, and unknown fields', () {
      final info = SubscriptionInfo.formHString(
        '; malformed; =1; unknown; unknown=9; upload; download=; '
        'total=1=2; UPLOAD=7; expire=42; extra=a=b',
      );

      expect(info.upload, 7);
      expect(info.download, 0);
      expect(info.total, 0);
      expect(info.expire, 42);
    });

    test('splits fields only on the first equals sign', () {
      final info = SubscriptionInfo.formHString(
        'unknown=value=with=equals; total=100',
      );

      expect(info, const SubscriptionInfo(total: 100));
    });
  });

  group('ProfileExtension', () {
    test('derives type, label, filename, and updating key', () {
      const fileProfile = Profile(
        id: 7,
        autoUpdateDuration: defaultUpdateDuration,
      );
      const urlProfile = Profile(
        id: 8,
        label: 'Remote',
        url: 'https://example.com/profile.yaml',
        autoUpdate: true,
        autoUpdateDuration: defaultUpdateDuration,
      );

      expect(fileProfile.type, ProfileType.file);
      expect(fileProfile.realAutoUpdate, false);
      expect(fileProfile.realLabel, '7');
      expect(fileProfile.fileName, '7.yaml');
      expect(fileProfile.updatingKey, 'profile_7');

      expect(urlProfile.type, ProfileType.url);
      expect(urlProfile.realAutoUpdate, true);
      expect(urlProfile.realLabel, 'Remote');
    });
  });

  group('ProfilesExt', () {
    test('gets profile by id', () {
      const profiles = [
        Profile(id: 1, label: 'A', autoUpdateDuration: defaultUpdateDuration),
        Profile(id: 2, label: 'B', autoUpdateDuration: defaultUpdateDuration),
      ];

      expect(profiles.getProfile(2)?.label, 'B');
      expect(profiles.getProfile(3), isNull);
      expect(profiles.getProfile(null), isNull);
    });

    test('optimizes duplicate labels with incremented suffix', () {
      const profiles = [
        Profile(
          id: 1,
          label: 'Work',
          autoUpdateDuration: defaultUpdateDuration,
        ),
        Profile(
          id: 2,
          label: 'Work(1)',
          autoUpdateDuration: defaultUpdateDuration,
        ),
      ];
      const newProfile = Profile(
        id: 3,
        label: 'Work',
        autoUpdateDuration: defaultUpdateDuration,
      );

      expect(profiles.optimizeLabel(newProfile).label, 'Work(2)');
    });
  });

  group('ProfileRuleLinkExt', () {
    test('builds stable key from non-null parts', () {
      const link = ProfileRuleLink(
        profileId: 1,
        ruleId: 2,
        scene: RuleScene.added,
      );
      const globalLink = ProfileRuleLink(ruleId: 3);

      expect(link.key, '1_2_added');
      expect(globalLink.key, '3');
    });
  });

  group('blank profile files', () {
    late Directory home;
    late PathProviderPlatform originalPathProvider;

    setUpAll(() async {
      home = await Directory.systemTemp.createTemp('flclash-profile-test-');
      originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPathProvider(home.path);
    });

    setUp(() async {
      for (final name in [profilesDirectoryName, '.tmp']) {
        final directory = Directory(path.join(home.path, name));
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    });

    tearDownAll(() async {
      PathProviderPlatform.instance = originalPathProvider;
      await home.delete(recursive: true);
    });

    test(
      'URL import preserves the old file and cleans its empty temp',
      () async {
        const profile = Profile(
          id: 90,
          autoUpdateDuration: defaultUpdateDuration,
        );
        final destination = File(await appPath.getProfilePath('90'));
        await destination.parent.create(recursive: true);
        await destination.writeAsString('mixed-port: 7890');

        await expectLater(
          profile.saveFile(Uint8List(0)),
          throwsA(isA<FormatException>()),
        );

        expect(await destination.readAsString(), 'mixed-port: 7890');
        expect(
          await Directory(path.join(home.path, '.tmp')).list().toList(),
          isEmpty,
        );
      },
    );

    test(
      'file import rejects BOM plus whitespace without replacing old file',
      () async {
        const profile = Profile(
          id: 91,
          autoUpdateDuration: defaultUpdateDuration,
        );
        final destination = File(await appPath.getProfilePath('91'));
        await destination.parent.create(recursive: true);
        await destination.writeAsString('mixed-port: 7890');
        final source = File(path.join(home.path, 'blank-source.yaml'));
        await source.writeAsBytes([0xEF, 0xBB, 0xBF, 0x20, 0x09, 0x0D, 0x0A]);

        await expectLater(
          profile.saveFileWithPath(source.path),
          throwsA(isA<FormatException>()),
        );

        expect(await destination.readAsString(), 'mixed-port: 7890');
        expect(
          await Directory(path.join(home.path, '.tmp')).list().toList(),
          isEmpty,
        );
      },
    );

    test('BOM followed by YAML content is not blank', () async {
      final file = File(path.join(home.path, 'nonblank.yaml'));
      await file.writeAsBytes([0xEF, 0xBB, 0xBF, 0x7B, 0x7D]);

      expect(await isBlankYamlFile(file), isFalse);
    });

    test(
      'successful save waits for commit before cleaning the staged file',
      () async {
        const profile = Profile(
          id: 94,
          label: 'remote',
          autoUpdateDuration: defaultUpdateDuration,
        );
        final bytes = Uint8List.fromList('proxies: []\n'.codeUnits);
        final commitStarted = Completer<void>();
        final releaseCommit = Completer<void>();
        Profile? committedProfile;
        var cleanupStarted = false;

        final save = profile.saveFile(
          bytes,
          validateConfig: (stagedPath) async {
            expect(await File(stagedPath).readAsBytes(), bytes);
            return '';
          },
          onCommit: (updated) async {
            committedProfile = updated;
            commitStarted.complete();
            await releaseCommit.future;
          },
          tempFileCleaner: (file) async {
            cleanupStarted = true;
            await file.safeDelete();
          },
        );
        await commitStarted.future;

        expect(cleanupStarted, isFalse);
        releaseCommit.complete();
        final result = await save;

        final destination = File(await appPath.getProfilePath('94'));
        expect(await destination.readAsBytes(), bytes);
        expect(committedProfile, result);
        expect(result.lastUpdateDate, isNotNull);
        expect(cleanupStarted, isTrue);
        expect(
          await Directory(path.join(home.path, '.tmp')).list().toList(),
          isEmpty,
        );
      },
    );

    test('metadata commit is the file transaction commit point', () async {
      const profile = Profile(
        id: 92,
        label: 'updated',
        autoUpdateDuration: defaultUpdateDuration,
      );
      final destination = File(await appPath.getProfilePath('92'));
      await destination.parent.create(recursive: true);
      await destination.writeAsString('old: config');
      final staged = File(path.join(home.path, '.tmp', 'staged.yaml'));
      await staged.parent.create(recursive: true);
      await staged.writeAsString('new: config');
      var current = true;
      Profile? committedProfile;

      final result = await commitProfileFile(
        stagedFile: staged,
        destination: destination,
        updatedProfile: profile,
        shouldSave: () => current,
        onCommit: (updated) async {
          committedProfile = updated;
          current = false;
        },
      );

      expect(result, profile);
      expect(committedProfile, profile);
      expect(await destination.readAsString(), 'new: config');
      expect(
        await destination.parent
            .list()
            .where((entry) => entry.path.contains('.previous-'))
            .toList(),
        isEmpty,
      );
    });

    test(
      'backup cleanup failure does not report a committed update as failed',
      () async {
        const profile = Profile(
          id: 93,
          label: 'updated',
          autoUpdateDuration: defaultUpdateDuration,
        );
        final destination = File(await appPath.getProfilePath('93'));
        await destination.parent.create(recursive: true);
        await destination.writeAsString('old: config');
        final staged = File(path.join(home.path, '.tmp', 'staged.yaml'));
        await staged.parent.create(recursive: true);
        await staged.writeAsString('new: config');
        var cleanupCalls = 0;

        final result = await commitProfileFile(
          stagedFile: staged,
          destination: destination,
          updatedProfile: profile,
          onCommit: (_) async {},
          previousFileCleaner: (_) async {
            cleanupCalls++;
            throw const FileSystemException('cleanup failed');
          },
        );

        expect(result, profile);
        expect(cleanupCalls, 1);
        expect(await destination.readAsString(), 'new: config');
        expect(
          await destination.parent
              .list()
              .where((entry) => entry.path.contains('.previous-'))
              .length,
          1,
        );
      },
    );
  });
}

class _TestPathProvider extends PathProviderPlatform {
  final String path;

  _TestPathProvider(this.path);

  @override
  Future<String?> getApplicationCachePath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getDownloadsPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}
