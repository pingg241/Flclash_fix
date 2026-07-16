part of '../state.dart';

final _groupTypeNames = GroupType.values.map((type) => type.name).toSet();

@riverpod
GroupsState filterGroupsState(Ref ref, String query) {
  final currentGroups = ref.watch(currentGroupsStateProvider);
  if (query.isEmpty) {
    return currentGroups;
  }
  final lowQuery = query.toLowerCase();
  final groups = currentGroups.value
      .map((group) {
        return group.copyWith(
          all: group.all
              .where((proxy) => proxy.name.toLowerCase().contains(lowQuery))
              .toList(),
        );
      })
      .where((group) => group.all.isNotEmpty)
      .toList();
  return currentGroups.copyWith(value: groups);
}

@riverpod
ProxiesListState proxiesListState(Ref ref) {
  final query = ref.watch(queryProvider(QueryTag.proxies));
  final currentGroups = ref.watch(filterGroupsStateProvider(query));
  final currentUnfoldSet = ref.watch(unfoldSetProvider);
  final cardType = ref.watch(
    proxiesStyleSettingProvider.select((state) => state.cardType),
  );

  final columns = ref.watch(proxiesColumnsProvider);
  return ProxiesListState(
    groups: currentGroups.value,
    currentUnfoldSet: currentUnfoldSet,
    proxyCardType: cardType,
    columns: columns,
  );
}

@riverpod
ProxiesTabState proxiesTabState(Ref ref) {
  final query = ref.watch(queryProvider(QueryTag.proxies));
  final currentGroups = ref.watch(filterGroupsStateProvider(query));
  final currentGroupName = ref.watch(
    currentProfileProvider.select((state) => state?.currentGroupName),
  );
  final cardType = ref.watch(
    proxiesStyleSettingProvider.select((state) => state.cardType),
  );
  final columns = ref.watch(proxiesColumnsProvider);
  return ProxiesTabState(
    groups: currentGroups.value,
    currentGroupName: currentGroupName,
    proxyCardType: cardType,
    columns: columns,
  );
}

@riverpod
bool isStart(Ref ref) {
  return ref.watch(runTimeProvider.select((state) => state != null));
}

@riverpod
bool proxyGeoSessionActive(Ref ref) {
  return ref.watch(coreStatusProvider) == CoreStatus.connected &&
      ref.watch(isStartProvider) &&
      !ref.watch(isStartingProvider) &&
      !ref.watch(suspendProvider);
}

@riverpod
VM2<List<String>, String?> proxiesTabControllerState(Ref ref) {
  return ref.watch(
    proxiesTabStateProvider.select(
      (state) => VM2(
        state.groups.map((group) => group.name).toList(),
        state.currentGroupName,
      ),
    ),
  );
}

@riverpod
ProxyGroupSelectorState proxyGroupSelectorState(
  Ref ref,
  String groupName,
  String query,
) {
  final proxiesStyle = ref.watch(
    proxiesStyleSettingProvider.select(
      (state) => VM2(state.sortType, state.cardType),
    ),
  );
  final group = ref.watch(
    currentGroupsStateProvider.select(
      (state) => state.value.getGroup(groupName),
    ),
  );
  final sortNum = ref.watch(sortNumProvider);
  final columns = ref.watch(proxiesColumnsProvider);
  final lowQuery = query.toLowerCase();
  final proxies =
      group?.all.where((item) {
        return item.name.toLowerCase().contains(lowQuery);
      }).toList() ??
      [];
  return ProxyGroupSelectorState(
    testUrl: group?.testUrl,
    proxiesSortType: proxiesStyle.a,
    proxyCardType: proxiesStyle.b,
    sortNum: sortNum,
    groupType: group?.type ?? GroupType.Selector,
    proxies: proxies,
    columns: columns,
  );
}

@riverpod
PackageListSelectorState packageListSelectorState(Ref ref) {
  final packages = ref.watch(packagesProvider);
  final accessControlProps = ref.watch(
    vpnSettingProvider.select((state) => state.accessControlProps),
  );
  return PackageListSelectorState(
    packages: packages,
    accessControlProps: accessControlProps,
  );
}

@riverpod
MoreToolsSelectorState moreToolsSelectorState(Ref ref) {
  final viewMode = ref.watch(viewModeProvider);
  final navigationItems = ref
      .watch(
        navigationItemsStateProvider.select((state) {
          return VM(
            state.value.where((element) {
              final isMore = element.modes.contains(NavigationItemMode.more);
              final isDesktop = element.modes.contains(
                NavigationItemMode.desktop,
              );
              if (isMore && !isDesktop) return true;
              if (viewMode != ViewMode.mobile || !isMore) {
                return false;
              }
              return true;
            }).toList(),
          );
        }),
      )
      .a;

  return MoreToolsSelectorState(navigationItems: navigationItems);
}

@riverpod
bool isCurrentPage(
  Ref ref,
  PageLabel pageLabel, {
  bool Function(PageLabel pageLabel, ViewMode viewMode)? handler,
}) {
  final currentPageLabel = ref.watch(currentPageLabelProvider);
  if (pageLabel == currentPageLabel) {
    return true;
  }
  if (handler != null) {
    final viewMode = ref.watch(viewModeProvider);
    return handler(currentPageLabel, viewMode);
  }
  return false;
}

@riverpod
String realTestUrl(Ref ref, [String? testUrl]) {
  final currentTestUrl = ref.watch(
    appSettingProvider.select((state) => state.testUrl),
  );
  return testUrl.takeFirstValid([currentTestUrl]);
}

