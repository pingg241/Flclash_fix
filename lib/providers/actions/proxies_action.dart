import 'dart:async';
import 'dart:collection';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part '../generated/actions/proxies_action.g.dart';

typedef ExternalProviderUpdater = Future<String> Function(String name);
typedef ExternalProviderLoader =
    Future<ExternalProvider?> Function(String name);
typedef ProxyChangeExecutor =
    Future<String> Function(String groupName, String proxyName);
typedef ProxyConnectionRefresher = Future<void> Function();
typedef RuntimeProxyChangeExecutor =
    Future<String> Function(ChangeProxyParams params);
typedef ProxiesSnapshotLoader = Future<ProxiesData> Function();
typedef ProxyGroupsBuilder =
    Future<List<Group>> Function({
      required ProxiesData proxiesData,
      required ProxiesSortType sortType,
      required DelayMap delayMap,
      required Map<String, String> selectedMap,
      required String defaultTestUrl,
    });
typedef ProxyServerGeoLoader =
    Future<ProxyServerGeos> Function(ProxyServerGeoParams params);
typedef ProxyExitGeoLoader =
    Future<ProxyExitGeo> Function(ProbeProxyExitParams params);
typedef ProxyGeoClock = DateTime Function();

final externalProviderUpdaterProvider = Provider<ExternalProviderUpdater>(
  (_) =>
      (name) => coreController.updateExternalProvider(providerName: name),
);
final externalProviderLoaderProvider = Provider<ExternalProviderLoader>(
  (_) => coreController.getExternalProvider,
);
final proxyChangeExecutorProvider = Provider<ProxyChangeExecutor>(
  (_) =>
      (groupName, proxyName) async => await coreController.changeProxy(
        ChangeProxyParams(groupName: groupName, proxyName: proxyName),
      ),
);
final runtimeProxyChangeExecutorProvider = Provider<RuntimeProxyChangeExecutor>(
  (_) =>
      (params) async => await coreController.changeProxy(params),
);
final proxiesSnapshotLoaderProvider = Provider<ProxiesSnapshotLoader>(
  (_) => coreController.getProxies,
);
final proxyGroupsBuilderProvider = Provider<ProxyGroupsBuilder>(
  (_) =>
      ({
        required proxiesData,
        required sortType,
        required delayMap,
        required selectedMap,
        required defaultTestUrl,
      }) => coreController.buildProxiesGroups(
        proxiesData: proxiesData,
        sortType: sortType,
        delayMap: delayMap,
        selectedMap: selectedMap,
        defaultTestUrl: defaultTestUrl,
      ),
);
final proxyServerGeoLoaderProvider = Provider<ProxyServerGeoLoader>(
  (_) => coreController.getProxyServerGeos,
);
final proxyExitGeoLoaderProvider = Provider<ProxyExitGeoLoader>(
  (_) => coreController.probeProxyExit,
);
final proxyExitGeoTimeoutProvider = Provider<Duration>(
  (_) => const Duration(seconds: 10),
);
final proxyGeoClockProvider = Provider<ProxyGeoClock>((_) => DateTime.now);
final proxyConnectionRefresherProvider = Provider<ProxyConnectionRefresher>((
  ref,
) {
  return () async {
    if (ref.read(appSettingProvider).closeConnections) {
      await coreController.closeConnections();
    } else {
      await coreController.resetConnections();
    }
  };
});

const _serverGeoCacheLimit = 1024;
const _exitGeoCacheLimit = 256;
const _serverGeoCacheTtl = Duration(hours: 24);
const _exitGeoCacheTtl = Duration(minutes: 10);
const _exitGeoRetryDelay = Duration(minutes: 1);
const _serverGeoRetryDelay = Duration(minutes: 5);
const _serverGeoBatchSize = 512;

typedef _ServerGeoCacheKey = ({String stableKey, String serverHost});
typedef _ExitGeoCacheKey = ({String stableKey, int networkRevision});
typedef _ActiveProxySelection = ({String groupId, String memberId});
typedef _ResolvedProxySelection = ({
  ChangeProxyParams params,
  ProxyGroupSnapshot? group,
  ProxyNodeSnapshot? member,
});

class _TimedCacheValue<T> {
  final T value;
  final DateTime expiresAt;

  const _TimedCacheValue(this.value, this.expiresAt);

  bool isValid(DateTime now) => now.isBefore(expiresAt);
}

class _BoundedLruCache<K, V> {
  final int limit;
  final LinkedHashMap<K, _TimedCacheValue<V>> _values = LinkedHashMap();

  _BoundedLruCache(this.limit);

  V? get(K key, DateTime now) {
    final cached = _values.remove(key);
    if (cached == null) return null;
    if (!cached.isValid(now)) return null;
    _values[key] = cached;
    return cached.value;
  }

  MapEntry<K, V>? latestWhere(bool Function(K key) matches, DateTime now) {
    final keys = _values.keys.toList(growable: false).reversed;
    for (final key in keys) {
      if (!matches(key)) continue;
      final value = get(key, now);
      if (value != null) return MapEntry(key, value);
    }
    return null;
  }

  void set(K key, V value, DateTime expiresAt) {
    _values.remove(key);
    _values[key] = _TimedCacheValue(value, expiresAt);
    while (_values.length > limit) {
      _values.remove(_values.keys.first);
    }
  }

  void clear() {
    _values.clear();
  }
}

