import 'dart:async';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'generated/database.g.dart';

@visibleForTesting
bool asyncValueListShouldNotify<T>(
  AsyncValue<List<T>> previous,
  AsyncValue<List<T>> next,
  Equality<List<T>?> equality,
) {
  return previous.isLoading != next.isLoading ||
      previous.hasValue != next.hasValue ||
      previous.hasError != next.hasError ||
      previous.error != next.error ||
      previous.stackTrace != next.stackTrace ||
      !equality.equals(previous.value, next.value);
}

Future<void> withRollback<T>({
  required T snapshot,
  required T optimistic,
  required T Function() current,
  required FutureOr<void> Function() action,
  required void Function(T snapshot) rollback,
}) async {
  try {
    await action();
  } catch (e, s) {
    var isCurrent = false;
    try {
      isCurrent = identical(current(), optimistic);
    } catch (_) {
      // The provider may have been disposed while the write was in flight.
    }
    if (isCurrent) {
      rollback(snapshot);
    }
    Error.throwWithStackTrace(e, s);
  }
}

@riverpod
Stream<List<Profile>> profilesStream(Ref ref) {
  return database.profilesDao.query().watch();
}

@riverpod
Stream<List<Rule>> addedRulesStream(Ref ref, int profileId) {
  return database.rulesDao.queryAddedRules(profileId).watch();
}

@riverpod
Stream<int> customRulesCount(Ref ref, int profileId) {
  return database.rulesDao.profileCustomRulesCount(profileId).watchSingle();
}

@riverpod
Stream<int> proxyGroupsCount(Ref ref, int profileId) {
  return database.proxyGroupsDao.count(profileId).watchSingle();
}

@Riverpod(keepAlive: true)
class Profiles extends _$Profiles {
  @override
  List<Profile> build() {
    return ref.watch(profilesStreamProvider).value ?? [];
  }

  Future<void> put(Profile profile) async {
    final previous = List<Profile>.from(state);
    final newProfile = previous.optimizeLabel(profile);
    final next = previous.copyAndPut(
      newProfile,
      (item) => item.id == newProfile.id,
    );
    state = next;
    await withRollback(
      snapshot: previous,
      optimistic: next,
      current: () => state,
      action: () => database.profiles.put(newProfile.toCompanion()),
      rollback: (v) => state = v,
    );
  }

  Future<void> del(int id) async {
    final previous = List<Profile>.from(state);
    final next = previous.where((e) => e.id != id).toList();
    state = next;
    await withRollback(
      snapshot: previous,
      optimistic: next,
      current: () => state,
      action: () => database.profiles.remove((t) => t.id.equals(id)),
      rollback: (v) => state = v,
    );
  }

  Future<void> updateProfile(
    int profileId,
    Profile Function(Profile profile) builder,
  ) async {
    final index = state.indexWhere((element) => element.id == profileId);
    if (index == -1) return;
    final newProfile = builder(state[index]);
    final previous = List<Profile>.from(state);
    final next = List<Profile>.from(previous);
    next[index] = newProfile;
    state = next;
    await withRollback(
      snapshot: previous,
      optimistic: next,
      current: () => state,
      action: () => database.profiles.put(newProfile.toCompanion()),
      rollback: (v) => state = v,
    );
  }

  Future<void> setAndReorder(List<Profile> profiles) async {
    final previous = List<Profile>.from(state);
    final next = List<Profile>.from(profiles);
    state = next;
    await withRollback(
      snapshot: previous,
      optimistic: next,
      current: () => state,
      action: () => database.profilesDao.setAll(profiles),
      rollback: (v) => state = v,
    );
  }

  Future<void> reorder(List<Profile> profiles) async {
    final previous = List<Profile>.from(state);
    final next = List<Profile>.from(profiles);
    final needUpdate = <ProfilesCompanion>[];
    next.forEachIndexed((index, item) {
      if (item.order != index) {
        needUpdate.add(item.toCompanion(index));
      }
    });
    state = next;
    await withRollback(
      snapshot: previous,
      optimistic: next,
      current: () => state,
      action: () => database.profilesDao.putAll(needUpdate),
      rollback: (v) => state = v,
    );
  }

  @override
  bool updateShouldNotify(List<Profile> previous, List<Profile> next) {
    return !profileListEquality.equals(previous, next);
  }
}

