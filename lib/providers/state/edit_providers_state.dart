part of '../state.dart';

@riverpod
class AccessControlState extends _$AccessControlState
    with AutoDisposeNotifierMixin {
  @override
  AccessControlProps build() => const AccessControlProps();
}

@Riverpod(name: 'proxyGroupProvider')
class ProxyGroupProvider extends _$ProxyGroupProvider
    with AutoDisposeNotifierMixin {
  @override
  ProxyGroup build() {
    throw 'Initialization proxyGroupProvider error';
  }
}

@Riverpod(name: 'ruleProvider')
class RuleProvider extends _$RuleProvider with AutoDisposeNotifierMixin {
  @override
  Rule build() {
    return throw 'Initialization RuleProvider error';
  }
}

@riverpod
bool suspend(Ref ref) {
  final currentSSID = ref.watch(currentSSIDProvider);
  final excludeSSIDs = ref.watch(excludeSSIDsProvider);
  return excludeSSIDs.contains(currentSSID);
}


