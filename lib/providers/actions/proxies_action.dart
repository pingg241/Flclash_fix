import 'dart:async';

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

@Riverpod(keepAlive: true)
class ProxiesAction extends _$ProxiesAction {
  final Map<String, Future<String>> _providerUpdates = {};
  final Map<String, int> _providerGenerations = {};
  final Map<({int? profileId, String groupName}), int> _selectionGenerations =
      {};

  @override
  void build() {}

  void updateGroupsDebounce([Duration? duration]) {
    debouncer.call(FunctionTag.updateGroups, updateGroups, duration: duration);
  }

  Future<void> changeProxyDebounce(
    String groupName,
    String proxyName, {
    Duration? duration,
  }) {
    final profileId = ref.read(currentProfileIdProvider);
    final key = (profileId: profileId, groupName: groupName);
    final generation = (_selectionGenerations[key] ?? 0) + 1;
    _selectionGenerations[key] = generation;
    return debouncer
        .callAsync<void>(
          (FunctionTag.changeProxy, key),
          () => serializedSetup(() async {
            if (!_isCurrentSelection(key, generation)) {
              return;
            }
            await _executeProxyChange(
              groupName: groupName,
              proxyName: proxyName,
            );
            if (!_isCurrentSelection(key, generation)) {
              return;
            }
            await ref
                .read(profilesActionProvider.notifier)
                .updateCurrentSelectedMap(groupName, proxyName);
            if (!_isCurrentSelection(key, generation)) {
              return;
            }
            await _refreshConnections();
            ref.read(checkIpNumProvider.notifier).add();
            updateGroupsDebounce();
          }),
          duration: duration,
        )
        .whenComplete(() {
          if (_selectionGenerations[key] == generation) {
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

  Future<void> _executeProxyChange({
    required String groupName,
    required String proxyName,
  }) async {
    final message = await ref.read(proxyChangeExecutorProvider)(
      groupName,
      proxyName,
    );
    if (message.isNotEmpty) {
      throw StateError(message);
    }
  }

  Future<void> _refreshConnections() async {
    try {
      await ref.read(proxyConnectionRefresherProvider)();
    } catch (error, stackTrace) {
      commonPrint.log(
        'Proxy changed but connection refresh failed: '
        '$error\n$stackTrace',
        logLevel: LogLevel.warning,
      );
    }
  }

  Future<void> updateGroups() async {
    try {
      commonPrint.log('updateGroups');
      ref.read(groupsProvider.notifier).value = await retry(
        task: () async {
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
          return coreController.getProxiesGroups(
            selectedMap: selectedMap,
            sortType: sortType,
            delayMap: delayMap,
            defaultTestUrl: testUrl,
          );
        },
        retryIf: (res) => res.isEmpty,
      );
    } catch (e) {
      commonPrint.log('updateGroups error: $e');
      ref.read(groupsProvider.notifier).value = [];
    }
  }

  Future<void> updateCurrentGroupName(String groupName) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null || profile.currentGroupName == groupName) return;
    await ref
        .read(profilesProvider.notifier)
        .put(profile.copyWith(currentGroupName: groupName));
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
  }) async {
    await _executeProxyChange(groupName: groupName, proxyName: proxyName);
    await _refreshConnections();
    ref.read(checkIpNumProvider.notifier).add();
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