@riverpod
class Scripts extends _$Scripts with AsyncNotifierMixin {
  @override
  Stream<List<Script>> build() {
    return database.scriptsDao.query().watch();
  }

  @override
  List<Script> get value => state.value ?? [];

  Future<void> put(Script script) async {
    final previous = List<Script>.from(value);
    final index = previous.indexWhere((item) => item.id == script.id);
    final next = List<Script>.from(previous);
    if (index != -1) {
      next[index] = script;
    } else {
      next.add(script);
    }
    value = next;
    await withRollback(
      snapshot: previous,
      optimistic: next,
      current: () => value,
      action: () => database.scripts.put(script.toCompanion()),
      rollback: (v) => value = v,
    );
  }

  Future<void> del(int id) async {
    final previous = List<Script>.from(value);
    final index = previous.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final next = List<Script>.from(previous);
    next.removeAt(index);
    value = next;
    await withRollback(
      snapshot: previous,
      optimistic: next,
      current: () => value,
      action: () => database.scripts.remove((t) => t.id.equals(id)),
      rollback: (v) => value = v,
    );
  }

  bool isExits(String label) {
    return value.indexWhere((item) => item.label == label) != -1;
  }

  @override
  bool updateShouldNotify(
    AsyncValue<List<Script>> previous,
    AsyncValue<List<Script>> next,
  ) {
    return asyncValueListShouldNotify(previous, next, scriptListEquality);
  }
}

@riverpod
Future<Script?> script(Ref ref, int? scriptId) async {
  final script = ref.watch(
    scriptsProvider.future.select((state) async {
      final scripts = await state;
      return scripts.get(scriptId);
    }),
  );
  return script;
}

@riverpod
class GlobalRules extends _$GlobalRules with AsyncNotifierMixin {
  @override
  Stream<List<Rule>> build() {
    return database.rulesDao.queryGlobalAddedRules().watch();
  }

  @override
  List<Rule> get value => state.value ?? [];

  @override
  bool updateShouldNotify(
    AsyncValue<List<Rule>> previous,
    AsyncValue<List<Rule>> next,
  ) {
    return asyncValueListShouldNotify(previous, next, ruleListEquality);
  }

  Future<void> delAll(Iterable<int> ruleIds) async {
    final previous = List<Rule>.from(value);
    final next = List<Rule>.from(
      previous.where((item) => !ruleIds.contains(item.id)),
    );
    value = next;
    await withRollback(
      snapshot: previous,
      optimistic: next,
      current: () => value,
      action: () => database.rulesDao.delRules(ruleIds),
      rollback: (v) => value = v,
    );
  }

  Future<void> put(Rule rule) async {
    final previous = List<Rule>.from(value);
    final newRule = rule.autoOrder(rule, null, previous.firstOrNull?.order);
    final next = previous.copyAndPut(newRule, (rule) => rule.id == newRule.id);
    value = next;
    await withRollback(
      snapshot: previous,
      optimistic: next,
      current: () => value,
      action: () => database.rulesDao.putGlobalRule(newRule),
      rollback: (v) => value = v,
    );
  }

  Future<void> order(int oldIndex, int newIndex) async {
    final previous = List<Rule>.from(value);
    final item = previous[oldIndex];
    final nextItems = previous.copyAndReorder(oldIndex, newIndex);
    value = nextItems;
    final preOrder = nextItems.safeGet(newIndex - 1)?.order;
    final nextOrder = nextItems.safeGet(newIndex + 1)?.order;
    final newOrder = indexing.generateKeyBetween(preOrder, nextOrder)!;
    await withRollback(
      snapshot: previous,
      optimistic: nextItems,
      current: () => value,
      action: () =>
          database.rulesDao.orderGlobalRule(ruleId: item.id, order: newOrder),
      rollback: (v) => value = v,
    );
  }
}

@riverpod
class ProfileAddedRules extends _$ProfileAddedRules with AsyncNotifierMixin {
  @override
  Stream<List<Rule>> build(int profileId) {
    return database.rulesDao.queryProfileAddedRules(profileId).watch();
  }

  @override
  List<Rule> get value => state.value ?? [];

  @override
  bool updateShouldNotify(
    AsyncValue<List<Rule>> previous,
    AsyncValue<List<Rule>> next,
  ) {
    return asyncValueListShouldNotify(previous, next, ruleListEquality);
  }

