import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class LogsView extends ConsumerStatefulWidget {
  const LogsView({super.key});

  @override
  ConsumerState<LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends ConsumerState<LogsView> {
  final _revisionNotifier = ValueNotifier<int>(0);
  final _autoScrollNotifier = ValueNotifier<bool>(true);
  late ScrollController _scrollController;

  List<Log> _logs = [];
  List<String> _keywords = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _logs = ref.read(logsProvider).list;
    _scrollController = ScrollController(initialScrollOffset: double.maxFinite);
    ref.listenManual(logsProvider, (_, next) {
      _logs = next.list;
      updateLogsThrottler();
    });
  }

  List<Widget> _buildActions() {
    return [
      IconButton(
        onPressed: () {
          _handleExport();
        },
        icon: const Icon(Icons.save_as_outlined),
      ),
    ];
  }

  void _onSearch(String value) {
    _query = value;
    _notifyChanged();
  }

  void _onKeywordsUpdate(List<String> keywords) {
    _keywords = keywords;
    _notifyChanged();
  }

  List<Log> get _visibleLogs {
    if (_query.isEmpty && _keywords.isEmpty) {
      return _logs;
    }
    return LogsState(logs: _logs, keywords: _keywords, query: _query).list;
  }

  void _notifyChanged() {
    _revisionNotifier.value++;
  }

  @override
  void dispose() {
    _revisionNotifier.dispose();
    _autoScrollNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleExport() async {
    final appLocalizations = context.appLocalizations;
    final res = await globalState.safeRun<bool>(() async {
      return globalState.container.read(logsProvider.notifier).exportLogs();
    }, title: appLocalizations.exportLogs);
    if (res != true) return;
    globalState.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(text: appLocalizations.exportSuccess),
    );
  }

  void updateLogsThrottler() {
    throttler.call(FunctionTag.logs, () {
      if (!mounted) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _notifyChanged();
        }
      });
    }, duration: commonDuration);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonScaffold(
      actions: _buildActions(),
      onKeywordsUpdate: _onKeywordsUpdate,
      searchState: AppBarSearchState(onSearch: _onSearch),
      title: appLocalizations.logs,
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _autoScrollNotifier,
        builder: (_, autoScrollToEnd, _) {
          return FadeRotationScaleBox(
            child: FloatingActionButton(
              key: ValueKey(autoScrollToEnd),
              onPressed: () {
                _autoScrollNotifier.value = !autoScrollToEnd;
              },
              child: autoScrollToEnd
                  ? const Icon(Icons.block)
                  : const Icon(Icons.vertical_align_top),
            ),
          );
        },
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: _revisionNotifier,
        builder: (context, _, _) {
          final logs = _visibleLogs;
          if (logs.isEmpty) {
            return NullStatus(
              illustration: const LogEmptyIllustration(),
              label: appLocalizations.nullTip(appLocalizations.logs),
            );
          }
          return ValueListenableBuilder<bool>(
            valueListenable: _autoScrollNotifier,
            builder: (_, autoScrollToEnd, _) {
              return Align(
                alignment: Alignment.topCenter,
                child: ScrollToEndBox(
                  onCancelToEnd: () {
                    _autoScrollNotifier.value = false;
                  },
                  controller: _scrollController,
                  enable: autoScrollToEnd,
                  dataToken: logs.last,
                  child: CommonScrollBar(
                    controller: _scrollController,
                    child: SuperListView.separated(
                      physics: const NextClampingScrollPhysics(),
                      reverse: true,
                      controller: _scrollController,
                      itemBuilder: (_, index) {
                        final log = logs[index];
                        return LogItem(
                          key: _LogItemKey(log, index),
                          log: log,
                          onClick: (value) {
                            context.commonScaffoldState?.addKeyword(value);
                          },
                        );
                      },
                      separatorBuilder: (_, _) => const Divider(height: 0),
                      itemCount: logs.length,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _LogItemKey extends LocalKey {
  final Log log;
  final int index;

  const _LogItemKey(this.log, this.index);

  @override
  bool operator ==(Object other) {
    return other is _LogItemKey &&
        identical(log, other.log) &&
        index == other.index;
  }

  @override
  int get hashCode => Object.hash(identityHashCode(log), index);
}

class LogItem extends StatelessWidget {
  final Log log;
  final Function(String)? onClick;

  const LogItem({super.key, required this.log, this.onClick});

  @override
  Widget build(BuildContext context) {
    return ListItem(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: () {},
      title: SelectableText(
        log.payload,
        style: context.textTheme.bodyLarge?.copyWith(
          color: log.logLevel.color(context),
        ),
      ),
      subtitle: Column(
        children: [
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CommonChip(
                onPressed: () {
                  if (onClick == null) return;
                  onClick!(log.logLevel.name);
                },
                label: log.logLevel.name,
              ),
              Text(
                log.dateTime,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurface.opacity80,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
