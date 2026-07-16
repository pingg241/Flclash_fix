import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part '../generated/actions/profiles_action.g.dart';

typedef ProfileUpdater =
    Future<Profile> Function(
      Profile profile,
      bool Function() shouldSave,
      Future<void> Function(Profile profile) onCommit,
    );
typedef ProfileStatusUpdater = Future<bool> Function(bool wantStart);
typedef ProfileEffectCleaner = Future<void> Function(int profileId);
typedef ProfileFileCleaner = Future<void> Function(int profileId);
typedef ProfileSwitchApplier = Future<void> Function();
typedef ProfileSwitchClearer = Future<bool> Function();
typedef ProfileSwitchPersister = Future<void> Function();
typedef ProfileRollbackFailureHandler = Future<void> Function();

class ProfileSwitchException implements Exception {
  final Object setupError;
  final List<Object> rollbackErrors;

  const ProfileSwitchException(this.setupError, this.rollbackErrors);

  @override
  String toString() {
    if (rollbackErrors.isEmpty) {
      return 'Profile switch failed: $setupError';
    }
    return 'Profile switch failed: $setupError; rollback failed: '
        '${rollbackErrors.join('; ')}';
  }
}

class ProfileOperationException implements Exception {
  final String operation;
  final Object error;
  final List<Object> rollbackErrors;

  const ProfileOperationException(
    this.operation,
    this.error,
    this.rollbackErrors,
  );

  @override
  String toString() {
    return 'Profile $operation failed: $error; rollback failed: '
        '${rollbackErrors.join('; ')}';
  }
}

final profileUpdaterProvider = Provider<ProfileUpdater>(
  (_) =>
      (profile, shouldSave, onCommit) =>
          profile.update(shouldSave: shouldSave, onCommit: onCommit),
);
final profileStatusUpdaterProvider = Provider<ProfileStatusUpdater>(
  (ref) =>
      (wantStart) =>
          ref.read(setupActionProvider.notifier).updateStatus(wantStart),
);
final profileEffectCleanerProvider = Provider<ProfileEffectCleaner>(
  (_) => _clearProfileProviderCache,
);
final profileFileCleanerProvider = Provider<ProfileFileCleaner>(
  (_) => _clearProfileFile,
);
final profileSwitchApplierProvider = Provider<ProfileSwitchApplier>(
  (ref) =>
      () => ref
          .read(setupActionProvider.notifier)
          .fullSetup(toleratePostApplyFailure: true),
);
final profileSwitchClearerProvider = Provider<ProfileSwitchClearer>(
  (ref) =>
      () => ref.read(profileStatusUpdaterProvider)(false),
);
final profileSwitchPersisterProvider = Provider<ProfileSwitchPersister>(
  (ref) => ref.read(storeActionProvider.notifier).flushPreferences,
);
final profileRollbackFailureHandlerProvider =
    Provider<ProfileRollbackFailureHandler>((ref) {
      return () async {
        final setup = ref.read(setupActionProvider.notifier);
        if (!setup.isStart) return;
        if (!await setup.handleStop()) {
          throw StateError('failed to stop after profile rollback failure');
        }
      };
    });

@Riverpod(keepAlive: true)
class ProfilesAction extends _$ProfilesAction {
  static final Object _profileUpdateZoneKey = Object();

  final Map<int, Future<bool>> _updates = {};
  final Map<int, Future<void>> _deletions = {};
  final Set<int> _activeDeletionIds = {};
  final Map<int, int> _generations = {};
  Future<void> _deleteTail = Future<void>.value();
  Future<void> _profileSwitchTail = Future<void>.value();
  _ActiveProfileSwitch? _activeProfileSwitch;
  int _profileSwitchGeneration = 0;
  int _currentProfileWriteDepth = 0;
  int? _appliedProfileId;

  @override
  void build() {
    _appliedProfileId = ref.read(currentProfileIdProvider);
  }

  bool get isChangingCurrentProfile => _currentProfileWriteDepth > 0;

  Future<bool> selectProfile(int? nextId) {
    return _selectProfile(nextId);
  }