@riverpod
int? delay(Ref ref, {required String proxyName, String? testUrl}) {
  final currentTestUrl = ref.watch(realTestUrlProvider(testUrl));
  final proxyState = ref.watch(realSelectedProxyStateProvider(proxyName));
  final effectiveTestUrl = proxyState.testUrl.takeFirstValid([currentTestUrl]);
  final effectiveProxyName = proxyState.proxyName;
  return ref.watch(
    delayDataSourceProvider.select(
      (state) => state[effectiveTestUrl]?[effectiveProxyName],
    ),
  );
}

@riverpod
Map<String, String> selectedMap(Ref ref) {
  final selectedMap = ref.watch(
    currentProfileProvider.select((state) => state?.selectedMap ?? {}),
  );
  return selectedMap;
}

@riverpod
Set<String> unfoldSet(Ref ref) {
  final unfoldSet = ref.watch(
    currentProfileProvider.select((state) => state?.unfoldSet ?? {}),
  );
  return unfoldSet;
}

final selectedProxyResolverProvider =
    Provider.autoDispose<SelectedProxyResolver>((ref) {
      final groups = ref.watch(groupsProvider);
      final selectedMap = ref.watch(selectedMapProvider);
      return SelectedProxyResolver(groups, selectedMap);
    });

@riverpod
String? resolvedCurrentLeafId(Ref ref, String groupId) {
  return ref.watch(
    runtimeProxiesProvider.select(
      (snapshot) => snapshot.resolveCurrentLeafId(groupId),
    ),
  );
}

@riverpod
String? selectedProxyId(Ref ref, String groupId) {
  return ref.watch(
    runtimeProxiesProvider.select(
      (snapshot) => snapshot.groupById(groupId)?.nowId,
    ),
  );
}

@riverpod
String? activeExitLeafId(Ref ref) {
  if (!ref.watch(proxyGeoSessionActiveProvider)) return null;
  final snapshotGeneration = ref.watch(
    runtimeProxiesProvider.select((state) => state.generation),
  );
  final networkRevision = ref.watch(networkRevisionProvider);
  return ref.watch(
    proxyGeoDataSourceProvider.select((state) {
      if (state.generation != snapshotGeneration ||
          state.networkRevision != networkRevision) {
        return null;
      }
      return state.activeExitLeafId;
    }),
  );
}

@riverpod
ProxyServerGeoEntryState proxyServerGeoEntry(Ref ref, String memberId) {
  return ref.watch(
    proxyGeoDataSourceProvider.select(
      (state) => ProxyServerGeoEntryState(
        value: state.serverByMemberId[memberId],
        loading: state.serverLoadingMemberIds.contains(memberId),
        error: state.serverErrorsByMemberId[memberId],
        stale: state.staleServerMemberIds.contains(memberId),
      ),
    ),
  );
}

@riverpod
ProxyExitGeoEntryState proxyExitGeoEntry(Ref ref, String memberId) {
  final connected = ref.watch(proxyGeoSessionActiveProvider);
  final activeLeafId = ref.watch(activeExitLeafIdProvider);
  return ref.watch(
    proxyGeoDataSourceProvider.select(
      (state) => ProxyExitGeoEntryState(
        value: state.exitByMemberId[memberId],
        loading: state.exitLoadingMemberIds.contains(memberId),
        error: state.exitErrorsByMemberId[memberId],
        stale: state.staleExitMemberIds.contains(memberId),
        active: connected && activeLeafId == memberId,
        connected: connected,
      ),
    ),
  );
}

@riverpod
HotKeyAction getHotKeyAction(Ref ref, HotAction hotAction) {
  return ref.watch(
    hotKeyActionsProvider.select((state) {
      final index = state.indexWhere((item) => item.action == hotAction);
      return index != -1 ? state[index] : HotKeyAction(action: hotAction);
    }),
  );
}

@riverpod
Profile? currentProfile(Ref ref) {
  final profileId = ref.watch(currentProfileIdProvider);
  return ref.watch(
    profilesProvider.select((state) => state.getProfile(profileId)),
  );
}

@riverpod
int proxiesColumns(Ref ref) {
  final contentWidth = ref.watch(contentWidthProvider);
  final proxiesLayout = ref.watch(
    proxiesStyleSettingProvider.select((state) => state.layout),
  );
  return utils.getProxiesColumns(contentWidth, proxiesLayout);
}

@riverpod
SelectedProxyState realSelectedProxyState(Ref ref, String proxyName) {
  return ref.watch(selectedProxyResolverProvider).resolve(proxyName);
}

@riverpod
String? proxyName(Ref ref, String groupName) {
  final proxyName = ref.watch(
    selectedMapProvider.select((state) => state[groupName]),
  );
  return proxyName;
}

@riverpod
String? selectedProxyName(Ref ref, String groupName) {
  final proxyName = ref.watch(proxyNameProvider(groupName));
  final group = ref.watch(
    groupsProvider.select((state) => state.getGroup(groupName)),
  );
  return group?.getCurrentSelectedName(proxyName ?? '');
}

@riverpod
String proxyDesc(Ref ref, Proxy proxy) {
  if (!_groupTypeNames.contains(proxy.type)) {
    return proxy.type;
  } else {
    final groups = ref.watch(groupsProvider);
    final index = groups.indexWhere((element) => element.name == proxy.name);
    if (index == -1) return proxy.type;
    final state = ref.watch(realSelectedProxyStateProvider(proxy.name));
    return "${proxy.type}(${state.proxyName.isNotEmpty ? state.proxyName : '*'})";
  }
}
