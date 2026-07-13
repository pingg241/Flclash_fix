import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  test(
    'flush cancels debounce and immediately saves the latest config',
    () async {
      final saved = <Config>[];
      final container = ProviderContainer(
        overrides: [
          configSaverProvider.overrideWithValue((config) async {
            saved.add(config);
            return true;
          }),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(autoLaunch: true));
      final store = container.read(storeActionProvider.notifier);

      store.savePreferencesDebounce();
      await store.flushPreferences();

      expect(saved, hasLength(1));
      expect(saved.single.appSettingProps.autoLaunch, isTrue);
    },
  );

  test(
    'latest flush is serialized after an older in-flight snapshot',
    () async {
      final firstWrite = Completer<bool>();
      final saved = <Config>[];
      final container = ProviderContainer(
        overrides: [
          configSaverProvider.overrideWithValue((config) {
            saved.add(config);
            if (saved.length == 1) {
              return firstWrite.future;
            }
            return Future<bool>.value(true);
          }),
        ],
      );
      addTearDown(container.dispose);
      final store = container.read(storeActionProvider.notifier);

      final oldSave = store.savePreferences();
      await Future<void>.delayed(Duration.zero);
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(autoLaunch: true));
      final latestFlush = store.flushPreferences();

      expect(saved, hasLength(1));
      expect(saved.first.appSettingProps.autoLaunch, isFalse);
      firstWrite.complete(true);
      await Future.wait([oldSave, latestFlush]);

      expect(saved, hasLength(2));
      expect(saved.last.appSettingProps.autoLaunch, isTrue);
    },
  );

  test('clear restores profiles when staging scripts fails', () async {
    final temp = await Directory.systemTemp.createTemp('flclash-clear-');
    addTearDown(() => temp.safeDelete(recursive: true));
    final profiles = Directory('${temp.path}/profiles');
    final scripts = Directory('${temp.path}/scripts');
    await profiles.create();
    await scripts.create();
    await File('${profiles.path}/1.yaml').writeAsString('profile');
    await File('${scripts.path}/2.js').writeAsString('script');
    var preferencesCleared = false;
    var databaseCleared = false;
    final container = ProviderContainer(
      overrides: [
        storeClearOperationsProvider.overrideWithValue(
          StoreClearOperations(
            stageFiles: () => stageClearFilesAtomically(
              directoryPaths: [profiles.path, scripts.path],
              transactionRootPath: '${temp.path}/transaction',
              faultInjector: (index) {
                if (index == 1) {
                  throw StateError('script staging failed');
                }
              },
            ),
            createDatabaseSnapshot: (path) async {
              await File(path).writeAsString('database');
            },
            createPreferencesSnapshot: (_) async {},
            rollbackPreferencesSnapshot: (_) async {},
            finalizePreferencesSnapshot: (_) async {},
            clearPreferences: () async => preferencesCleared = true,
            clearDatabase: () async => databaseCleared = true,
            exitApplication: () async {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(storeActionProvider.notifier).handleClear(),
      throwsStateError,
    );

    expect(await File('${profiles.path}/1.yaml').readAsString(), 'profile');
    expect(await File('${scripts.path}/2.js').readAsString(), 'script');
    expect(preferencesCleared, isFalse);
    expect(databaseCleared, isFalse);
  });

  test(
    'database clear failure restores staged files and preferences',
    () async {
      final temp = await Directory.systemTemp.createTemp('flclash-clear-');
      addTearDown(() => temp.safeDelete(recursive: true));
      final profiles = Directory('${temp.path}/profiles');
      final scripts = Directory('${temp.path}/scripts');
      await profiles.create();
      await scripts.create();
      await File('${profiles.path}/1.yaml').writeAsString('profile');
      await File('${scripts.path}/2.js').writeAsString('script');
      var preferencesRolledBack = false;
      var preferencesFinalized = false;
      final container = ProviderContainer(
        overrides: [
          storeClearOperationsProvider.overrideWithValue(
            StoreClearOperations(
              stageFiles: () => stageClearFilesAtomically(
                directoryPaths: [profiles.path, scripts.path],
                transactionRootPath: '${temp.path}/transaction',
              ),
              createDatabaseSnapshot: (path) async {
                await File(path).writeAsString('database');
              },
              createPreferencesSnapshot: (_) async {},
              rollbackPreferencesSnapshot: (_) async {
                preferencesRolledBack = true;
              },
              finalizePreferencesSnapshot: (_) async {
                preferencesFinalized = true;
              },
              clearPreferences: () async {},
              clearDatabase: () async {
                throw StateError('database clear failed');
              },
              exitApplication: () async {},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(storeActionProvider.notifier).handleClear(),
        throwsStateError,
      );

      expect(preferencesRolledBack, isTrue);
      expect(preferencesFinalized, isTrue);
      expect(await File('${profiles.path}/1.yaml').readAsString(), 'profile');
      expect(await File('${scripts.path}/2.js').readAsString(), 'script');
    },
  );

  test('successful clear stages and removes profiles and scripts', () async {
    final temp = await Directory.systemTemp.createTemp('flclash-clear-');
    addTearDown(() => temp.safeDelete(recursive: true));
    final profiles = Directory('${temp.path}/profiles');
    final scripts = Directory('${temp.path}/scripts');
    await profiles.create();
    await scripts.create();
    await File('${profiles.path}/1.yaml').writeAsString('profile');
    await File('${scripts.path}/2.js').writeAsString('script');
    var preferencesCleared = false;
    var databaseCleared = false;
    var exited = false;
    final transactionPath = '${temp.path}/transaction';
    final container = ProviderContainer(
      overrides: [
        storeClearOperationsProvider.overrideWithValue(
          StoreClearOperations(
            stageFiles: () => stageClearFilesAtomically(
              directoryPaths: [profiles.path, scripts.path],
              transactionRootPath: transactionPath,
            ),
            createDatabaseSnapshot: (path) async {
              await File(path).writeAsString('database');
            },
            createPreferencesSnapshot: (_) async {},
            rollbackPreferencesSnapshot: (_) async {},
            finalizePreferencesSnapshot: (_) async {},
            clearPreferences: () async => preferencesCleared = true,
            clearDatabase: () async => databaseCleared = true,
            exitApplication: () async => exited = true,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(storeActionProvider.notifier).handleClear();

    expect(await profiles.exists(), isFalse);
    expect(await scripts.exists(), isFalse);
    expect(await Directory(transactionPath).exists(), isFalse);
    expect(preferencesCleared, isTrue);
    expect(databaseCleared, isTrue);
    expect(exited, isTrue);
  });
}