  Future<void> put(Rule rule) async {
    final previous = List<Rule>.from(value);
    final newRule = rule.autoOrder(rule, null, previous.firstOrNull?.order);
    final next = previous.copyAndPut(newRule, (rule) => rule.id == newRule.id);
    value = next;
    await withRollback(
      snapshot: previous,
      optimistic: next,
      current: () => value,
      action: () => database.rulesDao.putProfileAddedRule(profileId, newRule),
      rollback: (v) => value = v,
    );
  }

  Future<void> delAll(Iterable<int> ruleIds) async {
    final previous = List<Rule>.from(value);
    final next = List<Rule>.from(
      previous.where((item) => !ruleIds.contains(item.id)),
    );
    value = next;
    await withRollback(
      snapshot: previous,
      optimistic: next,
      current: () => value,
      action: () => database.rulesDao.delRules(ruleIds),
      rollback: (v) => value = v,
    );
  }

  Future<void> order(int oldIndex, int newIndex) async {
    final previous = List<Rule>.from(value);
    final item = previous[oldIndex];
    final nextItems = previous.copyAndReorder(oldIndex, newIndex);
    value = nextItems;
    final preOrder = nextItems.safeGet(newIndex - 1)?.order;
    final nextOrder = nextItems.safeGet(newIndex + 1)?.order;
    final newOrder = indexing.generateKeyBetween(preOrder, nextOrder)!;
    await withRollback(
      snapshot: previous,
      optimistic: nextItems,
      current: () => value,
      action: () => database.rulesDao.orderProfileAddedRule(
        profileId,
        ruleId: item.id,
        order: newOrder,
      ),
      rollback: (v) => value = v,
    );
  }
}

@riverpod
class ProfileCustomRules extends _$ProfileCustomRules with AsyncNotifierMixin {
  @override
  Stream<List<Rule>> build(int profileId) {
    return database.rulesDao.queryProfileCustomRules(profileId).watch();
  }

  @override
  List<Rule> get value => state.value ?? [];

  @override
  bool updateShouldNotify(
    AsyncValue<List<Rule>> previous,
    AsyncValue<List<Rule>> next,
  ) {
    return asyncValueListShouldNotify(previous, next, ruleListEquality);
  }

  Future<void> put(Rule rule) async {
    final previous = List<Rule>.from(value);
    final newRule = rule.autoOrder(rule, null, previous.firstOrNull?.order);
    final next = previous.copyAndPut(newRule, (rule) => rule.id == newRule.id);
    value = next;
    await withRollback(
      snapshot: previous,
      optimistic: next,
      current: () => value,
      action: () => database.rulesDao.putProfileCustomRule(profileId, newRule),
      rollback: (v) => value = v,
    );
  }

  Future<void> delAll(Iterable<int> ruleIds) async {
    final previous = List<Rule>.from(value);
    final next = List<Rule>.from(
      previous.where((item) => !ruleIds.contains(item.id)),
    );
    value = next;
    await withRollback(
      snapshot: previous,
      optimistic: next,
      current: () => value,
      action: () => database.rulesDao.delRules(ruleIds),
      rollback: (v) => value = v,
    );
  }

  Future<void> order(int oldIndex, int newIndex) async {
    final previous = List<Rule>.from(value);
    final item = previous[oldIndex];
    final nextItems = previous.copyAndReorder(oldIndex, newIndex);
    value = nextItems;
    final preOrder = nextItems.safeGet(newIndex - 1)?.order;
    final nextOrder = nextItems.safeGet(newIndex + 1)?.order;
    final newOrder = indexing.generateKeyBetween(preOrder, nextOrder)!;
    await withRollback(
      snapshot: previous,
      optimistic: nextItems,
      current: () => value,
      action: () => database.rulesDao.orderProfileCustomRule(
        profileId,
        ruleId: item.id,
        order: newOrder,
      ),
      rollback: (v) => value = v,
    );
  }
}

@riverpod
class ProxyGroups extends _$ProxyGroups with AsyncNotifierMixin {
  @override
  Stream<List<ProxyGroup>> build(int profileId) {
    return database.proxyGroupsDao.query(profileId).watch();
  }