  Future<bool> applyExternalProfileSelection(int? nextId) {
    if (ref.read(currentProfileIdProvider) != nextId) {
      return Future<bool>.value(false);
    }
    final active = _activeProfileSwitch;
    if (active != null &&
        active.nextId == nextId &&
        ref.read(currentProfileIdProvider) == nextId) {
      return active.operation;
    }
    return _scheduleProfileSwitch(nextId);
  }

  Future<bool> _selectProfile(
    int? nextId, {
    int? allowedDeletingProfileId,
    bool skipClearStop = false,
  }) {
    final active = _activeProfileSwitch;
    if (active != null &&
        active.nextId == nextId &&
        ref.read(currentProfileIdProvider) == nextId) {
      return active.operation;
    }
    if (ref.read(currentProfileIdProvider) == nextId) {
      if (_appliedProfileId == nextId) {
        return Future<bool>.value(true);
      }
      return _scheduleProfileSwitch(
        nextId,
        allowedDeletingProfileId: allowedDeletingProfileId,
        skipClearStop: skipClearStop,
      );
    }
    if (nextId != null &&
        _activeDeletionIds.contains(nextId) &&
        nextId != allowedDeletingProfileId) {
      return Future<bool>.error(
        StateError('Cannot select a profile while it is being deleted'),
      );
    }
    if (nextId != null &&
        ref.read(profilesProvider).getProfile(nextId) == null) {
      return Future<bool>.error(StateError('Profile $nextId does not exist'));
    }
    _setCurrentProfileId(nextId);
    return _scheduleProfileSwitch(
      nextId,
      allowedDeletingProfileId: allowedDeletingProfileId,
      skipClearStop: skipClearStop,
    );
  }

  Future<bool> _scheduleProfileSwitch(
    int? nextId, {
    int? allowedDeletingProfileId,
    bool skipClearStop = false,
  }) {
    final generation = ++_profileSwitchGeneration;
    final previousOperation = _profileSwitchTail;
    late final Future<bool> operation;
    operation = () async {
      await previousOperation;
      if (!_isCurrentProfileSwitch(generation, nextId)) {
        return false;
      }
      return _performProfileSwitch(
        nextId,
        generation,
        allowedDeletingProfileId: allowedDeletingProfileId,
        skipClearStop: skipClearStop,
      );
    }();
    _activeProfileSwitch = _ActiveProfileSwitch(nextId, operation);
    _profileSwitchTail = operation.then<void>(
      (_) {
        if (identical(_activeProfileSwitch?.operation, operation)) {
          _activeProfileSwitch = null;
        }
      },
      onError: (Object _, StackTrace _) {
        if (identical(_activeProfileSwitch?.operation, operation)) {
          _activeProfileSwitch = null;
        }
      },
    );
    return operation;
  }

  Future<bool> _performProfileSwitch(
    int? nextId,
    int generation, {
    int? allowedDeletingProfileId,
    required bool skipClearStop,
  }) async {
    final previousId = _appliedProfileId;
    try {
      if (nextId != null) {
        if ((_activeDeletionIds.contains(nextId) &&
                nextId != allowedDeletingProfileId) ||
            ref.read(profilesProvider).getProfile(nextId) == null) {
          throw StateError('Profile $nextId is unavailable');
        }
        await ref.read(profileSwitchApplierProvider)();
      } else if (!skipClearStop &&
          (ref.read(isStartProvider) || ref.read(isStartingProvider))) {
        final stopped = await ref.read(profileSwitchClearerProvider)();
        if (!stopped) {
          throw const _ProfileClearRejected();
        }
      }
      _appliedProfileId = nextId;
      return _isCurrentProfileSwitch(generation, nextId);
    } catch (error, stackTrace) {
      if (!_isCurrentProfileSwitch(generation, nextId)) {
        return false;
      }
      final rollbackErrors = <Object>[];
      try {
        _setCurrentProfileId(previousId);
      } catch (rollbackError) {
        rollbackErrors.add(rollbackError);
      }
      try {
        await ref.read(profileSwitchPersisterProvider)();
      } catch (rollbackError) {
        rollbackErrors.add(rollbackError);
      }
      if (generation != _profileSwitchGeneration) {
        return false;
      }
      if (previousId != null && error is! _ProfileClearRejected) {
        try {
          await ref.read(profileSwitchApplierProvider)();
          _appliedProfileId = previousId;
        } catch (rollbackError) {
          rollbackErrors.add(rollbackError);
        }
      }
      if (generation != _profileSwitchGeneration) {
        return false;
      }
      if (rollbackErrors.isNotEmpty) {
        try {
          await ref.read(profileRollbackFailureHandlerProvider)();
        } catch (rollbackError) {
          rollbackErrors.add(rollbackError);
        }
      }
      Error.throwWithStackTrace(
        ProfileSwitchException(error, rollbackErrors),
        stackTrace,
      );
    }
  }

