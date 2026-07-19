import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'item.dart';

typedef ConnectionsLoader = Future<List<TrackerInfo>> Function();

class ConnectionsView extends ConsumerStatefulWidget {
  final ConnectionsLoader? loader;

  const ConnectionsView({super.key, @visibleForTesting this.loader});

  @override
  ConsumerState<ConnectionsView> createState() => _ConnectionsViewState();
}

class _ConnectionsViewState extends ConsumerState<ConnectionsView> {
  final _connectionsStateNotifier = ValueNotifier<TrackerInfosState>(
    const TrackerInfosState(),
  );
  final ScrollController _scrollController = ScrollController();
  late final AsyncPeriodicTask _poller;
  int _requestGeneration = 0;

  List<Widget> _buildActions() {
    return [
      IconButton(
        onPressed: () async {
          await globalState.safeRun<void>(() async {
            await coreController.closeConnections();
            await _updateConnections();
          });
        },
        icon: const Icon(Icons.delete_sweep_outlined),
      ),
    ];
  }

  void _onSearch(String value) {
    _connectionsStateNotifier.value = _connectionsStateNotifier.value.copyWith(
      query: value,
    );
  }

  void _onKeywordsUpdate(List<String> keywords) {
    _connectionsStateNotifier.value = _connectionsStateNotifier.value.copyWith(
      keywords: keywords,
    );
  }

  @override
  void initState() {
    super.initState();
    _poller = AsyncPeriodicTask(
      interval: const Duration(seconds: 1),
      task: _updateConnections,
      onError: (error, stackTrace) {
        commonPrint.log(
          'Connection polling failed: $error\n$stackTrace',
          logLevel: LogLevel.warning,
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _poller.start(immediate: true);
      }
    });
  }

  Future<void> _updateConnections() async {
    final generation = ++_requestGeneration;
    final trackerInfos =
        await (widget.loader ?? coreController.getConnections)();
    if (!mounted || generation != _requestGeneration) {
      return;
    }
    _connectionsStateNotifier.value = _connectionsStateNotifier.value.copyWith(
      trackerInfos: trackerInfos,
    );
  }

  Future<void> _handleBlockConnection(String id) async {
    await coreController.closeConnection(id);
    await _updateConnections();
  }

  @override
  void dispose() {
    _requestGeneration++;
    _poller.stop();
    _connectionsStateNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonScaffold(
      title: appLocalizations.connections,
      onKeywordsUpdate: _onKeywordsUpdate,
      searchState: AppBarSearchState(onSearch: _onSearch),
      actions: _buildActions(),
      body: ValueListenableBuilder<TrackerInfosState>(
        valueListenable: _connectionsStateNotifier,
        builder: (context, state, _) {
          final connections = state.list;
          if (connections.isEmpty) {
            return NullStatus(
              label: appLocalizations.nullTip(appLocalizations.connections),
              illustration: const ConnectionEmptyIllustration(),
            );
          }
          // 2 * n - 1: connection items interleaved with dividers
          final itemCount = connections.isEmpty
              ? 0
              : connections.length * 2 - 1;
          return SuperListView.builder(
            controller: _scrollController,
            itemBuilder: (context, index) {
              if (index.isOdd) {
                return const Divider(height: 0);
              }
              final trackerInfo = connections[index ~/ 2];
              return TrackerInfoItem(
                key: Key(trackerInfo.id),
                trackerInfo: trackerInfo,
                onClickKeyword: (value) {
                  context.commonScaffoldState?.addKeyword(value);
                },
                trailing: IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(minimumSize: Size.zero),
                  icon: const Icon(Icons.block),
                  onPressed: () async {
                    await globalState.safeRun<void>(
                      () => _handleBlockConnection(trackerInfo.id),
                    );
                  },
                ),
                detailTitle: appLocalizations.details(
                  appLocalizations.connection,
                ),
              );
            },
            itemCount: itemCount,
          );
        },
      ),
    );
  }
}
