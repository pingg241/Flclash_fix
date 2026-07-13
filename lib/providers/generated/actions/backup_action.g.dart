// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../../actions/backup_action.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(BackupAction)
final backupActionProvider = BackupActionProvider._();

final class BackupActionProvider extends $NotifierProvider<BackupAction, void> {
  BackupActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupActionHash();

  @$internal
  @override
  BackupAction create() => BackupAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$backupActionHash() => r'4953679dac7f99f6e076720a2a6f9750a22fd74f';

abstract class _$BackupAction extends $Notifier<void> {
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
