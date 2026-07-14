// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../../actions/store_action.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(StoreAction)
final storeActionProvider = StoreActionProvider._();

final class StoreActionProvider extends $NotifierProvider<StoreAction, void> {
  StoreActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'storeActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$storeActionHash();

  @$internal
  @override
  StoreAction create() => StoreAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$storeActionHash() => r'f1df1516c509372f982cab4d2c199392a380becb';

abstract class _$StoreAction extends $Notifier<void> {
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
