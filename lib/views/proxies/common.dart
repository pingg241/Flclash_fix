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

({String proxyName, String testUrl})? resolveProxyDelayTarget(
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

/// Unique delay targets matching [delayTest] dedupe rules.
List<({Proxy proxy, String testUrl, String proxyName})> collectDelayTargets(
  List<Proxy> proxies, [
  String? testUrl,
]) {
  final seen = <String>{};
  final out = <({Proxy proxy, String testUrl, String proxyName})>[];
  for (final proxy in proxies) {
    final target = resolveProxyDelayTarget(proxy, testUrl);
    if (target == null) {
      continue;
    }
    final key = '${target.testUrl}\u0000${target.proxyName}';
    if (!seen.add(key)) {
      continue;
    }
    out.add((
      proxy: proxy,
      testUrl: target.testUrl,
      proxyName: target.proxyName,
    ));
  }
  return out;
}

int countDelayTestTargets(List<Proxy> proxies, [String? testUrl]) {
  return collectDelayTargets(proxies, testUrl).length;
}

/// Same node set the UI is showing (respects search filter).
int countDelayTestTargetsForCurrentScope({required bool isTab}) {
  final container = globalState.container;
  final query = container.read(queryProvider(QueryTag.proxies));
  if (isTab) {
    final tab = container.read(proxiesTabStateProvider);
    final groups = tab.groups;
    if (groups.isEmpty) {
      return 0;
    }
    final name = tab.currentGroupName;
    final group = name == null
        ? groups.first
        : groups.firstWhere((g) => g.name == name, orElse: () => groups.first);
    // Tab grid uses filtered group.all from proxiesTabState.
    return countDelayTestTargets(group.all, group.testUrl);
  }
  final listGroups = container.read(filterGroupsStateProvider(query)).value;
  var total = 0;
  for (final group in listGroups) {
    total += countDelayTestTargets(group.all, group.testUrl);
  }
  return total;
}

int _delayTestGeneration = 0;
bool _delayTestBusy = false;

/// True while any batch delay test (title / header / card) is running.
bool get isDelayTestBusy => _delayTestBusy;

int get delayTestGeneration => _delayTestGeneration;

/// Bump generation so in-flight workers drop results (profile switch, leave page).
void invalidateDelayTests() {
  _delayTestGeneration += 1;
  _delayTestBusy = false;
}

/// Start a multi-call batch (holds global lock until [endDelayTestBatch]).
int beginDelayTestBatch() {
  _delayTestBusy = true;
  return _delayTestGeneration;
}

void endDelayTestBatch() {
  _delayTestBusy = false;
}

Future<void> proxyDelayTest(
  Proxy proxy, [
  String? testUrl,
  int? generation,
]) async {
  final target = resolveProxyDelayTarget(proxy, testUrl);
  if (target == null) {
    return;
  }
  final gen = generation ?? _delayTestGeneration;
  final delay = await coreController.getDelay(target.testUrl, target.proxyName);
  if (gen != _delayTestGeneration) {
    return;
  }
  globalState.container.read(proxiesActionProvider.notifier).setDelay(delay);
}

/// Batch delay test. [onProgress](done, total); respects [generation] / [isStale].
Future<void> delayTest(
  List<Proxy> proxies, {
  String? testUrl,
  void Function(int done, int total)? onProgress,
  int? generation,
  bool Function()? isStale,
  bool acquireGlobalLock = true,
}) async {
  if (acquireGlobalLock) {
    if (_delayTestBusy) {
      return;
    }
    _delayTestBusy = true;
  }
  final gen = generation ?? _delayTestGeneration;
  try {
    final targets = collectDelayTargets(proxies, testUrl);
    final total = targets.length;
    if (total == 0) {
      onProgress?.call(0, 0);
      return;
    }

    final delays = [
      for (final t in targets)
        Delay(url: t.testUrl, name: t.proxyName, value: 0),
    ];
    globalState.container.read(proxiesActionProvider.notifier).setDelays(delays);
    onProgress?.call(0, total);

    const maxConcurrent = 32;
    var nextIndex = 0;
    var done = 0;

    Future<void> worker() async {
      while (true) {
        if (isStale?.call() == true || gen != _delayTestGeneration) {
          return;
        }
        final i = nextIndex;
        if (i >= targets.length) {
          break;
        }
        nextIndex = i + 1;
        final t = targets[i];
        await proxyDelayTest(t.proxy, t.testUrl, gen);
        if (isStale?.call() == true || gen != _delayTestGeneration) {
          return;
        }
        done += 1;
        onProgress?.call(done, total);
      }
    }

    final workers = List.generate(
      min(maxConcurrent, targets.length),
      (_) => worker(),
    );
    await Future.wait(workers);
    if (isStale?.call() != true && gen == _delayTestGeneration) {
      globalState.container.read(sortNumProvider.notifier).add();
    }
  } finally {
    if (acquireGlobalLock) {
      _delayTestBusy = false;
    }
  }
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
