// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../../actions/profiles_action.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ProfilesAction)
final profilesActionProvider = ProfilesActionProvider._();

final class ProfilesActionProvider
    extends $NotifierProvider<ProfilesAction, void> {
  ProfilesActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'profilesActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$profilesActionHash();

  @$internal
  @override
  ProfilesAction create() => ProfilesAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$profilesActionHash() => r'1048e81651c1a0fba585f0868b0a02ac4076d138';

abstract class _$ProfilesAction extends $Notifier<void> {
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