@Riverpod(keepAlive: true)
class ProxiesAction extends _$ProxiesAction {
  final Map<String, Future<String>> _providerUpdates = {};
  final Map<String, int> _providerGenerations = {};
  final Map<({int? profileId, String groupName}), int> _selectionGenerations =
      {};
  final _serverGeoCache = _BoundedLruCache<_ServerGeoCacheKey, ProxyServerGeo>(
    _serverGeoCacheLimit,
  );
  final _exitGeoCache = _BoundedLruCache<_ExitGeoCacheKey, ProxyExitGeo>(
    _exitGeoCacheLimit,
  );
  final Map<String, DateTime> _serverGeoRetryAfter = {};
  final Map<String, DateTime> _exitGeoRetryAfter = {};
  int _groupsGeneration = 0;
  int _serverRequestGeneration = 0;
  int _exitRequestGeneration = 0;
  int? _restoredSnapshotGeneration;
  _ActiveProxySelection? _activeSelection;
  List<String>? _activePathIds;
  bool _committingRuntimeSelection = false;

  @override
  void build() {
    ref.listen<int>(networkRevisionProvider, (previous, next) {
      if (previous == next) return;
      unawaited(_handleNetworkRevision(next));
    });
    ref.listen<CoreStatus>(coreStatusProvider, (previous, next) {
      if (previous == next) return;
      if (next != CoreStatus.connected) {
        _groupsGeneration++;
        _serverRequestGeneration++;
        _restoredSnapshotGeneration = null;
        _activeSelection = null;
        _activePathIds = null;
        _serverGeoRetryAfter.clear();
        _exitGeoRetryAfter.clear();
      }
      _handleSessionAvailability();
    });
    ref.listen<int?>(runTimeProvider, (previous, next) {
      if ((previous != null) == (next != null)) return;
      _handleSessionAvailability();
    });
    ref.listen<bool>(isStartingProvider, (previous, next) {
      if (previous == next) return;
      _handleSessionAvailability();
    });
    ref.listen<bool>(suspendProvider, (previous, next) {
      if (previous == next) return;
      _handleSessionAvailability();
    });
    ref.listen<ProxiesData>(runtimeProxiesProvider, (previous, next) {
      if (_committingRuntimeSelection ||
          previous == null ||
          previous.generation == 0 ||
          previous.generation != next.generation) {
        return;
      }
      final oldSelection = _activeSelection;
      final oldPath = _activePathIds;
      _synchronizeActiveSelection(next);
      if (oldSelection == _activeSelection &&
          _sameNullableStringList(oldPath, _activePathIds)) {
        return;
      }
      _invalidateExitState();
      final leafId = _activePathIds?.lastOrNull;
      if (leafId != null) {
        _exitGeoRetryAfter.remove(leafId);
      }
      unawaited(_probeActiveSelection());
    });
    ref.listen<int>(geoDatabaseRevisionProvider, (previous, next) {
      if (previous == next) return;
      unawaited(_handleGeoDatabaseRevision(next));
    });
  }

  void _handleSessionAvailability() {
    _exitGeoRetryAfter.clear();
    if (!ref.read(proxyGeoSessionActiveProvider)) {
      _invalidateExitState();
      return;
    }
    unawaited(_probeActiveSelection(force: true));
  }

  void updateGroupsDebounce([Duration? duration]) {
    debouncer.call(FunctionTag.updateGroups, () async {
      if (!ref.mounted) return;
      await updateGroups();
    }, duration: duration);
  }

  Future<void> changeProxyDebounce(
    String groupName,
    String proxyName, {
    String? groupId,
    String? memberId,
    int? generation,
    Duration? duration,
  }) {
    final profileId = ref.read(currentProfileIdProvider);
    final key = (
      profileId: profileId,
      groupName: groupId?.isNotEmpty == true ? groupId! : groupName,
    );
    final selectionGeneration = (_selectionGenerations[key] ?? 0) + 1;
    _selectionGenerations[key] = selectionGeneration;
    return debouncer
        .callAsync<void>(
          (FunctionTag.changeProxy, key),
          () => serializedSetup(() async {
            if (!_isCurrentSelection(key, selectionGeneration)) {
              return;
            }
            final selection = _resolveProxySelection(
              groupName: groupName,
              proxyName: proxyName,
              groupId: groupId,
              memberId: memberId,
              generation: generation,
            );
            await _executeProxyChange(selection.params);
            if (!_isCurrentSelection(key, selectionGeneration)) {
              return;
            }
            await ref
                .read(profilesActionProvider.notifier)
                .updateCurrentSelectedMap(
                  groupName,
                  proxyName,
                  groupStableKey: selection.group == null
                      ? null
                      : ref
                            .read(runtimeProxiesProvider)
                            .nodesById[selection.group!.id]
                            ?.stableKey,
                  proxyStableKey: selection.member?.stableKey,
                );
            if (!_isCurrentSelection(key, selectionGeneration)) {
              return;
            }
            _commitRuntimeSelection(selection);
            await _refreshConnections();
            ref.read(checkIpNumProvider.notifier).add();
            _scheduleExitProbe(selection);
            updateGroupsDebounce();
          }),
          duration: duration,
        )
        .whenComplete(() {
          if (_selectionGenerations[key] == selectionGeneration) {
            _selectionGenerations.remove(key);
          }
        });
  }

  bool _isCurrentSelection(
    ({int? profileId, String groupName}) key,
    int generation,
  ) {
    return _selectionGenerations[key] == generation &&
        ref.read(currentProfileIdProvider) == key.profileId;
  }

