import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/manager/window_manager.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

@visibleForTesting
Future<void> performSuspendTransition({
  required bool suspend,
  required Future<bool> Function() startListener,
  required Future<bool> Function() stopListener,
}) async {
  final updated = suspend ? await stopListener() : await startListener();
  if (!updated) {
    throw StateError(
      suspend
          ? 'failed to suspend core listener'
          : 'failed to resume core listener',
    );
  }
}

@visibleForTesting
Future<void> performSerializedSuspendTransition({
  required bool suspend,
  required Future<bool> Function() startListener,
  required Future<bool> Function() stopListener,
}) {
  return serializedSetup(
    () => performSuspendTransition(
      suspend: suspend,
      startListener: startListener,
      stopListener: stopListener,
    ),
  );
}

@visibleForTesting
Future<bool> performSuspendTransitionWithRetry({
  required bool suspend,
  required Future<bool> Function() startListener,
  required Future<bool> Function() stopListener,
  required bool Function() shouldContinue,
  int maxAttempts = 2,
  Duration retryDelay = const Duration(milliseconds: 250),
  Future<void> Function(Duration delay)? wait,
}) async {
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    if (!shouldContinue()) {
      return false;
    }
    try {
      await performSerializedSuspendTransition(
        suspend: suspend,
        startListener: startListener,
        stopListener: stopListener,
      );
      return true;
    } catch (_) {
      if (!shouldContinue()) {
        return false;
      }
      if (attempt >= maxAttempts) {
        rethrow;
      }
      await (wait ?? Future<void>.delayed)(retryDelay);
    }
  }
  return false;
}

@visibleForTesting
Future<void> restoreDnsOnDispose(
  Future<void> Function(bool restore) updateDns,
) {
  return updateDns(true);
}

class AppStateManager extends ConsumerStatefulWidget {
  final Widget child;

  const AppStateManager({super.key, required this.child});

  @override
  ConsumerState<AppStateManager> createState() => _AppStateManagerState();
}

class _AppStateManagerState extends ConsumerState<AppStateManager>
    with WidgetsBindingObserver {
  int _suspendGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(checkIpProvider, (prev, next) {
      if (prev != next && next.a && next.c) {
        ref.read(networkDetectionProvider.notifier).startCheck();
      }
    });
    ref.listenManual(configProvider, (prev, next) {
      if (prev != next) {
        globalState.container
            .read(storeActionProvider.notifier)
            .savePreferencesDebounce();
      }
    });
    ref.listenManual(needUpdateGroupsProvider, (prev, next) {
      if (prev != next) {
        globalState.container
            .read(proxiesActionProvider.notifier)
            .updateGroupsDebounce();
      }
    });
    ref.listenManual(suspendProvider, (prev, next) {
      if (prev != next) {
        _scheduleSuspendTransition(next);
      }
    });
    if (system.isMacOS) {
      ref.listenManual(autoSetSystemDnsStateProvider, (prev, next) {
        if (prev == next) {
          return;
        }
        final currentMacOS = macOS;
        if (currentMacOS == null) {
          return;
        }
        final restore = next.a != true || next.b != true;
        unawaited(
          currentMacOS.updateDns(restore).catchError((
            Object error,
            StackTrace stackTrace,
          ) {
            commonPrint.log(
              'Failed to update macOS DNS: $error\n$stackTrace',
              logLevel: LogLevel.warning,
            );
          }),
        );
      });
    }
  }

  void _scheduleSuspendTransition(bool desired) {
    final generation = ++_suspendGeneration;
    unawaited(
      debouncer
          .callCoalesced<void>(
            FunctionTag.suspend,
            () => _applySuspendTransition(desired),
            duration: Duration.zero,
          )
          .catchError((Object error, StackTrace stackTrace) {
            if (!mounted || generation != _suspendGeneration) {
              return;
            }
            commonPrint.log(
              'Failed to apply SSID suspend state: $error\n$stackTrace',
              logLevel: LogLevel.error,
            );
            globalState.showNotifier(error.toString());
          }),
    );
  }

  Future<void> _applySuspendTransition(bool desired) async {
    if (!mounted || !ref.read(isStartProvider)) {
      return;
    }
    if (ref.read(confirmedSuspendProvider) == desired) {
      return;
    }
    final operations = ref.read(setupCoreOperationsProvider);
    final transitioned = await performSuspendTransitionWithRetry(
      suspend: desired,
      startListener: operations.startListener,
      stopListener: operations.stopListener,
      shouldContinue: () => mounted && ref.read(suspendProvider) == desired,
    );
    if (!transitioned || !mounted) {
      return;
    }
    ref.read(confirmedSuspendProvider.notifier).value = desired;
    ref.read(checkIpNumProvider.notifier).add();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final currentMacOS = macOS;
    if (currentMacOS != null) {
      unawaited(
        restoreDnsOnDispose(currentMacOS.updateDns).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          commonPrint.log(
            'Failed to restore macOS DNS during dispose: '
            '$error\n$stackTrace',
            logLevel: LogLevel.warning,
          );
        }),
      );
    }
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    commonPrint.log('$state');
    if (state == AppLifecycleState.resumed) {
      permissions.check();
      render?.resume();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ref.read(setupActionProvider.notifier).tryCheckIp();
        if (system.isAndroid) {
          unawaited(
            runAsyncSafely(
              operation: () =>
                  ref.read(coreActionProvider.notifier).tryStartCore(),
              onError: (error, stackTrace) {
                commonPrint.log(
                  'Failed to reconnect core after resume: '
                  '$error\n$stackTrace',
                  logLevel: LogLevel.error,
                );
                globalState.showNotifier(error.toString());
              },
            ),
          );
        }
      });
    }
  }

  @override
  void didChangePlatformBrightness() {
    globalState.container.read(themeActionProvider.notifier).updateBrightness();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerHover: (_) {
        render?.resume();
      },
      child: widget.child,
    );
  }
}

