import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class App with WidgetsBindingObserver {
  static const _maxPackageIconCacheSize = 128;
  static const _defaultPackageIconCacheDuration = Duration(minutes: 10);
  static const _defaultPackageIconLoadTimeout = Duration(seconds: 5);
  static App? _instance;

  final LinkedHashMap<String, _PackageIconCacheEntry> _packageIconCache =
      LinkedHashMap();
  final Map<String, int> _packageVersions = {};

  bool _observerRegistered = false;
  late MethodChannel methodChannel;
  @visibleForTesting
  Duration packageIconCacheDuration = _defaultPackageIconCacheDuration;
  @visibleForTesting
  Duration packageIconLoadTimeout = _defaultPackageIconLoadTimeout;
  Function()? onExit;

  App._internal() {
    methodChannel = const MethodChannel('$packageName/app');
    methodChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'exit':
          if (onExit != null) {
            await onExit!();
          }
        default:
          throw MissingPluginException();
      }
    });
  }

  factory App() {
    _instance ??= App._internal();
    return _instance!;
  }

  Future<bool?> moveTaskToBack() async {
    return methodChannel.invokeMethod<bool>('moveTaskToBack');
  }

  Future<List<Package>> getPackages() async {
    _ensureObserverRegistered();
    final packagesString = await methodChannel.invokeMethod<String>(
      'getPackages',
    );
    final List<dynamic> packagesRaw =
        (await packagesString?.commonToJSON<List<dynamic>>()) ?? [];
    final packages = packagesRaw
        .map((e) => Package.fromJson(e))
        .toSet()
        .toList();
    _updatePackageVersions(packages);
    return packages;
  }

  Future<List<String>> getChinaPackageNames() async {
    final packageNamesString = await methodChannel.invokeMethod<String>(
      'getChinaPackageNames',
    );
    final List<dynamic> packageNamesRaw =
        await packageNamesString?.commonToJSON<List<dynamic>>() ?? [];
    return packageNamesRaw.map((e) => e.toString()).toList();
  }

  Future<bool?> requestNotificationsPermission() async {
    return methodChannel.invokeMethod<bool>('requestNotificationsPermission');
  }

  Future<bool> openFile(String path) async {
    return await methodChannel.invokeMethod<bool>('openFile', {'path': path}) ??
        false;
  }

  Future<ImageProvider?> getPackageIcon(String packageName) {
    _ensureObserverRegistered();
    if (packageName.isEmpty) {
      return Future.value();
    }
    final packageVersion = _packageVersions[packageName];
    final cached = _packageIconCache.remove(packageName);
    if (cached != null &&
        cached.packageVersion == packageVersion &&
        DateTime.now().isBefore(cached.validUntil)) {
      _packageIconCache[packageName] = cached;
      return cached.future;
    }

    late final _PackageIconCacheEntry entry;
    final future = _loadPackageIcon(packageName);
    entry = _PackageIconCacheEntry(
      packageVersion: packageVersion,
      validUntil: DateTime.now().add(packageIconCacheDuration),
      future: future,
    );
    _packageIconCache[packageName] = entry;
    _trimPackageIconCache();
    unawaited(
      future.then((provider) {
        if (provider == null ||
            _packageVersions[packageName] != packageVersion) {
          _removePackageIconEntry(packageName, entry);
        }
      }),
    );
    return future;
  }

  Future<ImageProvider?> _loadPackageIcon(String packageName) async {
    try {
      final path = await methodChannel
          .invokeMethod<String>('getPackageIcon', {'packageName': packageName})
          .timeout(packageIconLoadTimeout);
      if (path == null) {
        return null;
      }
      return FileImage(File(path));
    } on Object {
      return null;
    }
  }

  void _updatePackageVersions(List<Package> packages) {
    final nextVersions = {
      for (final package in packages)
        package.packageName: package.lastUpdateTime,
    };
    for (final packageName in _packageIconCache.keys.toList()) {
      final entry = _packageIconCache[packageName];
      if (!nextVersions.containsKey(packageName) ||
          entry?.packageVersion != nextVersions[packageName]) {
        _packageIconCache.remove(packageName);
      }
    }
    _packageVersions
      ..clear()
      ..addAll(nextVersions);
  }

  void _ensureObserverRegistered() {
    if (_observerRegistered) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _observerRegistered = true;
  }

  void _trimPackageIconCache() {
    while (_packageIconCache.length > _maxPackageIconCacheSize) {
      _packageIconCache.remove(_packageIconCache.keys.first);
    }
  }

  void _removePackageIconEntry(
    String packageName,
    _PackageIconCacheEntry entry,
  ) {
    if (identical(_packageIconCache[packageName], entry)) {
      _packageIconCache.remove(packageName);
    }
  }

  @visibleForTesting
  int get packageIconCacheLength => _packageIconCache.length;

  @visibleForTesting
  void clearPackageIconCache({bool clearPackageVersions = true}) {
    _packageIconCache.clear();
    if (clearPackageVersions) {
      _packageVersions.clear();
    }
    packageIconCacheDuration = _defaultPackageIconCacheDuration;
    packageIconLoadTimeout = _defaultPackageIconLoadTimeout;
  }

  @override
  void didHaveMemoryPressure() {
    clearPackageIconCache(clearPackageVersions: false);
  }

  Future<bool?> tip(String? message) async {
    return methodChannel.invokeMethod<bool>('tip', {'message': '$message'});
  }

  Future<bool?> initShortcuts() async {
    return methodChannel.invokeMethod<bool>(
      'initShortcuts',
      currentAppLocalizations.toggle,
    );
  }

  Future<bool?> updateExcludeFromRecents(bool value) async {
    return methodChannel.invokeMethod<bool>('updateExcludeFromRecents', {
      'value': value,
    });
  }

  Future<bool?> isBatteryOptimizationDisabled() async {
    if (!Platform.isAndroid) return true;
    return methodChannel.invokeMethod<bool>('isBatteryOptimizationDisabled');
  }

  Future<bool?> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return false;
    return methodChannel.invokeMethod<bool>('openBatteryOptimizationSettings');
  }

  Future<bool?> openAppSettings() async {
    if (!Platform.isAndroid) return false;
    return methodChannel.invokeMethod<bool>('openAppSettings');
  }
}

class _PackageIconCacheEntry {
  final int? packageVersion;
  final DateTime validUntil;
  final Future<ImageProvider?> future;

  const _PackageIconCacheEntry({
    required this.packageVersion,
    required this.validUntil,
    required this.future,
  });
}

final app = system.isAndroid ? App() : null;