  _ResolvedProxySelection _resolveProxySelection({
    required String groupName,
    required String proxyName,
    String? groupId,
    String? memberId,
    int? generation,
  }) {
    final snapshot = ref.read(runtimeProxiesProvider);
    final hasRuntimeSnapshot =
        snapshot.generation > 0 &&
        snapshot.groups.isNotEmpty &&
        snapshot.nodesById.isNotEmpty;
    if (!hasRuntimeSnapshot) {
      return (
        params: ChangeProxyParams(groupName: groupName, proxyName: proxyName),
        group: null,
        member: null,
      );
    }

    final resolvedGroup = groupId?.isNotEmpty == true
        ? snapshot.groupById(groupId!)
        : snapshot.uniqueGroupByName(groupName);
    if (resolvedGroup == null) {
      throw StateError('Proxy group is missing or ambiguous');
    }
    if (generation != null && generation != snapshot.generation) {
      throw StateError('Proxy snapshot is stale');
    }
    ProxyNodeSnapshot? resolvedMember;
    if (proxyName.isNotEmpty) {
      resolvedMember = memberId?.isNotEmpty == true
          ? snapshot.nodesById[memberId!]
          : snapshot.uniqueMemberByName(resolvedGroup, proxyName);
      if (resolvedMember == null ||
          !resolvedGroup.memberIds.contains(resolvedMember.id)) {
        throw StateError('Proxy member is missing or ambiguous');
      }
    } else if (memberId?.isNotEmpty == true) {
      throw StateError('Empty selection cannot include a member ID');
    }
    return (
      params: ChangeProxyParams(
        groupId: resolvedGroup.id,
        memberId: resolvedMember?.id ?? '',
        generation: snapshot.generation,
      ),
      group: resolvedGroup,
      member: resolvedMember,
    );
  }

  Future<void> _executeProxyChange(ChangeProxyParams params) async {
    final message = params.groupId != null
        ? await ref.read(runtimeProxyChangeExecutorProvider)(params)
        : await ref.read(proxyChangeExecutorProvider)(
            params.groupName ?? '',
            params.proxyName ?? '',
          );
    if (message.isNotEmpty) {
      throw StateError(message);
    }
  }

  void _commitRuntimeSelection(_ResolvedProxySelection selection) {
    final group = selection.group;
    if (group == null) return;
    final memberId = selection.member?.id ?? '';
    final snapshot = ref.read(runtimeProxiesProvider);
    if (snapshot.generation != selection.params.generation) return;
    final updatedGroups = snapshot.groups
        .map(
          (item) => item.id == group.id ? item.copyWith(nowId: memberId) : item,
        )
        .toList();
    _committingRuntimeSelection = true;
    try {
      ref.read(runtimeProxiesProvider.notifier).value = snapshot.copyWith(
        groups: updatedGroups,
      );
    } finally {
      _committingRuntimeSelection = false;
    }
    final memberName = selection.member?.name ?? '';
    ref.read(groupsProvider.notifier).value = ref
        .read(groupsProvider)
        .map(
          (item) => item.runtimeId == group.id
              ? item.copyWith(now: memberName, nowId: memberId)
              : item,
        )
        .toList();
  }

  void _scheduleExitProbe(_ResolvedProxySelection selection) {
    final group = selection.group;
    final member = selection.member;
    if (group == null || member == null) {
      _activeSelection = null;
      _activePathIds = null;
      _invalidateExitState();
      return;
    }
    _activeSelection = (groupId: group.id, memberId: member.id);
    _activePathIds = ref
        .read(runtimeProxiesProvider)
        .resolveMemberPathIds(group.id, member.id);
    final leafId = _activePathIds?.lastOrNull;
    if (leafId != null) {
      _exitGeoRetryAfter.remove(leafId);
    }
    unawaited(_probeActiveSelection(force: true));
  }

  Future<void> _refreshConnections() async {
    await ref.read(proxyConnectionRefresherProvider)();
  }

  Future<void> updateGroups({bool rethrowOnFailure = false}) async {
    final requestGeneration = ++_groupsGeneration;
    final profileId = ref.read(currentProfileIdProvider);
    try {
      commonPrint.log('updateGroups');
      var loaded = await retry(
        task: () async {
          final snapshot = await ref.read(proxiesSnapshotLoaderProvider)();
          final sortType = ref.read(
            proxiesStyleSettingProvider.select((state) => state.sortType),
          );
          final delayMap = ref.read(delayDataSourceProvider);
          final testUrl = ref.read(
            appSettingProvider.select((state) => state.testUrl),
          );
          final selectedMap = ref.read(
            currentProfileProvider.select((state) => state?.selectedMap ?? {}),
          );
          final groups = await ref.read(proxyGroupsBuilderProvider)(
            proxiesData: snapshot,
            selectedMap: selectedMap,
            sortType: sortType,
            delayMap: delayMap,
            defaultTestUrl: testUrl,
          );
          return (snapshot: snapshot, groups: groups);
        },
        retryIf: (res) => res.groups.isEmpty,
      );
      if (!_isCurrentGroupsRequest(requestGeneration, profileId)) return;
      final shouldRestore =
          loaded.snapshot.generation > 0 &&
          loaded.snapshot.generation != _restoredSnapshotGeneration;
      if (shouldRestore) {
        final changed = await _restoreStableSelections(loaded.snapshot);
        _restoredSnapshotGeneration = loaded.snapshot.generation;
        if (!_isCurrentGroupsRequest(requestGeneration, profileId)) return;
        if (changed) {
          final snapshot = await ref.read(proxiesSnapshotLoaderProvider)();
          final groups = await ref.read(proxyGroupsBuilderProvider)(
            proxiesData: snapshot,
            selectedMap: ref.read(currentProfileProvider)?.selectedMap ?? {},
            sortType: ref.read(proxiesStyleSettingProvider).sortType,
            delayMap: ref.read(delayDataSourceProvider),
            defaultTestUrl: ref.read(appSettingProvider).testUrl,
          );
          loaded = (snapshot: snapshot, groups: groups);
        }
      }
      if (!_isCurrentGroupsRequest(requestGeneration, profileId)) return;
      final previousSnapshot = ref.read(runtimeProxiesProvider);
      ref.read(runtimeProxiesProvider.notifier).value = loaded.snapshot;
      ref.read(groupsProvider.notifier).value = loaded.groups;
      _synchronizeActiveSelection(loaded.snapshot);
      _seedGeoStateFromCache(
        loaded.snapshot,
        previousGeneration: previousSnapshot.generation,
      );
      if (_needsServerGeoRefresh(loaded.snapshot)) {
        unawaited(_refreshServerGeos(loaded.snapshot));
      }
      if (_needsExitProbe(loaded.snapshot)) {
        unawaited(_probeActiveSelection());
      }
    } catch (error, stackTrace) {
      commonPrint.log('updateGroups error: $error\n$stackTrace');
      if (!_isCurrentGroupsRequest(requestGeneration, profileId)) return;
      ref.read(runtimeProxiesProvider.notifier).value = const ProxiesData();
      ref.read(groupsProvider.notifier).value = [];
      if (rethrowOnFailure) rethrow;
    }
  }

