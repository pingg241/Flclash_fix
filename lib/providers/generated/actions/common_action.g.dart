// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../../actions/common_action.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CommonAction)
final commonActionProvider = CommonActionProvider._();

final class CommonActionProvider extends $NotifierProvider<CommonAction, void> {
  CommonActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'commonActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$commonActionHash();

  @$internal
  @override
  CommonAction create() => CommonAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$commonActionHash() => r'ef7d169bc9f5bb565563c4b3b0684d5153b0e090';

abstract class _$CommonAction extends $Notifier<void> {
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
