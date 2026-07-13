import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:path/path.dart' as path;

import 'clash_config.dart';

part 'generated/profile.freezed.dart';
part 'generated/profile.g.dart';

@freezed
abstract class SubscriptionInfo with _$SubscriptionInfo {
  const factory SubscriptionInfo({
    @Default(0) int upload,
    @Default(0) int download,
    @Default(0) int total,
    @Default(0) int expire,
  }) = _SubscriptionInfo;

  factory SubscriptionInfo.fromJson(Map<String, Object?> json) =>
      _$SubscriptionInfoFromJson(json);

  factory SubscriptionInfo.formHString(String? info) {
    if (info == null) return const SubscriptionInfo();
    final list = info.split(';');
    final Map<String, int?> map = {};
    for (final i in list) {
      final keyValue = i.trim().split('=');
      map[keyValue[0]] = int.tryParse(keyValue[1]);
    }
    return SubscriptionInfo(
      upload: map['upload'] ?? 0,
      download: map['download'] ?? 0,
      total: map['total'] ?? 0,
      expire: map['expire'] ?? 0,
    );
  }
}

@freezed
abstract class Profile with _$Profile {
  const factory Profile({
    required int id,
    @Default('') String label,
    String? currentGroupName,
    @Default('') String url,
    DateTime? lastUpdateDate,
    required Duration autoUpdateDuration,
    SubscriptionInfo? subscriptionInfo,
    @Default(true) bool autoUpdate,
    @Default({}) Map<String, String> selectedMap,
    @Default({}) Set<String> unfoldSet,
    @Default(OverwriteType.standard) OverwriteType overwriteType,
    int? scriptId,
    int? order,
  }) = _Profile;

  factory Profile.fromJson(Map<String, Object?> json) =>
      _$ProfileFromJson(json);

  factory Profile.normal({String? label, String url = ''}) {
    final id = snowflake.id;
    return Profile(
      label: label ?? '',
      url: url,
      id: id,
      autoUpdateDuration: defaultUpdateDuration,
    );
  }
}

@freezed
abstract class ProfileRuleLink with _$ProfileRuleLink {
  const factory ProfileRuleLink({
    int? profileId,
    required int ruleId,
    RuleScene? scene,
    String? order,
  }) = _ProfileRuleLink;
}

extension ProfileRuleLinkExt on ProfileRuleLink {
  String get key {
    final splits = <String?>[
      profileId?.toString(),
      ruleId.toString(),
      scene?.name,
    ];
    return splits.where((item) => item != null).join('_');
  }
}

// @freezed
// abstract class Overwrite with _$Overwrite {
//   const factory Overwrite({
//     @Default(OverwriteType.standard) OverwriteType type,
//     @Default(StandardOverwrite()) StandardOverwrite standardOverwrite,
//     @Default(ScriptOverwrite()) ScriptOverwrite scriptOverwrite,
//   }) = _Overwrite;
//
//   factory Overwrite.fromJson(Map<String, Object?> json) =>
//       _$OverwriteFromJson(json);
// }

@freezed
abstract class StandardOverwrite with _$StandardOverwrite {
  const factory StandardOverwrite({
    @Default([]) List<Rule> addedRules,
    @Default([]) List<int> disabledRuleIds,
  }) = _StandardOverwrite;

  factory StandardOverwrite.fromJson(Map<String, Object?> json) =>
      _$StandardOverwriteFromJson(json);
}

@freezed
abstract class ScriptOverwrite with _$ScriptOverwrite {
  const factory ScriptOverwrite({int? scriptId}) = _ScriptOverwrite;

  factory ScriptOverwrite.fromJson(Map<String, Object?> json) =>
      _$ScriptOverwriteFromJson(json);
}

extension ProfilesExt on List<Profile> {
  Profile? getProfile(int? profileId) {
    final index = indexWhere((profile) => profile.id == profileId);
    return index == -1 ? null : this[index];
  }

  String _getLabel(String label, int id) {
    final realLabel = label.takeFirstValid([id.toString()]);
    final hasDup =
        indexWhere(
          (element) => element.label == realLabel && element.id != id,
        ) !=
        -1;
    if (hasDup) {
      return _getLabel(utils.getOverwriteLabel(realLabel), id);
    } else {
      return label;
    }
  }

  Profile optimizeLabel(Profile profile) {
    return profile.copyWith(label: _getLabel(profile.label, profile.id));
  }
}

class ProfileUpdateCancelled implements Exception {
  const ProfileUpdateCancelled();
}

extension ProfileExtension on Profile {
  ProfileType get type =>
      url.isEmpty == true ? ProfileType.file : ProfileType.url;

  bool get realAutoUpdate => url.isEmpty == true ? false : autoUpdate;

  String get realLabel => label.takeFirstValid([id.toString()]);

  String get fileName => '$id.yaml';

  String get updatingKey => 'profile_$id';

  Future<Profile?> checkAndUpdateAndCopy() async {
    final mFile = await _getFile(false);
    final isExists = await mFile.exists();
    if (isExists || url.isEmpty) {
      return null;
    }
    return update();
  }