  bool _isCurrentGroupsRequest(int generation, int? profileId) {
    return ref.mounted &&
        generation == _groupsGeneration &&
        ref.read(currentProfileIdProvider) == profileId;
  }

  Future<bool> _restoreStableSelections(ProxiesData snapshot) async {
    final stableSelections = ref
        .read(currentProfileProvider)
        ?.selectedStableMap;
    if (stableSelections == null || stableSelections.isEmpty) return false;
    var changed = false;
    for (final selection in stableSelections.entries) {
      final matchingGroups = snapshot.groups.where((group) {
        return snapshot.nodesById[group.id]?.stableKey == selection.key;
      }).toList();
      if (matchingGroups.length != 1) continue;
      final group = matchingGroups.single;
      final matchingMembers = group.memberIds.where((memberId) {
        return snapshot.nodesById[memberId]?.stableKey == selection.value;
      }).toList();
      if (matchingMembers.length != 1) continue;
      final memberId = matchingMembers.single;
      if (group.nowId == memberId) continue;
      try {
        final message = await ref.read(runtimeProxyChangeExecutorProvider)(
          ChangeProxyParams(
            groupId: group.id,
            memberId: memberId,
            generation: snapshot.generation,
          ),
        );
        if (message.isEmpty) {
          changed = true;
        } else {
          commonPrint.log(
            'Stable proxy selection was rejected: $message',
            logLevel: LogLevel.warning,
          );
        }
      } catch (error, stackTrace) {
        commonPrint.log(
          'Stable proxy selection failed: $error\n$stackTrace',
          logLevel: LogLevel.warning,
        );
      }
    }
    return changed;
  }

  void _synchronizeActiveSelection(ProxiesData snapshot) {
    final current = _activeSelection;
    if (current != null) {
      final group = snapshot.groupById(current.groupId);
      if (group != null &&
          group.nowId == current.memberId &&
          group.memberIds.contains(current.memberId)) {
        _activePathIds = snapshot.resolveMemberPathIds(
          current.groupId,
          current.memberId,
        );
        return;
      }
      if (group != null &&
          group.nowId.isNotEmpty &&
          group.memberIds.contains(group.nowId)) {
        _activeSelection = (groupId: group.id, memberId: group.nowId);
        _activePathIds = snapshot.resolveMemberPathIds(group.id, group.nowId);
        return;
      }
    }
    final currentGroupName = ref.read(currentProfileProvider)?.currentGroupName;
    if (currentGroupName == null) {
      _activeSelection = null;
      _activePathIds = null;
      return;
    }
    final group = snapshot.uniqueGroupByName(currentGroupName);
    _activeSelection = group == null || group.nowId.isEmpty
        ? null
        : (groupId: group.id, memberId: group.nowId);
    _activePathIds = _activeSelection == null
        ? null
        : snapshot.resolveMemberPathIds(group!.id, group.nowId);
  }

  void _seedGeoStateFromCache(
    ProxiesData snapshot, {
    required int previousGeneration,
  }) {
    if (previousGeneration != snapshot.generation) {
      _serverGeoRetryAfter.clear();
      _exitGeoRetryAfter.clear();
    }
    final now = _now();
    final revision = ref.read(networkRevisionProvider);
    final geoRevision = ref.read(geoDatabaseRevisionProvider);
    final current = ref.read(proxyGeoDataSourceProvider);
    final canReuseCurrent =
        previousGeneration == snapshot.generation &&
        current.generation == snapshot.generation &&
        current.networkRevision == revision &&
        current.geoDatabaseRevision == geoRevision;
    final serverByMemberId = <String, ProxyServerGeo>{};
    final exitByMemberId = <String, ProxyExitGeo>{};
    final staleServerIds = <String>{};
    final staleExitIds = <String>{};
    for (final node in snapshot.nodesById.values) {
      final currentServer = canReuseCurrent
          ? current.serverByMemberId[node.id]
          : null;
      if (currentServer != null) {
        serverByMemberId[node.id] = currentServer;
        if (current.staleServerMemberIds.contains(node.id)) {
          staleServerIds.add(node.id);
        }
      } else {
        final cached = _serverGeoCache.latestWhere(
          (key) => key.stableKey == node.stableKey,
          now,
        );
        if (cached != null) {
          serverByMemberId[node.id] = cached.value.copyWith(memberId: node.id);
          staleServerIds.add(node.id);
        }
      }
      final currentExit = canReuseCurrent
          ? current.exitByMemberId[node.id]
          : null;
      if (currentExit != null) {
        exitByMemberId[node.id] = currentExit;
        if (current.staleExitMemberIds.contains(node.id)) {
          staleExitIds.add(node.id);
        }
      } else {
        final cached = _exitGeoCache.get((
          stableKey: node.stableKey,
          networkRevision: revision,
        ), now);
        if (cached != null) {
          exitByMemberId[node.id] = cached.copyWith(leafId: node.id);
          staleExitIds.add(node.id);
        }
      }
    }
    final activeExitLeafId =
        canReuseCurrent &&
            snapshot.nodesById.containsKey(current.activeExitLeafId)
        ? current.activeExitLeafId
        : null;
    final exitLoadingMemberIds = canReuseCurrent
        ? current.exitLoadingMemberIds
              .where(snapshot.nodesById.containsKey)
              .toSet()
        : const <String>{};
    final exitErrorsByMemberId = canReuseCurrent
        ? Map<String, String>.fromEntries(
            current.exitErrorsByMemberId.entries.where(
              (entry) => snapshot.nodesById.containsKey(entry.key),
            ),
          )
        : const <String, String>{};
    ref
        .read(proxyGeoDataSourceProvider.notifier)
        .replace(
          ProxyGeoState(
            generation: snapshot.generation,
            networkRevision: revision,
            geoDatabaseRevision: geoRevision,
            serverByMemberId: serverByMemberId,
            exitByMemberId: exitByMemberId,
            exitLoadingMemberIds: exitLoadingMemberIds,
            exitErrorsByMemberId: exitErrorsByMemberId,
            staleServerMemberIds: staleServerIds,
            staleExitMemberIds: staleExitIds,
            exitError: canReuseCurrent ? current.exitError : null,
            activeExitLeafId: activeExitLeafId,
          ),
        );
  }

