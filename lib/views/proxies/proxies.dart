import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/common.dart';
import 'package:fl_clash/models/state.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/proxies/delay_test_controller.dart';
import 'package:fl_clash/views/proxies/list.dart';
import 'package:fl_clash/views/proxies/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'setting.dart';
import 'tab.dart';

class ProxiesView extends ConsumerStatefulWidget {
  const ProxiesView({super.key});

  @override
  ConsumerState<ProxiesView> createState() => _ProxiesViewState();
}

class _ProxiesViewState extends ConsumerState<ProxiesView> {
  final GlobalKey<CommonScaffoldState> _scaffoldKey = GlobalKey();
  final GlobalKey<ProxiesTabViewState> _proxiesTabKey = GlobalKey();
  bool _hasProviders = false;
  final _delay = DelayTestController.instance;

  bool get _isTab => ref.read(
    proxiesStyleSettingProvider.select((s) => s.type == ProxiesType.tab),
  );

  @override
  void initState() {
    super.initState();
    ref.listenManual(providersProvider.select((state) => state.isNotEmpty), (
      prev,
      next,
    ) {
      if (prev != next) {
        setState(() {
          _hasProviders = next;
        });
      }
    }, fireImmediately: true);
    ref.listenManual(currentProfileIdProvider, (prev, next) {
      if (prev != next) {
        _delay.invalidate();
      }
    });
    ref.listenManual(
      currentPageLabelProvider.select((state) => state == PageLabel.proxies),
      (prev, next) {
        if (prev != next && next == false) {
          _scaffoldKey.currentState?.handleExitSearching();
          _delay.invalidate();
        }
      },
    );
  }

  @override
  void dispose() {
    _delay.invalidate();
    super.dispose();
  }

  Future<void> _runDelayTest() async {
    await _delay.runForCurrentScope(isTab: _isTab);
  }

  Widget _buildTitleRefreshButton() {
    return ListenableBuilder(
      listenable: _delay,
      builder: (context, _) {
        final scheme = context.colorScheme;
        final total = _delay.total;
        final done = _delay.done;
        final running = _delay.running;
        final progressText = _delay.progressText;
        final ratio = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
        final accent = scheme.primary;
        // Keep the running counter stable while progress changes.
        final sample = delayTestProgressMeasureText(total);
        final style = context.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        final textWidth =
            (TextPainter(
              text: TextSpan(text: sample, style: style),
              maxLines: 1,
              textDirection: TextDirection.ltr,
            )..layout()).width +
            2;

        return Tooltip(
          message: context.appLocalizations.delayTest,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: running ? null : _runDelayTest,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (progressText != null) ...[
                      SizedBox(
                        width: textWidth,
                        child: Text(
                          progressText,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          style: style?.copyWith(color: accent),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: running
                          ? CircularProgressIndicator(
                              value: total > 0 && ratio > 0 && ratio < 1
                                  ? ratio
                                  : null,
                              strokeWidth: 2.2,
                              color: accent,
                              backgroundColor: accent.withValues(alpha: 0.18),
                            )
                          : Icon(
                              Icons.refresh_rounded,
                              size: 22,
                              color: accent,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final isTab = ref.watch(
      proxiesStyleSettingProvider.select((s) => s.type == ProxiesType.tab),
    );
    return [
      if (isTab)
        IconButton(
          tooltip: appLocalizations.scrollToSelected,
          onPressed: () {
            _proxiesTabKey.currentState?.scrollToGroupSelected();
          },
          icon: const Icon(Icons.my_location_outlined),
        ),
      CommonPopupBox(
        targetBuilder: (open) {
          return IconButton(
            tooltip: appLocalizations.more,
            onPressed: () {
              final isMobile = ref.read(isMobileViewProvider);
              open(offset: Offset(0, isMobile ? 0 : 20));
            },
            icon: const Icon(Icons.more_vert),
          );
        },
        popup: CommonPopupMenu(
          items: [
            PopupMenuItemData(
              icon: Icons.tune,
              label: appLocalizations.settings,
              onPressed: () {
                showSheet(
                  context: context,
                  props: const SheetProps(isScrollControlled: true),
                  builder: (_) {
                    return AdaptiveSheetScaffold(
                      body: const ProxiesSetting(),
                      title: appLocalizations.settings,
                    );
                  },
                );
              },
            ),
            if (_hasProviders)
              PopupMenuItemData(
                icon: Icons.poll_outlined,
                label: appLocalizations.providers,
                onPressed: () {
                  showExtend(
                    context,
                    builder: (_) {
                      return const ProvidersView();
                    },
                  );
                },
              ),
          ],
        ),
      ),
    ];
  }

  void _onSearch(String value) {
    ref.read(queryProvider(QueryTag.proxies).notifier).value = value;
  }

  @override
  Widget build(BuildContext context) {
    final proxiesType = ref.watch(
      proxiesStyleSettingProvider.select((state) => state.type),
    );
    final isLoading = ref.watch(loadingProvider(LoadingTag.proxies));
    return CommonScaffold(
      key: _scaffoldKey,
      isLoading: isLoading,
      resizeToAvoidBottomInset: false,
      titleTrailing: _buildTitleRefreshButton(),
      actions: _buildActions(context),
      title: context.appLocalizations.proxies,
      searchState: AppBarSearchState(onSearch: _onSearch),
      body: switch (proxiesType) {
        ProxiesType.tab => ProxiesTabView(key: _proxiesTabKey),
        ProxiesType.list => const ProxiesListView(),
      },
    );
  }
}
