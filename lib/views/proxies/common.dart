import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

double get listHeaderHeight {
  final measure = globalState.measure;
  return 20 + measure.titleMediumHeight + 4 + measure.bodyMediumHeight + 2;
}

double getItemHeight(ProxyCardType proxyCardType) {
  final measure = globalState.measure;
  final baseHeight =
      16 + measure.bodyMediumHeight * 2 + measure.bodySmallHeight + 8 + 4;
  return switch (proxyCardType) {
    ProxyCardType.expand => baseHeight + measure.labelSmallHeight + 6,
    ProxyCardType.shrink => baseHeight,
    ProxyCardType.min => baseHeight - measure.bodyMediumHeight,
  };
}

List<Group> getCurrentGroups() {
  return globalState.container.read(currentGroupsStateProvider).value;
}

List<Group> getGroups() {
  return globalState.container.read(groupsProvider);
}

String? getCurrentGroupName() {
  return globalState.container.read(
    currentProfileProvider.select((state) => state?.currentGroupName),
  );
}

void updateCurrentGroupName(String groupName) {
  globalState.container
      .read(proxiesActionProvider.notifier)
      .updateCurrentGroupName(groupName);
}

void updateCurrentUnfoldSet(Set<String> value) {
  globalState.container
      .read(proxiesActionProvider.notifier)
      .updateCurrentUnfoldSet(value);
}

({String proxyName, String testUrl})? _resolveProxyDelayTarget(
  Proxy proxy, [
  String? testUrl,
]) {
  final ref = globalState.container;
  final groups = getGroups();
  final selectedMap = ref.read(
    currentProfileProvider.select((state) => state?.selectedMap ?? {}),
  );
  final state = computeRealSelectedProxyState(
    proxy.name,
    groups: groups,
    selectedMap: selectedMap,
  );
  final currentTestUrl = state.testUrl.takeFirstValid([
    ref.read(realTestUrlProvider(testUrl)),
  ]);
  if (state.proxyName.isEmpty) {
    return null;
  }
  return (proxyName: state.proxyName, testUrl: currentTestUrl);
}

Future<void> proxyDelayTest(Proxy proxy, [String? testUrl]) async {
  final target = _resolveProxyDelayTarget(proxy, testUrl);
  if (target == null) {
    return;
  }
  final ref = globalState.container;
  ref
      .read(proxiesActionProvider.notifier)
      .setDelay(
        await coreController.getDelay(target.testUrl, target.proxyName),
      );
}

Future<void> delayTest(List<Proxy> proxies, [String? testUrl]) async {
  if (proxies.isEmpty) {
    return;
  }

  final ref = globalState.container;
  final delays = <Delay>[];
  final seen = <String>{};
  for (final proxy in proxies) {
    final target = _resolveProxyDelayTarget(proxy, testUrl);
    if (target == null) {
      continue;
    }
    final key = '${target.testUrl}\u0000${target.proxyName}';
    if (!seen.add(key)) {
      continue;
    }
    delays.add(
      Delay(url: target.testUrl, name: target.proxyName, value: 0),
    );
  }
  if (delays.isNotEmpty) {
    ref.read(proxiesActionProvider.notifier).setDelays(delays);
  }

  const maxConcurrent = 32;
  var index = 0;
  Future<void> worker() async {
    while (true) {
      final i = index;
      if (i >= proxies.length) {
        break;
      }
      index = i + 1;
      await proxyDelayTest(proxies[i], testUrl);
    }
  }

  final workers = List.generate(
    min(maxConcurrent, proxies.length),
    (_) => worker(),
  );
  await Future.wait(workers);
  globalState.container.read(sortNumProvider.notifier).add();
}

double getScrollToSelectedOffset({
  required String groupName,
  required List<Proxy> proxies,
}) {
  final ref = globalState.container;
  final columns = ref.read(proxiesColumnsProvider);
  final proxyCardType = ref.read(
    proxiesStyleSettingProvider.select((state) => state.cardType),
  );
  final selectedProxyName = ref.read(selectedProxyNameProvider(groupName));
  final findSelectedIndex = proxies.indexWhere(
    (proxy) => proxy.name == selectedProxyName,
  );
  final selectedIndex = findSelectedIndex != -1 ? findSelectedIndex : 0;
  final rows = (selectedIndex / columns).floor();
  return rows * getItemHeight(proxyCardType) + (rows - 1) * 8;
}
