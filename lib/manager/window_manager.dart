import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_ext/window_ext.dart';
import 'package:window_manager/window_manager.dart';

class WindowManager extends ConsumerStatefulWidget {
  final Widget child;

  const WindowManager({super.key, required this.child});

  @override
  ConsumerState<WindowManager> createState() => _WindowContainerState();
}

class _WindowContainerState extends ConsumerState<WindowManager>
    with WindowListener, WindowExtListener {
  int _autoLaunchGeneration = 0;
  int _positionGeneration = 0;
  int _sizeGeneration = 0;

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(appSettingProvider.select((state) => state.autoLaunch), (
      prev,
      next,
    ) {
      if (prev != next) {
        final generation = ++_autoLaunchGeneration;
        unawaited(_updateAutoLaunch(prev, next, generation));
      }
    });
    windowExtManager.addListener(this);
    windowManager.addListener(this);
  }

  Future<void> _updateAutoLaunch(
    bool? previous,
    bool next,
    int generation,
  ) async {
    bool? updated;
    try {
      updated = await debouncer.callAsync<bool>(
        FunctionTag.autoLaunch,
        () async {
          if (!mounted || generation != _autoLaunchGeneration) {
            return true;
          }
          final launcher = autoLaunch;
          if (launcher == null) {
            return false;
          }
          return launcher.updateStatus(next);
        },
      );
    } catch (error, stackTrace) {
      commonPrint.log(
        'Failed to update auto launch: $error\n$stackTrace',
        logLevel: LogLevel.warning,
      );
      updated = false;
    }
    if (!mounted ||
        generation != _autoLaunchGeneration ||
        updated == null ||
        updated) {
      return;
    }
    final current = ref.read(appSettingProvider).autoLaunch;
    if (current == next) {
      ref
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(autoLaunch: previous ?? !next));
    }
  }

  @override
  void onWindowClose() {
    unawaited(
      runAsyncSafely(
        operation: () async {
          await ref.read(systemActionProvider.notifier).handleClose();
          super.onWindowClose();
        },
        onError: (error, stackTrace) {
          commonPrint.log(
            'Failed to handle window close: $error\n$stackTrace',
            logLevel: LogLevel.error,
          );
          globalState.showNotifier(error.toString());
        },
      ),
    );
  }

  @override
  void onWindowFocus() {
    super.onWindowFocus();
    commonPrint.log('focus');
    render?.resume();
  }

  @override
  Future<void> onShouldTerminate() async {
    await ref.read(systemActionProvider.notifier).handleExit();
    super.onShouldTerminate();
  }

  @override
  void onWindowMoved() {
    super.onWindowMoved();
    unawaited(_updateWindowPosition(++_positionGeneration));
  }

  Future<void> _updateWindowPosition(int generation) async {
    try {
      final offset = await windowManager.getPosition();
      if (!mounted || generation != _positionGeneration) {
        return;
      }
      ref
          .read(windowSettingProvider.notifier)
          .update((state) => state.copyWith(top: offset.dy, left: offset.dx));
    } catch (error, stackTrace) {
      commonPrint.log(
        'Failed to read window position: $error\n$stackTrace',
        logLevel: LogLevel.warning,
      );
    }
  }

  @override
  Future<void> onWindowResized() async {
    super.onWindowResized();
    final generation = ++_sizeGeneration;
    try {
      final size = await windowManager.getSize();
      if (!mounted || generation != _sizeGeneration) {
        return;
      }
      ref
          .read(windowSettingProvider.notifier)
          .update(
            (state) => state.copyWith(width: size.width, height: size.height),
          );
    } catch (error, stackTrace) {
      commonPrint.log(
        'Failed to read window size: $error\n$stackTrace',
        logLevel: LogLevel.warning,
      );
    }
  }

  @override
  void onWindowMinimize() {
    ref.read(storeActionProvider.notifier).savePreferencesDebounce();
    commonPrint.log('minimize');
    render?.pause();
    super.onWindowMinimize();
  }

  @override
  void onWindowRestore() {
    commonPrint.log('restore');
    render?.resume();
    super.onWindowRestore();
  }

  @override
  void dispose() {
    _autoLaunchGeneration++;
    _positionGeneration++;
    _sizeGeneration++;
    debouncer.cancel(FunctionTag.autoLaunch);
    windowManager.removeListener(this);
    windowExtManager.removeListener(this);
    super.dispose();
  }
}

class WindowHeaderContainer extends StatelessWidget {
  final Widget child;

  const WindowHeaderContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (_, ref, child) {
        final isMobileView = ref.watch(isMobileViewProvider);
        final version = ref.watch(versionProvider);
        if ((version <= 10 || !isMobileView) && system.isMacOS) {
          return child!;
        }
        return Stack(
          children: [
            Column(
              children: [
                SizedBox(height: kHeaderHeight),
                Expanded(flex: 1, child: child!),
              ],
            ),
            const WindowHeader(),
          ],
        );
      },
      child: child,
    );
  }
}

class WindowHeader extends StatefulWidget {
  const WindowHeader({super.key});

  @override
  State<WindowHeader> createState() => _WindowHeaderState();
}

