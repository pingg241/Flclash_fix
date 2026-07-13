part of '../state.dart';

@riverpod
GroupsState currentGroupsState(Ref ref) {
  final mode = ref.watch(
    patchClashConfigProvider.select((state) => state.mode),
  );
  // Prefer sharing group list references over deep-copying every proxy to
  // strip `now`. Extra rebuilds when core updates `now` are cheaper than the
  // previous full copy on every groupsProvider change.
  final groups = ref.watch(groupsProvider);
  return GroupsState(
    value: switch (mode) {
      Mode.direct => [],
      Mode.global => groups,
      Mode.rule =>
        groups
            .where((item) => item.hidden == false)
            .where((element) => element.name != GroupName.GLOBAL.name)
            .toList(),
    },
  );
}