  Future<File> _getFile([bool autoCreate = true]) async {
    final path = await appPath.getProfilePath(id.toString());
    final file = File(path);
    final isExists = await file.exists();
    if (!isExists && autoCreate) {
      return file.create(recursive: true);
    }
    return file;
    // final oldPath = await appPath.getProfilePath(id);
    // final newPath = await appPath.getProfilePath(fileName);
    // final oldFile = oldPath == newPath ? null : File(oldPath);
    // final oldIsExists = await oldFile?.exists() ?? false;
    // if (oldIsExists) {
    //   return await oldFile!.rename(newPath);
    // }
    // final file = File(newPath);
    // final isExists = await file.exists();
    // if (!isExists && autoCreate) {
    //   return await file.create(recursive: true);
    // }
    // return file;
  }

  Future<File> get file async {
    return _getFile();
  }

  Future<Profile> update({
    bool Function()? shouldSave,
    Future<void> Function(Profile profile)? onCommit,
  }) async {
    final response = await request.getFileResponseForUrl(url);
    final disposition = response.headers.value('content-disposition');
    final userinfo = response.headers.value('subscription-userinfo');
    if (shouldSave != null && !shouldSave()) {
      throw const ProfileUpdateCancelled();
    }
    return copyWith(
      label: label.takeFirstValid([
        utils.getFileNameForDisposition(disposition),
        id.toString(),
      ]),
      subscriptionInfo: SubscriptionInfo.formHString(userinfo),
    ).saveFile(
      response.data ?? Uint8List.fromList([]),
      shouldSave: shouldSave,
      onCommit: onCommit,
    );
  }

  Future<Profile> saveFile(
    Uint8List bytes, {
    bool Function()? shouldSave,
    Future<void> Function(Profile profile)? onCommit,
  }) async {
    if (bytes.length > ExternalInputLimits.profileBytes) {
      throw const InputTooLargeException(
        'Profile',
        ExternalInputLimits.profileBytes,
      );
    }
    return _saveValidatedFile(
      (tempFile) => tempFile.writeAsBytes(bytes),
      shouldSave: shouldSave,
      onCommit: onCommit,
    );
  }

  Future<Profile> saveFileWithPath(String sourcePath) async {
    return _saveValidatedFile(
      (tempFile) => File(sourcePath).copy(tempFile.path),
    );
  }

  Future<Profile> _saveValidatedFile(
    Future<File> Function(File tempFile) writeTempFile, {
    bool Function()? shouldSave,
    Future<void> Function(Profile profile)? onCommit,
  }) async {
    final homeDir = Directory(await appPath.homeDirPath);
    await homeDir.create(recursive: true);
    final canonicalHome = await homeDir.resolveSymbolicLinks();
    final tempDir = Directory(path.join(canonicalHome, '.tmp'));
    await tempDir.create(recursive: true);
    final canonicalTempDir = await tempDir.resolveSymbolicLinks();
    if (!path.isWithin(canonicalHome, canonicalTempDir)) {
      throw const FileSystemException('Invalid profile temporary directory');
    }

    final tempFile = File(
      path.join(canonicalTempDir, 'profile-$id-${utils.id}.yaml'),
    );
    final destination = await _getFile(false);
    File? previous;
    try {
      await writeTempFile(tempFile);
      if (await tempFile.length() > ExternalInputLimits.profileBytes) {
        throw const InputTooLargeException(
          'Profile',
          ExternalInputLimits.profileBytes,
        );
      }
      final message = await coreController.validateConfig(tempFile.path);
      if (message.isNotEmpty) {
        throw message;
      }
      if (shouldSave != null && !shouldSave()) {
        throw const ProfileUpdateCancelled();
      }
      await destination.parent.create(recursive: true);
      final canonicalDestinationDir = await destination.parent
          .resolveSymbolicLinks();
      if (!path.isWithin(canonicalHome, canonicalDestinationDir)) {
        throw const FileSystemException('Invalid profile directory');
      }
      if (await destination.exists()) {
        previous = File('${destination.path}.previous-${utils.id}');
        await destination.rename(previous.path);
      }
      var installed = false;
      var committed = false;
      try {
        await tempFile.rename(destination.path);
        installed = true;
        if (shouldSave != null && !shouldSave()) {
          throw const ProfileUpdateCancelled();
        }
        final updatedProfile = copyWith(lastUpdateDate: DateTime.now());
        if (onCommit != null) {
          await onCommit(updatedProfile);
        }
        if (shouldSave != null && !shouldSave()) {
          throw const ProfileUpdateCancelled();
        }
        committed = true;
        await previous?.safeDelete();
        return updatedProfile;
      } catch (_) {
        if (!committed) {
          if (installed) {
            await destination.safeDelete();
          }
          if (previous != null && await previous.exists()) {
            await previous.rename(destination.path);
          }
        }
        rethrow;
      }
    } finally {
      await tempFile.safeDelete();
    }
  }
}