class _WindowHeaderState extends State<WindowHeader> {
  final isMaximizedNotifier = ValueNotifier<bool>(false);
  final isPinNotifier = ValueNotifier<bool>(false);
  int _maximizedGeneration = 0;
  int _pinGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_initNotifier());
  }

  Future<void> _initNotifier() async {
    final maximizedGeneration = _maximizedGeneration;
    final pinGeneration = _pinGeneration;
    try {
      final values = await Future.wait([
        windowManager.isMaximized(),
        windowManager.isAlwaysOnTop(),
      ]);
      if (!mounted) {
        return;
      }
      if (maximizedGeneration == _maximizedGeneration) {
        isMaximizedNotifier.value = values[0];
      }
      if (pinGeneration == _pinGeneration) {
        isPinNotifier.value = values[1];
      }
    } catch (error, stackTrace) {
      commonPrint.log(
        'Failed to initialize window state: $error\n$stackTrace',
        logLevel: LogLevel.warning,
      );
    }
  }

  @override
  void dispose() {
    _maximizedGeneration++;
    _pinGeneration++;
    isMaximizedNotifier.dispose();
    isPinNotifier.dispose();
    super.dispose();
  }

  Future<void> _updateMaximized() async {
    final generation = ++_maximizedGeneration;
    try {
      final isMaximized = await windowManager.isMaximized();
      if (isMaximized) {
        await windowManager.unmaximize();
        if (system.isWindows) {
          await windowExtManager.setWindowCornerPreference(round: true);
        }
      } else {
        await windowManager.maximize();
        if (system.isWindows) {
          await windowExtManager.setWindowCornerPreference(round: false);
        }
      }
    } catch (error, stackTrace) {
      commonPrint.log(
        'Failed to update maximized state: $error\n$stackTrace',
        logLevel: LogLevel.warning,
      );
    }
    try {
      final updated = await windowManager.isMaximized();
      if (mounted && generation == _maximizedGeneration) {
        isMaximizedNotifier.value = updated;
      }
    } catch (error, stackTrace) {
      commonPrint.log(
        'Failed to verify maximized state: $error\n$stackTrace',
        logLevel: LogLevel.warning,
      );
    }
  }

  Future<void> _updatePin() async {
    final generation = ++_pinGeneration;
    try {
      final isAlwaysOnTop = await windowManager.isAlwaysOnTop();
      await windowManager.setAlwaysOnTop(!isAlwaysOnTop);
    } catch (error, stackTrace) {
      commonPrint.log(
        'Failed to update always-on-top state: $error\n$stackTrace',
        logLevel: LogLevel.warning,
      );
    }
    try {
      final updated = await windowManager.isAlwaysOnTop();
      if (mounted && generation == _pinGeneration) {
        isPinNotifier.value = updated;
      }
    } catch (error, stackTrace) {
      commonPrint.log(
        'Failed to verify always-on-top state: $error\n$stackTrace',
        logLevel: LogLevel.warning,
      );
    }
  }

  Widget _buildActions() {
    return Row(
      children: [
        IconButton(
          onPressed: () => unawaited(_updatePin()),
          icon: ValueListenableBuilder(
            valueListenable: isPinNotifier,
            builder: (_, value, _) {
              return value
                  ? const Icon(Icons.push_pin)
                  : const Icon(Icons.push_pin_outlined);
            },
          ),
        ),
        IconButton(
          onPressed: () {
            unawaited(
              windowManager.minimize().catchError((
                Object error,
                StackTrace stackTrace,
              ) {
                commonPrint.log(
                  'Failed to minimize window: $error\n$stackTrace',
                  logLevel: LogLevel.warning,
                );
              }),
            );
          },
          icon: const Icon(Icons.remove),
        ),
        IconButton(
          onPressed: () => unawaited(_updateMaximized()),
          icon: ValueListenableBuilder(
            valueListenable: isMaximizedNotifier,
            builder: (_, value, _) {
              return value
                  ? const Icon(Icons.filter_none, size: 20)
                  : const Icon(Icons.crop_square);
            },
          ),
        ),
        IconButton(
          onPressed: () {
            unawaited(
              globalState.container
                  .read(systemActionProvider.notifier)
                  .handleClose()
                  .catchError((Object error, StackTrace stackTrace) {
                    commonPrint.log(
                      'Failed to close window: $error\n$stackTrace',
                      logLevel: LogLevel.warning,
                    );
                  }),
            );
          },
          icon: const Icon(Icons.close),
        ),
        // const SizedBox(
        //   width: 8,
        // ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Stack(
        alignment: AlignmentDirectional.center,
        children: [
          Positioned(
            child: GestureDetector(
              onPanStart: (_) {
                unawaited(
                  windowManager.startDragging().catchError((
                    Object error,
                    StackTrace stackTrace,
                  ) {
                    commonPrint.log(
                      'Failed to start window drag: $error\n$stackTrace',
                      logLevel: LogLevel.warning,
                    );
                  }),
                );
              },
              onDoubleTap: () {
                unawaited(_updateMaximized());
              },
              child: Container(
                color: context.colorScheme.secondary.opacity15,
                alignment: Alignment.centerLeft,
                height: kHeaderHeight,
              ),
            ),
          ),
          if (system.isMacOS)
            const Text(appName)
          else ...[
            Positioned(right: 0, child: _buildActions()),
          ],
        ],
      ),
    );
  }
}

class AppIcon extends StatelessWidget {
  const AppIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: ShapeDecoration(
        color: context.colorScheme.surfaceContainerHighest,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Transform.translate(
        offset: const Offset(0, -1),
        child: Image.asset('assets/images/icon.png', width: 34, height: 34),
      ),
    );
  }
}
