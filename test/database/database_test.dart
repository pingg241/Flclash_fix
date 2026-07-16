import 'dart:collection';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Database database;

  setUp(() async {
    database = Database(NativeDatabase.memory());
    await database.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await database.close();
  });

  Profile profile(int id) {
    return Profile(id: id, autoUpdateDuration: const Duration(hours: 1));
  }

  Rule rule(int id, String order) {
    return Rule(
      id: id,
      content: 'example$id.com',
      ruleTarget: 'DIRECT',
      order: order,
    );
  }

  test(
    'combined added rules preserve ascending priority within each scope',
    () async {
      await database.profiles.put(profile(100).toCompanion());
      await database.rulesDao.putGlobalRule(rule(1, 'a'));
      await database.rulesDao.putGlobalRule(rule(2, 'b'));
      await database.rulesDao.putProfileAddedRule(100, rule(3, 'a'));
      await database.rulesDao.putProfileAddedRule(100, rule(4, 'b'));

      final rules = await database.rulesDao.queryAddedRules(100).get();

      expect(rules.map((item) => item.id), [1, 2, 3, 4]);
    },
  );

  test('backup snapshot round-trips stable proxy selections', () async {
    final source = profile(100).copyWith(
      selectedMap: const {'group': 'same-name'},
      selectedStableMap: const {'group-key': 'provider-b-same-key'},
    );
    await database.profiles.put(source.toCompanion());
    final tempDir = await Directory.systemTemp.createTemp(
      'flclash-database-backup-',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final snapshotPath = '${tempDir.path}/snapshot.sqlite';

    await database.backupTo(snapshotPath);

    final snapshot = Database(NativeDatabase(File(snapshotPath)));
    addTearDown(snapshot.close);
    final restored = (await snapshot.profilesDao.query().get()).single;
    expect(restored.id, 100);
    expect(restored.selectedMap, source.selectedMap);
    expect(restored.selectedStableMap, source.selectedStableMap);
  });

  test('schema v3 preserves legacy selections and adds stable map', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'flclash-v2-migration-',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final file = File('${tempDir.path}/profiles.sqlite');
    final oldDatabase = Database(NativeDatabase(file));
    await oldDatabase.profiles.put(
      profile(
        100,
      ).copyWith(selectedMap: const {'group': 'legacy-proxy'}).toCompanion(),
    );
    await oldDatabase.customStatement(
      'ALTER TABLE profiles DROP COLUMN selected_stable_map',
    );
    await oldDatabase.customStatement('PRAGMA user_version = 2');
    await oldDatabase.close();

    final migrated = Database(NativeDatabase(file));
    addTearDown(migrated.close);
    final restored = await migrated.profilesDao.query().getSingle();

    expect(restored.selectedMap, {'group': 'legacy-proxy'});
    expect(restored.selectedStableMap, isEmpty);
  });

  test('clearAllData keeps the database connection reusable', () async {
    await database.profiles.put(profile(100).toCompanion());
    await database.scripts.put(
      Script(
        id: 200,
        label: 'script',
        lastUpdateTime: DateTime.fromMillisecondsSinceEpoch(0),
      ).toCompanion(),
    );
    await database.rulesDao.putProfileAddedRule(100, rule(300, 'a'));
    await database.setProfileCustomData(100, const [
      ProxyGroup(id: 400, name: 'group', type: GroupType.Selector),
    ], const []);

    await database.clearAllData();

    expect(await database.profilesDao.query().get(), isEmpty);
    expect(await database.scriptsDao.query().get(), isEmpty);
    expect(await database.select(database.rules).get(), isEmpty);
    expect(await database.select(database.profileRuleLinks).get(), isEmpty);
    expect(await database.select(database.proxyGroups).get(), isEmpty);
    await database.profiles.put(profile(500).toCompanion());
    expect((await database.profilesDao.query().get()).single.id, 500);
  });

  test(
    'override restore with an empty backup clears every restored table',
    () async {
      final script = Script(
        id: 200,
        label: 'script',
        lastUpdateTime: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final restoredRule = rule(300, 'a');
      const link = ProfileRuleLink(
        profileId: 100,
        ruleId: 300,
        scene: RuleScene.added,
      );
      const group = ProxyGroup(
        profileId: 100,
        id: 400,
        name: 'group',
        type: GroupType.Selector,
      );
      await database.restore(
        [profile(100)],
        [script],
        [restoredRule],
        const [link],
        const [group],
        isOverride: true,
      );

      await database.restore(
        const [],
        const [],
        const [],
        const [],
        const [],
        isOverride: true,
      );

      expect(await database.profilesDao.query().get(), isEmpty);
      expect(await database.scriptsDao.query().get(), isEmpty);
      expect(await database.select(database.rules).get(), isEmpty);
      expect(await database.select(database.profileRuleLinks).get(), isEmpty);
      expect(await database.select(database.proxyGroups).get(), isEmpty);
    },
  );

  test(
    'restore rolls back when a batch builder throws synchronously',
    () async {
      await expectLater(
        database.restore(
          [profile(100)],
          _ThrowingList<Script>(),
          const [],
          const [],
          const [],
          isOverride: true,
        ),
        throwsStateError,
      );

      expect(await database.profilesDao.query().get(), isEmpty);
    },
  );

  test(
    'empty custom data explicitly clears profile rules and groups',
    () async {
      await database.profiles.put(profile(100).toCompanion());
      await database.setProfileCustomData(
        100,
        const [ProxyGroup(id: 10, name: 'group', type: GroupType.Selector)],
        [rule(1, 'a')],
      );

      await database.setProfileCustomData(100, const [], const []);

      expect(await database.proxyGroupsDao.query(100).get(), isEmpty);
      expect(
        await database.rulesDao.queryProfileCustomRules(100).get(),
        isEmpty,
      );
    },
  );

  test(
    'renaming a proxy group updates dependent custom data atomically',
    () async {
      await database.profiles.put(profile(100).toCompanion());
      await database.setProfileCustomData(
        100,
        const [
          ProxyGroup(
            id: 10,
            name: 'old-name',
            type: GroupType.Selector,
            order: 'a',
          ),
          ProxyGroup(
            id: 11,
            name: 'parent',
            type: GroupType.Selector,
            proxies: ['old-name'],
            order: 'b',
          ),
        ],
        [rule(1, 'a').copyWith(ruleTarget: 'old-name')],
      );

      await database.putProxyGroup(
        100,
        const ProxyGroup(
          id: 10,
          name: 'new-name',
          type: GroupType.Selector,
          order: 'a',
        ),
        oldName: 'old-name',
      );

      final groups = await database.proxyGroupsDao.query(100).get();
      final rules = await database.rulesDao.queryProfileCustomRules(100).get();
      expect(groups.map((item) => item.name), ['new-name', 'parent']);
      expect(groups.last.proxies, ['new-name']);
      expect(rules.single.ruleTarget, 'new-name');
    },
  );

  test('putProxyGroup persists the supplied fractional order', () async {
    await database.profiles.put(profile(100).toCompanion());

    await database.putProxyGroup(
      100,
      const ProxyGroup(
        id: 10,
        name: 'group',
        type: GroupType.Selector,
        order: 'generated-order',
      ),
    );

    final group = await database.proxyGroupsDao.query(100).getSingle();
    expect(group.order, 'generated-order');
  });

  test(
    'unknown explicit rules survive database round-trip unchanged',
    () async {
      const value = 'FUTURE-RULE,payload,DIRECT,option';
      final parsed = Rule.parse(value, id: 42);

      await database.rulesDao.putGlobalRule(parsed);

      final restored = await database.rulesDao
          .queryGlobalAddedRules()
          .getSingle();
      expect(restored.ruleAction, RuleAction.UNKNOWN);
      expect(restored.rawValue, value);
    },
  );
}

class _ThrowingList<T> extends ListBase<T> {
  @override
  int get length => 1;

  @override
  set length(int value) => throw UnsupportedError('fixed');

  @override
  T operator [](int index) => throw StateError('iteration failed');

  @override
  void operator []=(int index, T value) => throw UnsupportedError('fixed');
}
