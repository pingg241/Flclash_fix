import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import 'constant.dart';
import 'system.dart';

abstract interface class AutoLaunchPlatform {
  Future<bool> isEnabled();

  Future<bool> enable();

  Future<bool> disable();
}

class _PluginAutoLaunchPlatform implements AutoLaunchPlatform {
  const _PluginAutoLaunchPlatform();

  @override
  Future<bool> isEnabled() => launchAtStartup.isEnabled();

  @override
  Future<bool> enable() => launchAtStartup.enable();

  @override
  Future<bool> disable() => launchAtStartup.disable();
}

class AutoLaunch {
  static AutoLaunch? _instance;
  final AutoLaunchPlatform _platform;
  final bool _skipInDebug;

  AutoLaunch._internal()
    : _platform = const _PluginAutoLaunchPlatform(),
      _skipInDebug = true {
    launchAtStartup.setup(
      appName: appName,
      appPath: Platform.resolvedExecutable,
    );
  }

  AutoLaunch.test(this._platform) : _skipInDebug = false;

  factory AutoLaunch() {
    _instance ??= AutoLaunch._internal();
    return _instance!;
  }

  Future<bool> get isEnable async {
    return _platform.isEnabled();
  }

  Future<bool> enable() async {
    return _platform.enable();
  }

  Future<bool> disable() async {
    return _platform.disable();
  }

  Future<bool> updateStatus(bool isAutoLaunch) async {
    if (kDebugMode && _skipInDebug) {
      return true;
    }
    if (await isEnable == isAutoLaunch) {
      return true;
    }
    final updated = isAutoLaunch ? await enable() : await disable();
    if (!updated) {
      return false;
    }
    return await isEnable == isAutoLaunch;
  }
}

final autoLaunch = system.isDesktop ? AutoLaunch() : null;
