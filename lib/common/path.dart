import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class AppPath {
  static AppPath? _instance;
  late final Future<Directory> dataDir;
  late final Future<Directory> downloadDir;
  late final Future<Directory> tempDir;
  late final Future<Directory> cacheDir;
  late String appDirPath;

  AppPath._internal({
    Future<Directory>? dataDirectory,
    Future<Directory?>? downloadsDirectory,
    Future<Directory>? temporaryDirectory,
    Future<Directory>? applicationCacheDirectory,
  }) {
    appDirPath = join(dirname(Platform.resolvedExecutable));
    dataDir = dataDirectory ?? getApplicationSupportDirectory();
    tempDir = temporaryDirectory ?? getTemporaryDirectory();
    cacheDir = applicationCacheDirectory ?? getApplicationCacheDirectory();
    downloadDir = (downloadsDirectory ?? getDownloadsDirectory()).then((value) {
      if (value == null) {
        throw const FileSystemException('Downloads directory is unavailable');
      }
      return value;
    });
  }

  AppPath.test({
    required Future<Directory> dataDirectory,
    required Future<Directory?> downloadsDirectory,
    required Future<Directory> temporaryDirectory,
    required Future<Directory> applicationCacheDirectory,
  }) : this._internal(
         dataDirectory: dataDirectory,
         downloadsDirectory: downloadsDirectory,
         temporaryDirectory: temporaryDirectory,
         applicationCacheDirectory: applicationCacheDirectory,
       );

  factory AppPath() {
    _instance ??= AppPath._internal();
    return _instance!;
  }

  String get executableExtension {
    return system.isWindows ? '.exe' : '';
  }

  String get executableDirPath {
    final currentExecutablePath = Platform.resolvedExecutable;
    return dirname(currentExecutablePath);
  }

  String get corePath {
    return join(executableDirPath, 'FlClashCore$executableExtension');
  }

  String get helperPath {
    return join(executableDirPath, '$appHelperService$executableExtension');
  }

  Future<String> get downloadDirPath async {
    final directory = await downloadDir;
    return directory.path;
  }

  Future<String> get homeDirPath async {
    final directory = await dataDir;
    return directory.path;
  }

  Future<String> get databasePath async {
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, 'database.sqlite');
  }

  Future<String> get backupFilePath async {
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, 'backup.zip');
  }

  Future<String> get restoreDirPath async {
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, 'restore');
  }

  Future<String> get tempFilePath async {
    final mTempDir = await tempDir;
    return join(mTempDir.path, 'temp${utils.id}');
  }

  Future<String> get lockFilePath async {
    final homeDirPath = await appPath.homeDirPath;
    return join(homeDirPath, 'FlClash.lock');
  }

  Future<String> get configFilePath async {
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, 'config.yaml');
  }

  Future<String> get sharedFilePath async {
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, 'shared.json');
  }

  Future<String> get sharedPreferencesPath async {
    final directory = await dataDir;
    return join(directory.path, 'shared_preferences.json');
  }

  Future<String> get profilesPath async {
    final directory = await dataDir;
    return join(directory.path, profilesDirectoryName);
  }

  Future<String> getProfilePath(String fileName) async {
    return join(await profilesPath, '$fileName.yaml');
  }

  Future<String> get scriptsDirPath async {
    final path = await homeDirPath;
    return join(path, 'scripts');
  }

  Future<String> getScriptPath(String fileName) async {
    final path = await scriptsDirPath;
    return join(path, '$fileName.js');
  }

  Future<String> getIconsCacheDir() async {
    final directory = await cacheDir;
    return join(directory.path, 'icons');
  }

  Future<String> getProvidersRootPath() async {
    final directory = await profilesPath;
    return join(directory, 'providers');
  }

  Future<String> getProvidersDirPath(String id) async {
    final directory = await profilesPath;
    return join(directory, 'providers', id);
  }

  Future<String> getProvidersFilePath(
    String id,
    String type,
    String url,
  ) async {
    final directory = await profilesPath;
    return join(directory, 'providers', id, type, url.toMd5());
  }

  Future<String> get tempPath async {
    final directory = await tempDir;
    return directory.path;
  }
}

final appPath = AppPath();