  bool _isCurrentProfileSwitch(int generation, int? nextId) {
    return generation == _profileSwitchGeneration &&
        ref.read(currentProfileIdProvider) == nextId;
  }

  void _setCurrentProfileId(int? profileId) {
    _currentProfileWriteDepth++;
    try {
      ref.read(currentProfileIdProvider.notifier).value = profileId;
    } finally {
      _currentProfileWriteDepth--;
    }
  }

  Future<void> updateCurrentSelectedMap(
    String groupName,
    String proxyName, {
    String? groupStableKey,
    String? proxyStableKey,
  }) async {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile != null) {
      final legacyChanged = currentProfile.selectedMap[groupName] != proxyName;
      final hasStableSelection =
          groupStableKey?.isNotEmpty == true &&
          proxyStableKey?.isNotEmpty == true;
      final stableChanged =
          hasStableSelection &&
          currentProfile.selectedStableMap[groupStableKey] != proxyStableKey;
      if (!legacyChanged && !stableChanged) {
        return;
      }
      final selectedMap = Map<String, String>.from(currentProfile.selectedMap)
        ..[groupName] = proxyName;
      final selectedStableMap = Map<String, String>.from(
        currentProfile.selectedStableMap,
      );
      if (hasStableSelection) {
        selectedStableMap[groupStableKey!] = proxyStableKey!;
      }
      await ref
          .read(profilesProvider.notifier)
          .put(
            currentProfile.copyWith(
              selectedMap: selectedMap,
              selectedStableMap: selectedStableMap,
            ),
          );
    }
  }

  Future<void> deleteProfile(int id) {
    if (Zone.current[_profileUpdateZoneKey] == id) {
      return Future<void>.error(
        StateError('Cannot delete a profile from its active update'),
      );
    }
    final activeDeletion = _deletions[id];
    if (activeDeletion != null) {
      return activeDeletion;
    }
    final previousDeletion = _deleteTail;
    late final Future<void> deletion;
    deletion = () async {
      try {
        await previousDeletion;
      } catch (_) {}
      _activeDeletionIds.add(id);
      try {
        await _deleteProfile(id);
      } finally {
        _activeDeletionIds.remove(id);
      }
    }();
    _deletions[id] = deletion;
    _deleteTail = deletion;
    return deletion.whenComplete(() {
      if (identical(_deletions[id], deletion)) {
        _deletions.remove(id);
      }
    });
  }

  Future<void> _deleteProfile(int id) async {
    invalidateProfileUpdate(id);
    final activeUpdate = _updates[id];
    if (activeUpdate != null) {
      try {
        await activeUpdate;
      } catch (error, stackTrace) {
        commonPrint.log(
          'Profile $id update settled with ${error.runtimeType} before '
          'deletion\n$stackTrace',
          logLevel: LogLevel.warning,
        );
      }
    }
    final currentProfileId = ref.read(currentProfileIdProvider);
    final remainingProfiles = ref
        .read(profilesProvider)
        .where((profile) => profile.id != id)
        .toList();
    final isCurrentProfile = currentProfileId == id;
    final wasRunning =
        ref.read(isStartProvider) || ref.read(isStartingProvider);
    var stopped = false;
    if (isCurrentProfile) {
      try {
        if (remainingProfiles.isNotEmpty) {
          final switched = await _selectProfile(remainingProfiles.first.id);
          if (!switched) {
            throw StateError('Profile switch was superseded before deletion');
          }
        } else {
          if (wasRunning) {
            stopped = await ref.read(profileStatusUpdaterProvider)(false);
            if (!stopped) {
              throw StateError(
                'Failed to stop before deleting the last profile',
              );
            }
          }
          final cleared = await _selectProfile(null, skipClearStop: stopped);
          if (!cleared) {
            throw StateError(
              'Profile selection clear was superseded before deletion',
            );
          }
        }
      } catch (error, stackTrace) {
        final rollbackErrors = <Object>[];
        if (stopped && wasRunning) {
          await _restoreProfileStatus(rollbackErrors);
        }
        if (rollbackErrors.isNotEmpty) {
          Error.throwWithStackTrace(
            ProfileOperationException('deletion', error, rollbackErrors),
            stackTrace,
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    try {
      await ref.read(profilesProvider.notifier).del(id);
    } catch (error, stackTrace) {
      final rollbackErrors = <Object>[];
      if (isCurrentProfile) {
        try {
          final restored = await _selectProfile(
            id,
            allowedDeletingProfileId: id,
          );
          if (!restored) {
            rollbackErrors.add(
              StateError('Previous profile selection restore was superseded'),
            );
          }
        } catch (rollbackError) {
          rollbackErrors.add(rollbackError);
        }
        if (stopped && wasRunning && rollbackErrors.isEmpty) {
          await _restoreProfileStatus(rollbackErrors);
        }
      }
      if (rollbackErrors.isNotEmpty) {
        Error.throwWithStackTrace(
          ProfileOperationException('deletion', error, rollbackErrors),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    await _runProfileCleanup(
      id,
      'provider cache',
      () => ref.read(profileEffectCleanerProvider)(id),
    );
    await _runProfileCleanup(
      id,
      'profile file',
      () => ref.read(profileFileCleanerProvider)(id),
    );
  }

  void invalidateProfileUpdate(int id) {
    _generations[id] = (_generations[id] ?? 0) + 1;
  }

  Future<void> autoUpdateProfiles() async {
    for (final profile in ref.read(profilesProvider)) {
      if (!profile.autoUpdate) continue;
      final isNotNeedUpdate = profile.lastUpdateDate
          ?.add(profile.autoUpdateDuration)
          .isBeforeNow;
      if (isNotNeedUpdate == false || profile.type == ProfileType.file) {
        continue;
      }
      try {
        await updateProfile(profile);
      } catch (e) {
        commonPrint.log(e.toString(), logLevel: LogLevel.warning);
      }
    }
  }

  Future<void> putProfile(Profile profile) async {
    await ref.read(profilesProvider.notifier).put(profile);
    if (ref.read(currentProfileIdProvider) != null) return;
    final switched = await selectProfile(profile.id);
    if (!switched) {
      throw StateError('Profile switch was superseded');
    }
  }

  Future<void> addProfile(Profile profile) async {
    if (ref.read(profilesProvider).getProfile(profile.id) != null) {
      throw StateError('Profile ${profile.id} already exists');
    }
    var metadataStored = false;
    try {
      await ref.read(profilesProvider.notifier).put(profile);
      metadataStored = true;
      if (ref.read(currentProfileIdProvider) == null) {
        final switched = await selectProfile(profile.id);
        if (!switched) {
          throw StateError('Profile switch was superseded');
        }
      }
    } catch (error, stackTrace) {
      final rollbackErrors = <Object>[];
      var canRemoveProfileFiles = true;
      if (metadataStored ||
          ref.read(profilesProvider).getProfile(profile.id) != null) {
        try {
          await ref.read(profilesProvider.notifier).del(profile.id);
        } catch (rollbackError) {
          rollbackErrors.add(rollbackError);
          canRemoveProfileFiles = false;
        }
      }
      if (canRemoveProfileFiles) {
        for (final cleanup in <Future<void> Function()>[
          () => ref.read(profileEffectCleanerProvider)(profile.id),
          () => ref.read(profileFileCleanerProvider)(profile.id),
        ]) {
          try {
            await cleanup();
          } catch (rollbackError) {
            rollbackErrors.add(rollbackError);
          }
        }
      }
      if (rollbackErrors.isNotEmpty) {
        Error.throwWithStackTrace(
          ProfileOperationException('addition', error, rollbackErrors),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<Map<int, Object>> updateProfiles({
    Iterable<Profile>? profiles,
    bool showLoading = false,
  }) async {
    final Iterable<Profile> source = profiles ?? ref.read(profilesProvider);
    final pending = source
        .where((profile) => profile.type != ProfileType.file)
        .toList();
    return _updateProfilesConcurrently(pending, showLoading: showLoading);
  }

  Future<bool> updateProfile(
    Profile profile, {
    bool showLoading = false,
    bool replaceProfile = false,
  }) {
    if (_activeDeletionIds.contains(profile.id)) {
      return Future<bool>.value(false);
    }
    final generation = (_generations[profile.id] ?? 0) + 1;
    _generations[profile.id] = generation;
    final previous = _updates[profile.id];
    late final Future<bool> request;
    request = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      return runZoned(
        () => _performProfileUpdate(
          profile,
          generation,
          showLoading,
          replaceProfile,
        ),
        zoneValues: {_profileUpdateZoneKey: profile.id},
      );
    }();
    _updates[profile.id] = request;
    return request.whenComplete(() {
      if (identical(_updates[profile.id], request)) {
        _updates.remove(profile.id);
      }
    });
  }

  Future<bool> _performProfileUpdate(
    Profile profile,
    int generation,
    bool showLoading,
    bool replaceProfile,
  ) async {
    try {
      if (_generations[profile.id] != generation) {
        return false;
      }
      if (showLoading) {
        ref.read(isUpdatingProvider(profile.updatingKey).notifier).value = true;
      }
      final expectedProfile = ref.read(profilesProvider).getProfile(profile.id);
      if (expectedProfile == null) {
        return false;
      }
      final expectedVersion = _profileUpdateVersion(expectedProfile);
      var activeVersion = expectedVersion;
      final sourceProfile = replaceProfile ? profile : expectedProfile;
      try {
        await ref.read(profileUpdaterProvider)(
          sourceProfile,
          () {
            final current = ref.read(profilesProvider).getProfile(profile.id);
            return _generations[profile.id] == generation &&
                _profileUpdateVersion(current) == activeVersion;
          },
          (newProfile) async {
            final current = ref.read(profilesProvider).getProfile(profile.id);
            if (_generations[profile.id] != generation ||
                _profileUpdateVersion(current) != expectedVersion ||
                current == null) {
              throw const ProfileUpdateCancelled();
            }
            final put = ref
                .read(profilesProvider.notifier)
                .put(
                  newProfile.copyWith(
                    currentGroupName: current.currentGroupName,
                    selectedMap: current.selectedMap,
                    selectedStableMap: current.selectedStableMap,
                    unfoldSet: current.unfoldSet,
                    order: current.order,
                  ),
                );
            activeVersion = _profileUpdateVersion(
              ref.read(profilesProvider).getProfile(profile.id),
            );
            await put;
          },
        );
      } on ProfileUpdateCancelled {
        return false;
      }
      if (_generations[profile.id] != generation ||
          ref.read(profilesProvider).getProfile(profile.id) == null) {
        return false;
      }
      if (profile.id == ref.read(currentProfileIdProvider)) {
        ref
            .read(setupActionProvider.notifier)
            .applyProfileDebounce(silence: true);
      }
      return true;
    } finally {
      ref.read(isUpdatingProvider(profile.updatingKey).notifier).value = false;
    }
  }

  Future<void> _restoreProfileStatus(List<Object> rollbackErrors) async {
    try {
      final restored = await ref.read(profileStatusUpdaterProvider)(true);
      if (!restored) {
        rollbackErrors.add(StateError('Status updater returned false'));
      }
    } catch (error) {
      rollbackErrors.add(error);
    }
  }

  Future<Map<int, Object>> _updateProfilesConcurrently(
    List<Profile> profiles, {
    required bool showLoading,
  }) async {
    final errors = <int, Object>{};
    var nextIndex = 0;
    Future<void> worker() async {
      while (nextIndex < profiles.length) {
        final profile = profiles[nextIndex++];
        try {
          await updateProfile(profile, showLoading: showLoading);
        } catch (error) {
          errors[profile.id] = error;
        }
      }
    }

    final workerCount = profiles.length < 4 ? profiles.length : 4;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return errors;
  }

  Future<void> addProfileFormFile() async {
    final platformFile = await globalState.safeRun(picker.pickerFile);
    if (platformFile == null) return;
    final bytes = await platformFile.readBytes(
      maxBytes: ExternalInputLimits.profileBytes,
      inputName: 'Profile',
    );
    globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    ref.read(currentPageLabelProvider.notifier).toProfiles();
    await globalState.loadingRun<void>(tag: LoadingTag.profiles, () async {
      final profile = await Profile.normal(
        label: platformFile.name,
      ).saveFile(bytes);
      await addProfile(profile);
    }, title: currentAppLocalizations.addProfile);
  }

  Future<void> addProfileFormURL(String url) async {
    if (globalState.navigatorKey.currentState?.canPop() ?? false) {
      globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
    ref.read(currentPageLabelProvider.notifier).value = PageLabel.profiles;
    await globalState.loadingRun<void>(tag: LoadingTag.profiles, () async {
      final profile = await Profile.normal(url: url).update();
      await addProfile(profile);
    }, title: currentAppLocalizations.addProfile);
  }

  Future<void> setProfileAndAutoApply(Profile profile) async {
    await ref.read(profilesProvider.notifier).put(profile);
    if (profile.id == ref.read(currentProfileIdProvider)) {
      ref.read(setupActionProvider.notifier).applyProfileDebounce();
    }
  }

  Future<void> addProfileFormQrCode() async {
    final url = await globalState.safeRun(picker.pickerConfigQRCode);
    if (url == null) return;
    await addProfileFormURL(url);
  }

  Future<void> reorder(List<Profile> profiles) {
    return ref.read(profilesProvider.notifier).reorder(profiles);
  }

  Future<void> clearEffect(int profileId) async {
    await _clearProfileProviderCache(profileId);
    await _clearProfileFile(profileId);
  }
}

Future<void> _clearProfileProviderCache(int profileId) async {
  final providersDirPath = await appPath.getProvidersDirPath(
    profileId.toString(),
  );
  final error = await coreController.deleteFile(providersDirPath);
  throwIfFileSystemOperationFailed(error, providersDirPath);
}

Future<void> _clearProfileFile(int profileId) async {
  final profilePath = await appPath.getProfilePath(profileId.toString());
  final profileFile = File(profilePath);
  final isExists = await profileFile.exists();
  if (isExists) {
    await profileFile.safeDelete(recursive: true);
  }
}

Future<void> _runProfileCleanup(
  int profileId,
  String target,
  Future<void> Function() cleanup,
) async {
  try {
    await cleanup();
  } catch (error, stackTrace) {
    commonPrint.log(
      'Profile $profileId $target cleanup failed: $error\n$stackTrace',
      logLevel: LogLevel.warning,
    );
  }
}

class _ActiveProfileSwitch {
  final int? nextId;
  final Future<bool> operation;

  const _ActiveProfileSwitch(this.nextId, this.operation);
}

class _ProfileClearRejected implements Exception {
  const _ProfileClearRejected();

  @override
  String toString() => 'Failed to stop before clearing the active profile';
}

typedef _ProfileUpdateVersion = ({
  int id,
  String label,
  String url,
  bool autoUpdate,
  Duration autoUpdateDuration,
  OverwriteType overwriteType,
  int? scriptId,
});

_ProfileUpdateVersion? _profileUpdateVersion(Profile? profile) {
  if (profile == null) {
    return null;
  }
  return (
    id: profile.id,
    label: profile.label,
    url: profile.url,
    autoUpdate: profile.autoUpdate,
    autoUpdateDuration: profile.autoUpdateDuration,
    overwriteType: profile.overwriteType,
    scriptId: profile.scriptId,
  );
}
