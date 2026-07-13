import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StartButton extends ConsumerStatefulWidget {
  const StartButton({super.key});

  @override
  ConsumerState<StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends ConsumerState<StartButton>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late Animation<double> _animation;
  bool isStart = false;

  /// Soft peach fill — fixed, not ColorScheme.primary (M3 deepens brand orange).
  static const Color _fill = BrandSoft.fill;
  static const Color _ink = BrandSoft.onFill;

  /// Compact control size (less "chubby" than default 56 FAB).
  static const double _size = 44;

  /// Modest corner radius for a clean rectangle (not stadium / bubble).
  static const double _corner = 10;

  @override
  void initState() {
    super.initState();
    isStart = ref.read(isStartProvider);
    _controller = AnimationController(
      vsync: this,
      value: isStart ? 1 : 0,
      duration: const Duration(milliseconds: 200),
    );
    _animation = CurvedAnimation(parent: _controller!, curve: Curves.easeInOut);
    // Drive icon only from real running state — never optimistic flip.
    ref.listenManual(isStartProvider, (prev, next) {
      if (next != isStart) {
        isStart = next;
        updateController();
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  void handleSwitchStart() {
    if (ref.read(isStartingProvider)) {
      return;
    }
    final wantStart = !ref.read(isStartProvider);
    debouncer.call(FunctionTag.updateStatus, () {
      return globalState.container
          .read(setupActionProvider.notifier)
          .updateStatus(wantStart, isInit: !ref.read(initProvider));
    }, duration: commonDuration);
  }

  void updateController() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (isStart) {
        _controller?.forward();
      } else {
        _controller?.reverse();
      }
    });
  }

  OutlinedBorder get _shape =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(_corner));

  @override
  Widget build(BuildContext context) {
    final hasProfile = ref.watch(
      profilesProvider.select((state) => state.isNotEmpty),
    );
    if (!hasProfile) {
      return const SizedBox.shrink();
    }
    final suspend = ref.watch(suspendProvider);
    final isStarting = ref.watch(isStartingProvider);
    final appLocalizations = context.appLocalizations;
    final theme = Theme.of(context);

    return RepaintBoundary(
      child: Theme(
        data: theme.copyWith(
          floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
            backgroundColor: _fill,
            foregroundColor: _ink,
            elevation: 0,
            focusElevation: 0,
            hoverElevation: 0,
            highlightElevation: 0,
            shape: _shape,
            sizeConstraints: const BoxConstraints.tightFor(
              width: _size,
              height: _size,
            ),
            extendedSizeConstraints: const BoxConstraints(
              minHeight: _size,
              maxHeight: _size,
              minWidth: _size,
            ),
          ),
        ),
        child: AnimatedBuilder(
          animation: _animation,
          builder: (_, _) {
            final showLabel = isStart || suspend || isStarting;
            final Widget icon;
            if (isStarting) {
              icon = const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: _ink),
              );
            } else {
              icon = AnimatedIcon(
                icon: AnimatedIcons.play_pause,
                progress: _animation,
                color: _ink,
                size: 22,
              );
            }

            if (!showLabel) {
              return SizedBox(
                width: _size,
                height: _size,
                child: FloatingActionButton(
                  heroTag: null,
                  elevation: 0,
                  highlightElevation: 0,
                  focusElevation: 0,
                  hoverElevation: 0,
                  backgroundColor: _fill,
                  foregroundColor: _ink,
                  shape: _shape,
                  onPressed: isStarting ? null : handleSwitchStart,
                  child: icon,
                ),
              );
            }

            return SizedBox(
              height: _size,
              child: FloatingActionButton.extended(
                heroTag: null,
                elevation: 0,
                highlightElevation: 0,
                focusElevation: 0,
                hoverElevation: 0,
                backgroundColor: _fill,
                foregroundColor: _ink,
                shape: _shape,
                extendedPadding: const EdgeInsets.symmetric(horizontal: 14),
                onPressed: isStarting ? null : handleSwitchStart,
                icon: icon,
                label: isStarting
                    ? Text(
                        appLocalizations.connecting,
                        maxLines: 1,
                        style: context.textTheme.titleSmall?.copyWith(
                          color: _ink,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : suspend
                    ? Text(
                        appLocalizations.suspended,
                        maxLines: 1,
                        style: context.textTheme.titleSmall?.copyWith(
                          color: _ink,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : Consumer(
                        builder: (_, ref, _) {
                          final runTime = ref.watch(runTimeProvider);
                          return Text(
                            utils.getTimeText(runTime),
                            maxLines: 1,
                            style: context.textTheme.titleSmall?.toSoftBold
                                .copyWith(color: _ink),
                          );
                        },
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}