class AppEnvManager extends StatelessWidget {
  final Widget child;

  const AppEnvManager({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      if (globalState.isPre) {
        return Banner(
          message: 'DEBUG',
          location: BannerLocation.topEnd,
          child: child,
        );
      }
    }
    if (globalState.isPre) {
      return Banner(
        message: 'PRE',
        location: BannerLocation.topEnd,
        child: child,
      );
    }
    return child;
  }
}

class AppSidebarContainer extends ConsumerWidget {
  final Widget child;

  const AppSidebarContainer({super.key, required this.child});

  // Widget _buildLoading() {
  //   return Consumer(
  //     builder: (_, ref, _) {
  //       final loading = ref.watch(loadingProvider);
  //       final isMobileView = ref.watch(isMobileViewProvider);
  //       return loading && !isMobileView
  //           ? RotatedBox(
  //               quarterTurns: 1,
  //               child: const LinearProgressIndicator(),
  //             )
  //           : Container();
  //     },
  //   );
  // }

  Widget _buildBackground({
    required BuildContext context,
    required Widget child,
  }) {
    return Material(color: context.colorScheme.surfaceContainer, child: child);
    // if (!system.isMacOS) {
    //   return Material(
    //     color: context.colorScheme.surfaceContainer,
    //     child: child,
    //   );
    // }
    // return child;
    // return TransparentMacOSSidebar(
    //   child: Material(color: Colors.transparent, child: child),
    // );
  }

  void _updateSideBarWidth(
    BuildContext context,
    WidgetRef ref,
    double contentWidth,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      ref.read(sideWidthProvider.notifier).value =
          ref.read(viewSizeProvider.select((state) => state.width)) -
          contentWidth;
    });
  }

  void _handleToPage(PageLabel pageLabel) {
    globalState.container
        .read(currentPageLabelProvider.notifier)
        .toPage(pageLabel);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigationState = ref.watch(navigationStateProvider);
    final navigationItems = navigationState.navigationItems;
    final isMobileView = navigationState.viewMode == ViewMode.mobile;
    if (isMobileView) {
      return child;
    }
    final currentIndex = navigationState.currentIndex;
    final showLabel = ref.watch(appSettingProvider).showLabel;
    return Row(
      children: [
        _buildBackground(
          context: context,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (system.isMacOS) const SizedBox(height: 22),
                const SizedBox(height: 10),
                if (!system.isMacOS) ...[
                  const ClipRect(child: AppIcon()),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: ScrollConfiguration(
                    behavior: HiddenBarScrollBehavior(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: NavigationRail(
                            scrollable: true,
                            minExtendedWidth: 200,
                            backgroundColor: Colors.transparent,
                            selectedLabelTextStyle: context
                                .textTheme
                                .labelLarge!
                                .copyWith(color: context.colorScheme.onSurface),
                            unselectedLabelTextStyle: context
                                .textTheme
                                .labelLarge!
                                .copyWith(color: context.colorScheme.onSurface),
                            destinations: navigationItems
                                .map(
                                  (e) => NavigationRailDestination(
                                    icon: e.icon,
                                    label: Text(Intl.message(e.label.name)),
                                  ),
                                )
                                .toList(),
                            onDestinationSelected: (index) {
                              _handleToPage(navigationItems[index].label);
                            },
                            extended: false,
                            selectedIndex: currentIndex,
                            labelType: showLabel
                                ? NavigationRailLabelType.all
                                : NavigationRailLabelType.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                IconButton(
                  onPressed: () {
                    ref
                        .read(appSettingProvider.notifier)
                        .update(
                          (state) =>
                              state.copyWith(showLabel: !state.showLabel),
                        );
                  },
                  icon: Icon(
                    Icons.menu,
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: ClipRect(
            child: LayoutBuilder(
              builder: (_, constraints) {
                _updateSideBarWidth(context, ref, constraints.maxWidth);
                return child;
              },
            ),
          ),
        ),
      ],
    );
  }
}
