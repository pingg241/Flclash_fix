import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

List<Group> computeSort({
  required List<Group> groups,
  required ProxiesSortType sortType,
  required DelayMap delayMap,
  required Map<String, String> selectedMap,
  required String defaultTestUrl,
}) {
  final resolver = SelectedProxyResolver(groups, selectedMap);

  List<Proxy> sortOfDelay({
    required List<Proxy> proxies,
    required DelayMap delayMap,
    required String testUrl,
  }) {
    final delayStates = <String, DelayState>{
      for (final proxy in proxies)
        proxy.name: _computeProxyDelayState(
          proxyName: proxy.name,
          testUrl: testUrl,
          resolver: resolver,
          delayMap: delayMap,
        ),
    };
    return List.from(proxies)..sort((a, b) {
      return delayStates[a.name]!.compareTo(delayStates[b.name]!);
    });
  }

  List<Proxy> sortOfName(List<Proxy> proxies) {
    return List.of(proxies)..sort((a, b) => a.name.compareTo(b.name));
  }

  return groups.map((group) {
    final proxies = group.all;
    final newProxies = switch (sortType) {
      ProxiesSortType.none => proxies,
      ProxiesSortType.delay => sortOfDelay(
        proxies: proxies,
        delayMap: delayMap,
        testUrl: group.testUrl.takeFirstValid([defaultTestUrl]),
      ),
      ProxiesSortType.name => sortOfName(proxies),
    };
    return group.copyWith(all: newProxies);
  }).toList();
}

class SelectedProxyResolver {
  final Map<String, Group> _groups = {};
  final Map<String, String> _selectedMap;
  final Map<String, SelectedProxyState> _cache = {};

  SelectedProxyResolver(List<Group> groups, this._selectedMap) {
    for (final group in groups) {
      _groups.putIfAbsent(group.name, () => group);
    }
  }

  SelectedProxyState resolve(String proxyName) {
    if (proxyName.isEmpty) {
      return const SelectedProxyState(proxyName: '');
    }
    final cached = _cache[proxyName];
    if (cached != null) {
      return cached;
    }

    var state = SelectedProxyState(proxyName: proxyName);
    final visited = <String>{};
    while (state.proxyName.isNotEmpty) {
      final group = _groups[state.proxyName];
      state = state.copyWith(group: true);
      if (group == null || !visited.add(state.proxyName)) {
        break;
      }
      final selectedName = group.getCurrentSelectedName(
        _selectedMap[state.proxyName] ?? '',
      );
      if (selectedName.isEmpty) {
        break;
      }
      state = state.copyWith(proxyName: selectedName, testUrl: group.testUrl);
    }
    _cache[proxyName] = state;
    return state;
  }
}

SelectedProxyState computeRealSelectedProxyState(
  String proxyName, {
  required List<Group> groups,
  required Map<String, String> selectedMap,
}) {
  return SelectedProxyResolver(groups, selectedMap).resolve(proxyName);
}

DelayState computeProxyDelayState({
  required String proxyName,
  required String testUrl,
  required List<Group> groups,
  required Map<String, String> selectedMap,
  required DelayMap delayMap,
}) {
  return _computeProxyDelayState(
    proxyName: proxyName,
    testUrl: testUrl,
    resolver: SelectedProxyResolver(groups, selectedMap),
    delayMap: delayMap,
  );
}

DelayState _computeProxyDelayState({
  required String proxyName,
  required String testUrl,
  required SelectedProxyResolver resolver,
  required DelayMap delayMap,
}) {
  final state = resolver.resolve(proxyName);
  final currentDelayMap =
      delayMap[state.testUrl.takeFirstValid([testUrl])] ?? {};
  final delay = currentDelayMap[state.proxyName];
  return DelayState(delay: delay ?? 0, group: state.group);
}