  @override
  bool updateShouldNotify(
    AsyncValue<List<ProxyGroup>> previous,
    AsyncValue<List<ProxyGroup>> next,
  ) {
    return asyncValueListShouldNotify(previous, next, proxyGroupsEquality);
  }

  Future<void> del(String name) async {
    final previous = List<ProxyGroup>.from(value);
    final next = List<ProxyGroup>.from(
      previous.where((item) => item.name != name),
    );
    value = next;
    await withRollback(
      snapshot: previous,
      optimistic: next,
      current: () => value,
      action: () => database.proxyGroups.remove(
        (t) => t.profileId.equals(profileId) & t.name.equals(name),
      ),
      rollback: (v) => value = v,
    );
  }

  Future<bool> put(ProxyGroup proxyGroup) async {
    final previous = List<ProxyGroup>.from(value);
    final index = previous.indexWhere((item) => item.id == proxyGroup.id);
    final duplicateIndex = previous.indexWhere(
      (item) => item.name == proxyGroup.name,
    );
    if (duplicateIndex != -1 && duplicateIndex != index) {
      return false;
    }
    final oldName = index == -1 ? null : previous[index].name;
    final next = List<ProxyGroup>.from(previous);
    late final ProxyGroup persistedGroup;
    if (index != -1) {
      persistedGroup = proxyGroup;
      next[index] = persistedGroup;
    } else {
      persistedGroup = proxyGroup.copyWith(
        order: indexing.generateKeyBetween(previous.lastOrNull?.order, null),
      );
      next.add(persistedGroup);
    }
    final icon = persistedGroup.icon?.value;
    value = next;
    await withRollback(
      snapshot: previous,
      optimistic: next,
      current: () => value,
      action: () async {
        if (icon != null) {
          await database.iconRecordsDao.put(icon);
        }
        await database.putProxyGroup(
          profileId,
          persistedGroup,
          oldName: oldName,
        );
      },
      rollback: (v) => value = v,
    );
    return true;
  }

  Future<void> order(int oldIndex, int newIndex) async {
    final previous = List<ProxyGroup>.from(value);
    final item = previous[oldIndex];
    final nextItems = previous.copyAndReorder(oldIndex, newIndex);
    value = nextItems;
    final preOrder = nextItems.safeGet(newIndex - 1)?.order;
    final nextOrder = nextItems.safeGet(newIndex + 1)?.order;
    final newOrder = indexing.generateKeyBetween(preOrder, nextOrder)!;
    await withRollback(
      snapshot: previous,
      optimistic: nextItems,
      current: () => value,
      action: () => database.proxyGroupsDao.order(
        profileId,
        proxyGroup: item,
        order: newOrder,
      ),
      rollback: (v) => value = v,
    );
  }

  @override
  List<ProxyGroup> get value => state.value ?? [];
}

@riverpod
class ProfileDisabledRuleIds extends _$ProfileDisabledRuleIds
    with AsyncNotifierMixin {
  @override
  List<int> get value => state.value ?? [];

  @override
  Stream<List<int>> build(int profileId) {
    return database.rulesDao
        .queryProfileDisabledRules(profileId)
        .map((item) => item.id)
        .watch();
  }

  @override
  bool updateShouldNotify(
    AsyncValue<List<int>> previous,
    AsyncValue<List<int>> next,
  ) {
    return asyncValueListShouldNotify(previous, next, intListEquality);
  }

  void _put(int ruleId) {
    final newList = List<int>.from(value);
    final index = newList.indexWhere((item) => item == ruleId);
    if (index != -1) {
      newList[index] = ruleId;
    } else {
      newList.insert(0, ruleId);
    }
    value = newList;
  }

  Future<void> del(int ruleId) async {
    final previous = List<int>.from(value);
    final next = List<int>.from(previous.where((item) => item != ruleId));
    value = next;
    await withRollback(
      snapshot: previous,
      optimistic: next,
      current: () => value,
      action: () => database.rulesDao.delDisabledLink(profileId, ruleId),
      rollback: (v) => value = v,
    );
  }

  Future<void> put(int ruleId) async {
    final previous = List<int>.from(value);
    _put(ruleId);
    final next = value;
    await withRollback(
      snapshot: previous,
      optimistic: next,
      current: () => value,
      action: () => database.rulesDao.putDisabledLink(profileId, ruleId),
      rollback: (v) => value = v,
    );
  }
}
