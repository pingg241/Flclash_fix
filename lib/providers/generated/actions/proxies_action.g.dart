// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../../actions/proxies_action.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ProxiesAction)
final proxiesActionProvider = ProxiesActionProvider._();

final class ProxiesActionProvider
    extends $NotifierProvider<ProxiesAction, void> {
  ProxiesActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'proxiesActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$proxiesActionHash();

  @$internal
  @override
  ProxiesAction create() => ProxiesAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$proxiesActionHash() => r'689265b4d162127e20e1f8abc7db9c0424215fa6';

abstract class _$ProxiesAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
