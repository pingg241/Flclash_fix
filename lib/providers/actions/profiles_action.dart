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
  (_) => _clearProfileEffect,
);

@Riverpod(keepAlive: true)
class ProfilesAction extends _$ProfilesAction {
  final Map<int, Future<void>> _updates = {};
  final Map<int, int> _generations = {};

  @override
  void build() {}

  Future<void> updateCurrentSelectedMap(
    String groupName,
    String proxyName,
  ) async {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile != null &&
        currentProfile.selectedMap[groupName] != proxyName) {
      final selectedMap = Map<String, String>.from(currentProfile.selectedMap)
        ..[groupName] = proxyName;
      await ref
          .read(profilesProvider.notifier)
          .put(currentProfile.copyWith(selectedMap: selectedMap));
    }
  }

  Future<void> deleteProfile(int id) async {
    invalidateProfileUpdate(id);
    final currentProfileId = ref.read(currentProfileIdProvider);
    final remainingProfiles = ref
        .read(profilesProvider)
        .where((profile) => profile.id != id)
        .toList();
    if (currentProfileId == id && remainingProfiles.isEmpty) {
      final stopped = await ref.read(profileStatusUpdaterProvider)(false);
      if (!stopped) {
        throw StateError('Failed to stop before deleting the last profile');
      }
    }
    await ref.read(profilesProvider.notifier).del(id);
    if (currentProfileId == id) {
      if (remainingProfiles.isNotEmpty) {
        final updateId = remainingProfiles.first.id;
        ref.read(currentProfileIdProvider.notifier).value = updateId;
      } else {
        ref.read(currentProfileIdProvider.notifier).value = null;
      }
    }
    await ref.read(profileEffectCleanerProvider)(id);
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
    ref.read(currentProfileIdProvider.notifier).value = profile.id;
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

  Future<void> updateProfile(
    Profile profile, {
    bool showLoading = false,
    bool replaceProfile = false,
  }) {
    final replacement = replaceProfile
        ? ref.read(profilesProvider.notifier).put(profile)
        : null;
    final generation = (_generations[profile.id] ?? 0) + 1;
    _generations[profile.id] = generation;
    final previous = _updates[profile.id];
    late final Future<void> request;
    request = () async {
      if (replacement != null) {
        await replacement;
      }
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      await _performProfileUpdate(profile, generation, showLoading);
    }();
    _updates[profile.id] = request;
    return request.whenComplete(() {
      if (identical(_updates[profile.id], request)) {
        _updates.remove(profile.id);
      }
    });
  }

  Future<void> _performProfileUpdate(
    Profile profile,
    int generation,
    bool showLoading,
  ) async {
    try {
      if (_generations[profile.id] != generation) {
        return;
      }
      if (showLoading) {
        ref.read(isUpdatingProvider(profile.updatingKey).notifier).value = true;
      }
      final expectedProfile = ref.read(profilesProvider).getProfile(profile.id);
      if (expectedProfile == null) {
        return;
      }
      final expectedVersion = _profileUpdateVersion(expectedProfile);
      var activeVersion = expectedVersion;
      try {
        await ref.read(profileUpdaterProvider)(
          expectedProfile,
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
        return;
      }
      if (profile.id == ref.read(currentProfileIdProvider)) {
        ref
            .read(setupActionProvider.notifier)
            .applyProfileDebounce(silence: true);
      }
    } finally {
      ref.read(isUpdatingProvider(profile.updatingKey).notifier).value = false;
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
    final profile = await globalState.loadingRun(
      tag: LoadingTag.profiles,
      () async {
        return Profile.normal(label: platformFile.name).saveFile(bytes);
      },
      title: currentAppLocalizations.addProfile,
    );
    if (profile != null) {
      await putProfile(profile);
    }
  }

  Future<void> addProfileFormURL(String url) async {
    if (globalState.navigatorKey.currentState?.canPop() ?? false) {
      globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
    ref.read(currentPageLabelProvider.notifier).value = PageLabel.profiles;
    final profile = await globalState.loadingRun(
      tag: LoadingTag.profiles,
      () async {
        return Profile.normal(url: url).update();
      },
      title: currentAppLocalizations.addProfile,
    );
    if (profile != null) {
      await putProfile(profile);
    }
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
    await _clearProfileEffect(profileId);
  }
}

Future<void> _clearProfileEffect(int profileId) async {
  final profilePath = await appPath.getProfilePath(profileId.toString());
  final providersDirPath = await appPath.getProvidersDirPath(
    profileId.toString(),
  );
  final profileFile = File(profilePath);
  final isExists = await profileFile.exists();
  if (isExists) {
    await profileFile.safeDelete(recursive: true);
  }
  await coreController.deleteFile(providersDirPath);
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
