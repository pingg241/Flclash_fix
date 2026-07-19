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

typedef ProxyGroupsRefreshScheduler = void Function();

const proxyGroupsRuntimeRefreshDebounce = Duration(milliseconds: 500);

final proxyGroupsRefreshSchedulerProvider =
    Provider<ProxyGroupsRefreshScheduler>(
      (ref) =>
          () => ref
              .read(proxiesActionProvider.notifier)
              .updateGroupsDebounce(Duration.zero),
    );

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

@visibleForTesting
bool invalidatesProxyGeoDatabase(GeoResource resource, GeoUpdateNotice notice) {
  return notice == GeoUpdateNotice.updated &&
      (resource == GeoResource.MMDB || resource == GeoResource.ASN);
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
      unawaited(
        ref
            .read(setupActionProvider.notifier)
            .applyProfileDebounce(silence: true)
            .catchError((Object error, StackTrace stackTrace) {
              commonPrint.log(
                'Automatic profile apply failed: $error\n$stackTrace',
                logLevel: LogLevel.error,
              );
            }),
      );
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
    debouncer.cancel(FunctionTag.updateDelay);
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
    debouncer.call(FunctionTag.updateDelay, () async {
      if (_disposed) {
        return;
      }
      ref.read(proxyGroupsRefreshSchedulerProvider)();
    }, duration: proxyGroupsRuntimeRefreshDebounce);
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
    if (_disposed) {
      return;
    }
    if (isProviderSyncEvent(providerName)) {
      await ref.read(providersProvider.notifier).syncProviders();
    } else {
      final provider = await coreController.getExternalProvider(providerName);
      if (_disposed) {
        return;
      }
      ref.read(providersProvider.notifier).setProvider(provider);
    }
    if (_disposed) {
      return;
    }
    debouncer.call(FunctionTag.loadedProvider, () async {
      if (_disposed) {
        return;
      }
      ref.read(proxiesActionProvider.notifier).updateGroupsDebounce();
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
    final notice = resolveGeoUpdateNotice(
      updating: updating,
      skipped: skipped,
      error: error,
    );
    switch (notice) {
      case GeoUpdateNotice.updating:
        globalState.showNotifier(l10n.geoUpdating(geoResource.name));
      case GeoUpdateNotice.skipped:
        globalState.showNotifier(l10n.geoSkipped(geoResource.name));
      case GeoUpdateNotice.updated:
        globalState.showNotifier(l10n.geoUpdated(geoResource.name));
      case GeoUpdateNotice.error:
        globalState.showNotifier(error!);
    }
    if (invalidatesProxyGeoDatabase(geoResource, notice)) {
      ref.read(geoDatabaseRevisionProvider.notifier).bump();
    }
    ref.read(isUpdatingProvider(key).notifier).value = updating;
    super.onGeoUpdate(geoType, updating, skipped, error);
  }
}
