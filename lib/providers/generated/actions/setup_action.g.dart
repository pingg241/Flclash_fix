// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../../actions/setup_action.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SetupAction)
final setupActionProvider = SetupActionProvider._();

final class SetupActionProvider extends $NotifierProvider<SetupAction, void> {
  SetupActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'setupActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$setupActionHash();

  @$internal
  @override
  SetupAction create() => SetupAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$setupActionHash() => r'42194b670a037ab5c4ea0832760a3da62aef3a9f';

abstract class _$SetupAction extends $Notifier<void> {
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
