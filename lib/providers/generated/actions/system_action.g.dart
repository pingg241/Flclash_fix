// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../../actions/system_action.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SystemAction)
final systemActionProvider = SystemActionProvider._();

final class SystemActionProvider extends $NotifierProvider<SystemAction, void> {
  SystemActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'systemActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$systemActionHash();

  @$internal
  @override
  SystemAction create() => SystemAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$systemActionHash() => r'0caaeb523f6ef640dd3a11beee9def10997759d0';

abstract class _$SystemAction extends $Notifier<void> {
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