  bool _needsServerGeoRefresh(ProxiesData snapshot) {
    final state = ref.read(proxyGeoDataSourceProvider);
    final groupIds = snapshot.groups.map((group) => group.id).toSet();
    final now = _now();
    for (final memberId in snapshot.nodesById.keys) {
      if (groupIds.contains(memberId)) continue;
      if (!state.serverByMemberId.containsKey(memberId) ||
          state.staleServerMemberIds.contains(memberId)) {
        final retryAfter = _serverGeoRetryAfter[memberId];
        if (retryAfter == null || !now.isBefore(retryAfter)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _needsExitProbe(ProxiesData snapshot) {
    final selection = _activeSelection;
    if (selection == null || !ref.read(proxyGeoSessionActiveProvider)) {
      return false;
    }
    final selectedLeafId = snapshot.resolveMemberLeafId(
      selection.groupId,
      selection.memberId,
    );
    if (selectedLeafId == null || _exitProbeIsDeferred(selectedLeafId)) {
      return false;
    }
    final state = ref.read(proxyGeoDataSourceProvider);
    final activeLeafId = state.activeExitLeafId;
    if (activeLeafId == null) return true;
    if (state.exitLoadingMemberIds.contains(activeLeafId)) return false;
    final value = state.exitByMemberId[activeLeafId];
    return value == null ||
        value.stale ||
        state.staleExitMemberIds.contains(activeLeafId);
  }

  Future<void> _refreshServerGeos(ProxiesData snapshot) async {
    if (snapshot.generation == 0 || snapshot.nodesById.isEmpty) return;
    final revision = ref.read(networkRevisionProvider);
    final geoRevision = ref.read(geoDatabaseRevisionProvider);
    final requestGeneration = ++_serverRequestGeneration;
    final groupIds = snapshot.groups.map((group) => group.id).toSet();
    final stateBefore = ref.read(proxyGeoDataSourceProvider);
    final now = _now();
    final memberIds =
        snapshot.nodesById.keys
            .where((memberId) => !groupIds.contains(memberId))
            .where(
              (memberId) =>
                  !stateBefore.serverByMemberId.containsKey(memberId) ||
                  stateBefore.staleServerMemberIds.contains(memberId),
            )
            .where((memberId) {
              final retryAfter = _serverGeoRetryAfter[memberId];
              return retryAfter == null || !now.isBefore(retryAfter);
            })
            .toList()
          ..sort();
    if (memberIds.isEmpty) return;
    final memberIdSet = memberIds.toSet();
    ref
        .read(proxyGeoDataSourceProvider.notifier)
        .replace(
          stateBefore.copyWith(
            generation: snapshot.generation,
            networkRevision: revision,
            geoDatabaseRevision: geoRevision,
            serverLoadingMemberIds: memberIdSet,
            serverError: null,
          ),
        );
    try {
      for (
        var offset = 0;
        offset < memberIds.length;
        offset += _serverGeoBatchSize
      ) {
        if (!_ownsServerRequest(
          requestGeneration,
          snapshot.generation,
          revision,
          geoRevision,
        )) {
          return;
        }
        final tentativeEnd = offset + _serverGeoBatchSize;
        final end = tentativeEnd < memberIds.length
            ? tentativeEnd
            : memberIds.length;
        final batch = memberIds.sublist(offset, end);
        final batchIndex = offset ~/ _serverGeoBatchSize;
        final requestId = 'dart-server-$requestGeneration-$batchIndex';
        final response = await ref.read(proxyServerGeoLoaderProvider)(
          ProxyServerGeoParams(
            generation: snapshot.generation,
            networkRevision: revision,
            requestId: requestId,
            memberIds: batch,
          ),
        );
        if (!_ownsServerRequest(
          requestGeneration,
          snapshot.generation,
          revision,
          geoRevision,
        )) {
          return;
        }
        if (response.stale ||
            response.generation != snapshot.generation ||
            response.requestId.isNotEmpty && response.requestId != requestId) {
          final pending = memberIds.skip(offset);
          _deferServerGeoMembers(pending);
          _finishServerGeoMembers(pending, error: 'stale');
          return;
        }
        _mergeServerGeoBatch(snapshot, batch, response);
      }
    } catch (error, stackTrace) {
      if (!_ownsServerRequest(
        requestGeneration,
        snapshot.generation,
        revision,
        geoRevision,
      )) {
        return;
      }
      commonPrint.log(
        'Proxy server geo refresh failed: $error\n$stackTrace',
        logLevel: LogLevel.warning,
      );
      final state = ref.read(proxyGeoDataSourceProvider);
      final pending = state.serverLoadingMemberIds.intersection(memberIdSet);
      _deferServerGeoMembers(pending);
      final errors = Map<String, String>.from(state.serverErrorsByMemberId);
      for (final memberId in pending) {
        errors[memberId] = error.toString();
      }
      ref
          .read(proxyGeoDataSourceProvider.notifier)
          .replace(
            state.copyWith(
              serverLoadingMemberIds: {...state.serverLoadingMemberIds}
                ..removeAll(memberIdSet),
              serverErrorsByMemberId: errors,
              staleServerMemberIds: {...state.staleServerMemberIds, ...pending},
              serverError: error.toString(),
            ),
          );
    }
  }

  void _mergeServerGeoBatch(
    ProxiesData snapshot,
    List<String> batch,
    ProxyServerGeos response,
  ) {
    final state = ref.read(proxyGeoDataSourceProvider);
    final values = Map<String, ProxyServerGeo>.from(state.serverByMemberId);
    final errors = Map<String, String>.from(state.serverErrorsByMemberId);
    final staleIds = Set<String>.from(state.staleServerMemberIds);
    final loadingIds = Set<String>.from(state.serverLoadingMemberIds)
      ..removeAll(batch);
    final now = _now();
    for (final memberId in batch) {
      final value = response.members[memberId];
      if (value == null || value.memberId != memberId) {
        errors[memberId] = 'missing';
        staleIds.add(memberId);
        _serverGeoRetryAfter[memberId] = now.add(_serverGeoRetryDelay);
        continue;
      }
      if (value.status == 'ok' || value.status == 'unsupported') {
        values[memberId] = value;
        errors.remove(memberId);
        staleIds.remove(memberId);
        _serverGeoRetryAfter.remove(memberId);
        if (value.status == 'ok') {
          final node = snapshot.nodesById[memberId]!;
          final cacheable =
              value.serverHost.isNotEmpty &&
              value.addresses.isNotEmpty &&
              value.addresses.every(
                (address) => address.countryCode.isNotEmpty,
              );
          if (cacheable) {
            _serverGeoCache.set(
              (stableKey: node.stableKey, serverHost: value.serverHost),
              value,
              now.add(_serverGeoCacheTtl),
            );
          }
        }
        continue;
      }
      values.putIfAbsent(memberId, () => value);
      errors[memberId] = value.status.isEmpty ? 'unavailable' : value.status;
      staleIds.add(memberId);
      _serverGeoRetryAfter[memberId] = now.add(_serverGeoRetryDelay);
    }
    ref
        .read(proxyGeoDataSourceProvider.notifier)
        .replace(
          state.copyWith(
            serverByMemberId: values,
            serverLoadingMemberIds: loadingIds,
            serverErrorsByMemberId: errors,
            staleServerMemberIds: staleIds,
            serverError: null,
          ),
        );
  }

  void _deferServerGeoMembers(Iterable<String> memberIds) {
    final retryAt = _now().add(_serverGeoRetryDelay);
    for (final memberId in memberIds) {
      _serverGeoRetryAfter[memberId] = retryAt;
    }
  }

  void _finishServerGeoMembers(
    Iterable<String> memberIds, {
    required String error,
  }) {
    final ids = memberIds.toSet();
    final state = ref.read(proxyGeoDataSourceProvider);
    final errors = Map<String, String>.from(state.serverErrorsByMemberId);
    for (final memberId in ids) {
      errors[memberId] = error;
    }
    ref
        .read(proxyGeoDataSourceProvider.notifier)
        .replace(
          state.copyWith(
            serverLoadingMemberIds: {...state.serverLoadingMemberIds}
              ..removeAll(ids),
            serverErrorsByMemberId: errors,
            staleServerMemberIds: {...state.staleServerMemberIds, ...ids},
          ),
        );
  }

  DateTime _now() => ref.read(proxyGeoClockProvider)();

  bool _exitProbeIsDeferred(String leafId) {
    final retryAfter = _exitGeoRetryAfter[leafId];
    if (retryAfter == null) return false;
    if (_now().isBefore(retryAfter)) return true;
    _exitGeoRetryAfter.remove(leafId);
    return false;
  }

  void _deferExitProbe(String leafId) {
    _exitGeoRetryAfter[leafId] = _now().add(_exitGeoRetryDelay);
  }

  bool _ownsServerRequest(
    int requestGeneration,
    int snapshotGeneration,
    int networkRevision,
    int geoDatabaseRevision,
  ) {
    return ref.mounted &&
        requestGeneration == _serverRequestGeneration &&
        ref.read(runtimeProxiesProvider).generation == snapshotGeneration &&
        ref.read(networkRevisionProvider) == networkRevision &&
        ref.read(geoDatabaseRevisionProvider) == geoDatabaseRevision;
  }

  Future<void> _probeActiveSelection({bool force = false}) async {
    final selection = _activeSelection;
    if (selection == null || !ref.read(proxyGeoSessionActiveProvider)) {
      return;
    }
    final snapshot = ref.read(runtimeProxiesProvider);
    final group = snapshot.groupById(selection.groupId);
    if (snapshot.generation == 0 ||
        group == null ||
        group.nowId != selection.memberId ||
        !group.memberIds.contains(selection.memberId)) {
      return;
    }
    final leafId = snapshot.resolveMemberLeafId(
      selection.groupId,
      selection.memberId,
    );
    if (leafId == null) return;
    final revision = ref.read(networkRevisionProvider);
    final state = ref.read(proxyGeoDataSourceProvider);
    if (!force &&
        state.activeExitLeafId == leafId &&
        state.exitLoadingMemberIds.contains(leafId)) {
      return;
    }
    if (!force && _exitProbeIsDeferred(leafId)) return;
    if (force) {
      _exitGeoRetryAfter.remove(leafId);
    }
    final requestGeneration = ++_exitRequestGeneration;
    final requestId = 'dart-exit-$requestGeneration';
    ref
        .read(proxyGeoDataSourceProvider.notifier)
        .replace(
          state.copyWith(
            generation: snapshot.generation,
            networkRevision: revision,
            exitLoadingMemberIds: {leafId},
            activeExitLeafId: leafId,
            exitError: null,
          ),
        );
    try {
      final response = await ref
          .read(proxyExitGeoLoaderProvider)(
            ProbeProxyExitParams(
              generation: snapshot.generation,
              networkRevision: revision,
              requestId: requestId,
              groupId: selection.groupId,
              memberId: selection.memberId,
            ),
          )
          .timeout(ref.read(proxyExitGeoTimeoutProvider));
      if (!_ownsExitRequest(
        requestGeneration,
        selection,
        snapshot.generation,
        revision,
      )) {
        return;
      }
      if (response.stale ||
          response.generation != snapshot.generation ||
          response.requestId.isNotEmpty && response.requestId != requestId ||
          response.leafId.isEmpty ||
          !snapshot.nodesById.containsKey(response.leafId)) {
        _deferExitProbe(leafId);
        final current = ref.read(proxyGeoDataSourceProvider);
        ref
            .read(proxyGeoDataSourceProvider.notifier)
            .replace(
              current.copyWith(
                exitLoadingMemberIds: {},
                staleExitMemberIds: {...current.staleExitMemberIds, leafId},
              ),
            );
        return;
      }
      final currentSnapshot = ref.read(runtimeProxiesProvider);
      final currentPath = currentSnapshot.resolveMemberPathIds(
        selection.groupId,
        selection.memberId,
      );
      if (currentPath == null ||
          currentPath.last != response.leafId ||
          response.pathIds.isNotEmpty &&
              !_sameStringList(currentPath, response.pathIds)) {
        _deferExitProbe(leafId);
        final current = ref.read(proxyGeoDataSourceProvider);
        ref
            .read(proxyGeoDataSourceProvider.notifier)
            .replace(
              current.copyWith(
                exitLoadingMemberIds: {},
                staleExitMemberIds: {...current.staleExitMemberIds, leafId},
                activeExitLeafId: null,
              ),
            );
        return;
      }
      final current = ref.read(proxyGeoDataSourceProvider);
      final exits = Map<String, ProxyExitGeo>.from(current.exitByMemberId)
        ..[response.leafId] = response;
      final staleIds = Set<String>.from(current.staleExitMemberIds)
        ..remove(response.leafId);
      final errors = Map<String, String>.from(current.exitErrorsByMemberId)
        ..remove(response.leafId);
      final node = snapshot.nodesById[response.leafId]!;
      _exitGeoRetryAfter.remove(response.leafId);
      _exitGeoCache.set(
        (stableKey: node.stableKey, networkRevision: revision),
        response,
        _now().add(_exitGeoCacheTtl),
      );
      ref
          .read(proxyGeoDataSourceProvider.notifier)
          .replace(
            current.copyWith(
              exitByMemberId: exits,
              exitLoadingMemberIds: {},
              exitErrorsByMemberId: errors,
              staleExitMemberIds: staleIds,
              activeExitLeafId: response.leafId,
              exitError: null,
            ),
          );
    } catch (error, stackTrace) {
      if (!_ownsExitRequest(
        requestGeneration,
        selection,
        snapshot.generation,
        revision,
      )) {
        return;
      }
      commonPrint.log(
        'Proxy exit probe failed: $error\n$stackTrace',
        logLevel: LogLevel.warning,
      );
      _deferExitProbe(leafId);
      final current = ref.read(proxyGeoDataSourceProvider);
      final errors = Map<String, String>.from(current.exitErrorsByMemberId)
        ..[leafId] = error.toString();
      ref
          .read(proxyGeoDataSourceProvider.notifier)
          .replace(
            current.copyWith(
              exitLoadingMemberIds: {},
              exitErrorsByMemberId: errors,
              staleExitMemberIds: {...current.staleExitMemberIds, leafId},
              exitError: error.toString(),
            ),
          );
    }
  }

  bool _ownsExitRequest(
    int requestGeneration,
    _ActiveProxySelection selection,
    int snapshotGeneration,
    int networkRevision,
  ) {
    return ref.mounted &&
        requestGeneration == _exitRequestGeneration &&
        _activeSelection == selection &&
        ref.read(runtimeProxiesProvider).generation == snapshotGeneration &&
        ref.read(networkRevisionProvider) == networkRevision &&
        ref.read(proxyGeoSessionActiveProvider);
  }

  Future<void> _handleNetworkRevision(int revision) async {
    final snapshot = ref.read(runtimeProxiesProvider);
    if (snapshot.generation == 0) return;
    _serverRequestGeneration++;
    _exitRequestGeneration++;
    _serverGeoRetryAfter.clear();
    _exitGeoRetryAfter.clear();
    final state = ref.read(proxyGeoDataSourceProvider);
    ref
        .read(proxyGeoDataSourceProvider.notifier)
        .replace(
          state.copyWith(
            networkRevision: revision,
            serverLoadingMemberIds: {},
            exitLoadingMemberIds: {},
            staleServerMemberIds: state.serverByMemberId.keys.toSet(),
            staleExitMemberIds: state.exitByMemberId.keys.toSet(),
            activeExitLeafId: null,
          ),
        );
    await Future.wait([_refreshServerGeos(snapshot), _probeActiveSelection()]);
  }

  Future<void> _handleGeoDatabaseRevision(int revision) async {
    final snapshot = ref.read(runtimeProxiesProvider);
    _serverRequestGeneration++;
    _exitRequestGeneration++;
    _serverGeoCache.clear();
    _exitGeoCache.clear();
    _serverGeoRetryAfter.clear();
    _exitGeoRetryAfter.clear();
    final state = ref.read(proxyGeoDataSourceProvider);
    ref
        .read(proxyGeoDataSourceProvider.notifier)
        .replace(
          state.copyWith(
            geoDatabaseRevision: revision,
            serverLoadingMemberIds: {},
            exitLoadingMemberIds: {},
            staleServerMemberIds: state.serverByMemberId.keys.toSet(),
            staleExitMemberIds: state.exitByMemberId.keys.toSet(),
            activeExitLeafId: null,
            serverError: null,
            exitError: null,
          ),
        );
    if (snapshot.generation != 0) {
      await Future.wait([
        _refreshServerGeos(snapshot),
        _probeActiveSelection(),
      ]);
    }
  }

  void _invalidateExitState() {
    _exitRequestGeneration++;
    final state = ref.read(proxyGeoDataSourceProvider);
    ref
        .read(proxyGeoDataSourceProvider.notifier)
        .replace(
          state.copyWith(
            exitLoadingMemberIds: {},
            staleExitMemberIds: state.exitByMemberId.keys.toSet(),
            activeExitLeafId: null,
          ),
        );
  }

  Future<void> updateCurrentGroupName(String groupName) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;
    if (profile.currentGroupName != groupName) {
      await ref
          .read(profilesProvider.notifier)
          .put(profile.copyWith(currentGroupName: groupName));
    }
    final group = ref.read(runtimeProxiesProvider).uniqueGroupByName(groupName);
    if (group == null || group.nowId.isEmpty) return;
    _activeSelection = (groupId: group.id, memberId: group.nowId);
    _activePathIds = ref
        .read(runtimeProxiesProvider)
        .resolveMemberPathIds(group.id, group.nowId);
    final leafId = _activePathIds?.lastOrNull;
    if (leafId != null) {
      _exitGeoRetryAfter.remove(leafId);
    }
    unawaited(_probeActiveSelection(force: true));
  }

  Future<void> updateCurrentUnfoldSet(Set<String> value) async {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile == null) return;
    await ref
        .read(profilesProvider.notifier)
        .put(currentProfile.copyWith(unfoldSet: value));
  }

  void setDelay(Delay delay) {
    ref.read(delayDataSourceProvider.notifier).setDelay(delay);
  }

  void setDelays(List<Delay> delays) {
    ref.read(delayDataSourceProvider.notifier).setDelays(delays);
  }

  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
    String? groupId,
    String? memberId,
    int? generation,
  }) async {
    final selection = _resolveProxySelection(
      groupName: groupName,
      proxyName: proxyName,
      groupId: groupId,
      memberId: memberId,
      generation: generation,
    );
    await _executeProxyChange(selection.params);
    _commitRuntimeSelection(selection);
    await _refreshConnections();
    ref.read(checkIpNumProvider.notifier).add();
    _scheduleExitProbe(selection);
  }

