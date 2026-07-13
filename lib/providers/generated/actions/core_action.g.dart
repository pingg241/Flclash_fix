// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../../actions/core_action.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CoreAction)
final coreActionProvider = CoreActionProvider._();

final class CoreActionProvider extends $NotifierProvider<CoreAction, void> {
  CoreActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'coreActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$coreActionHash();

  @$internal
  @override
  CoreAction create() => CoreAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$coreActionHash() => r'e2ebb77612364222abab34f015b76646746c07d5';

abstract class _$CoreAction extends $Notifier<void> {
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
