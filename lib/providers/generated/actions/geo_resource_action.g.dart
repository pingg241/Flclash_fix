// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../../actions/geo_resource_action.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(GeoResourceAction)
final geoResourceActionProvider = GeoResourceActionProvider._();

final class GeoResourceActionProvider
    extends $NotifierProvider<GeoResourceAction, void> {
  GeoResourceActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'geoResourceActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$geoResourceActionHash();

  @$internal
  @override
  GeoResourceAction create() => GeoResourceAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$geoResourceActionHash() => r'980385b1cc4e685e0e2732471083c63d29b59c10';

abstract class _$GeoResourceAction extends $Notifier<void> {
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