  Future<String> updateProvider(
    ExternalProvider provider, {
    bool showLoading = false,
  }) {
    final inFlight = _providerUpdates[provider.name];
    if (inFlight != null) {
      return inFlight;
    }
    final generation = (_providerGenerations[provider.name] ?? 0) + 1;
    _providerGenerations[provider.name] = generation;
    late final Future<String> request;
    request = _performProviderUpdate(provider, generation, showLoading);
    _providerUpdates[provider.name] = request;
    return request.whenComplete(() {
      if (identical(_providerUpdates[provider.name], request)) {
        _providerUpdates.remove(provider.name);
      }
    });
  }

  Future<String> _performProviderUpdate(
    ExternalProvider provider,
    int generation,
    bool showLoading,
  ) async {
    try {
      if (showLoading) {
        ref.read(isUpdatingProvider(provider.updatingKey).notifier).value =
            true;
      }
      final message = await ref.read(externalProviderUpdaterProvider)(
        provider.name,
      );
      if (message.isNotEmpty) return message;
      final updatedProvider = await ref.read(externalProviderLoaderProvider)(
        provider.name,
      );
      final current = ref
          .read(providersProvider)
          .where((item) => item.name == provider.name)
          .firstOrNull;
      if (_providerGenerations[provider.name] == generation &&
          identical(current, provider)) {
        ref.read(providersProvider.notifier).setProvider(updatedProvider);
        updateGroupsDebounce(Duration.zero);
      }
      return '';
    } finally {
      ref.read(isUpdatingProvider(provider.updatingKey).notifier).value = false;
    }
  }

  Future<Map<String, String>> updateProviders(
    Iterable<ExternalProvider> providers,
  ) async {
    final pending = providers.toList();
    final messages = <String, String>{};
    var nextIndex = 0;
    Future<void> worker() async {
      while (nextIndex < pending.length) {
        final provider = pending[nextIndex++];
        try {
          final message = await updateProvider(provider);
          if (message.isNotEmpty) {
            messages[provider.name] = message;
          }
        } catch (error) {
          messages[provider.name] = error.toString();
        }
      }
    }

    final workerCount = pending.length < 4 ? pending.length : 4;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return messages;
  }
}

bool _sameStringList(List<String> first, List<String> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

bool _sameNullableStringList(List<String>? first, List<String>? second) {
  if (identical(first, second)) return true;
  if (first == null || second == null) return false;
  return _sameStringList(first, second);
}
