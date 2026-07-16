import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum GeoUpdateNotice { updating, skipped, updated, error }

@visibleForTesting
GeoUpdateNotice resolveGeoUpdateNotice({
  required bool updating,
  required bool skipped,
  required String? error,
}) {
  if (error?.isNotEmpty == true) {
    return GeoUpdateNotice.error;
  }
  if (updating) {
    return GeoUpdateNotice.updating;
  }
  if (skipped) {
    return GeoUpdateNotice.skipped;
  }
  return GeoUpdateNotice.updated;
}

class CoreManager extends ConsumerStatefulWidget {
  final Widget child;

  const CoreManager({super.key, required this.child});

  @override
  ConsumerState<CoreManager> createState() => _CoreContainerState();
}

class _CoreContainerState extends ConsumerState<CoreManager>
    with CoreEventListener {
  bool _disposed = false;

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void initState() {
    super.initState();
    coreEventManager.addListener(this);
    ref.read(profilesActionProvider.notifier);
    ref.listenManual(currentProfileIdProvider, (prev, next) {
      if (prev == next) {
        return;
      }
      final profilesAction = ref.read(profilesActionProvider.notifier);
      if (profilesAction.isChangingCurrentProfile) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_applyExternalProfileSelection(next));
      });
    });
    ref.listenManual(updateParamsProvider, (prev, next) {
      if (prev != next) {
        ref.read(setupActionProvider.notifier).updateConfigDebounce();
      }
    });
    ref.listenManual(profileRebuildConfigProvider, (prev, next) {
      if (prev == next || ref.read(runTimeProvider) == null) {
        return;
      }
      ref
          .read(setupActionProvider.notifier)
          .applyProfileDebounce(silence: true);
    });
    ref.listenManual(
      appSettingProvider.select((state) => state.openLogs),
      (prev, next) => unawaited(_updateLogSubscription()),
      fireImmediately: true,
    );
    ref.listenManual(coreStatusProvider, (prev, next) {
      if (prev != next && next == CoreStatus.connected) {
        unawaited(_updateLogSubscription());
      }
    });
  }

  Future<void> _applyExternalProfileSelection(int? nextId) async {
    try {
      await ref
          .read(profilesActionProvider.notifier)
          .applyExternalProfileSelection(nextId);
    } catch (error, stackTrace) {
      commonPrint.log('$error\n$stackTrace', logLevel: LogLevel.error);
      if (mounted) {
        globalState.showNotifier(error.toString());
      }
    }
  }

  Future<void> _updateLogSubscription() async {
    if (!mounted || ref.read(coreStatusProvider) != CoreStatus.connected) {
      return;
    }
    try {
      if (ref.read(appSettingProvider).openLogs) {
        await coreController.startLog();
      } else {
        await coreController.stopLog();
      }
    } catch (error, stackTrace) {
      commonPrint.log(
        'Failed to update core log subscription: $error\n$stackTrace',
        logLevel: LogLevel.error,
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    coreEventManager.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onDelay(Delay delay) async {
    super.onDelay(delay);
    if (_disposed) {
      return;
    }
    final proxiesAction = ref.read(proxiesActionProvider.notifier);
    proxiesAction.setDelay(delay);
    // Delay values are already reflected via delayProvider; full group
    // rebuilds are only needed when the proxy list is sorted by delay.
    final sortType = ref.read(
      proxiesStyleSettingProvider.select((state) => state.sortType),
    );
    if (sortType != ProxiesSortType.delay) {
      return;
    }
    debouncer.call(FunctionTag.updateDelay, () async {
      if (_disposed) {
        return;
      }
      proxiesAction.updateGroupsDebounce();
    }, duration: const Duration(milliseconds: 15000));
  }

  @override
  void onLog(Log log) {
    if (_disposed) {
      return;
    }
    ref.read(logsProvider.notifier).add(log);
    if (log.logLevel == LogLevel.error) {
      globalState.showNotifier(log.payload);
    }
    super.onLog(log);
  }

  @override
  void onRequest(TrackerInfo trackerInfo) {
    if (_disposed) {
      return;
    }
    ref.read(requestsProvider.notifier).addRequest(trackerInfo);
    super.onRequest(trackerInfo);
  }

  @override
  Future<void> onLoaded(String providerName) async {
    final container = globalState.container;
    final provider = await coreController.getExternalProvider(providerName);
    if (_disposed) {
      return;
    }
    container.read(providersProvider.notifier).setProvider(provider);
    debouncer.call(FunctionTag.loadedProvider, () async {
      if (_disposed) {
        return;
      }
      container.read(proxiesActionProvider.notifier).updateGroupsDebounce();
    }, duration: const Duration(milliseconds: 5000));
    super.onLoaded(providerName);
  }

  @override
  Future<void> onCrash(String message) async {
    if (_disposed) {
      return;
    }
    if (ref.read(coreStatusProvider) != CoreStatus.connected) {
      return;
    }
    ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
    if (mounted &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      context.showNotifier(message);
    }
    await coreController.shutdown(false);
    super.onCrash(message);
  }

  @override
  void onGeoUpdate(String geoType, bool updating, bool skipped, String? error) {
    if (_disposed) {
      return;
    }
    final geoResource = GeoResource.fromJson(geoType.toLowerCase());
    final key = geoResource.updatingKey;
    final l10n = currentAppLocalizations;
    switch (resolveGeoUpdateNotice(
      updating: updating,
      skipped: skipped,
      error: error,
    )) {
      case GeoUpdateNotice.updating:
        globalState.showNotifier(l10n.geoUpdating(geoResource.name));
      case GeoUpdateNotice.skipped:
        globalState.showNotifier(l10n.geoSkipped(geoResource.name));
      case GeoUpdateNotice.updated:
        globalState.showNotifier(l10n.geoUpdated(geoResource.name));
      case GeoUpdateNotice.error:
        globalState.showNotifier(error!);
    }
    ref.read(isUpdatingProvider(key).notifier).value = updating;
    super.onGeoUpdate(geoType, updating, skipped, error);
  }
}
