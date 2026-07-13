// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../../actions/theme_action.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ThemeAction)
final themeActionProvider = ThemeActionProvider._();

final class ThemeActionProvider extends $NotifierProvider<ThemeAction, void> {
  ThemeActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'themeActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$themeActionHash();

  @$internal
  @override
  ThemeAction create() => ThemeAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$themeActionHash() => r'9802c7ba8247f8c2d396fab398642567d8eecf62';

abstract class _$ThemeAction extends $Notifier<void> {
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
