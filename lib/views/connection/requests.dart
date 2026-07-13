import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'item.dart';

class RequestsView extends ConsumerStatefulWidget {
  const RequestsView({super.key});

  @override
  ConsumerState<RequestsView> createState() => _RequestsViewState();
}

class _RequestsViewState extends ConsumerState<RequestsView> {
  final _revisionNotifier = ValueNotifier<int>(0);
  final _autoScrollNotifier = ValueNotifier<bool>(true);
  List<TrackerInfo> _requests = [];
  List<String> _keywords = [];
  String _query = '';
  late final ScrollController _scrollController;

  void _onSearch(String value) {
    _query = value;
    _notifyChanged();
  }

  void _onKeywordsUpdate(List<String> keywords) {
    _keywords = keywords;
    _notifyChanged();
  }

  List<TrackerInfo> get _visibleRequests {
    if (_query.isEmpty && _keywords.isEmpty) {
      return _requests;
    }
    return TrackerInfosState(
      trackerInfos: _requests,
      keywords: _keywords,
      query: _query,
    ).list;
  }

  void _notifyChanged() {
    _revisionNotifier.value++;
  }

  @override
  void initState() {
    super.initState();
    _requests = ref.read(requestsProvider).list;
    _scrollController = ScrollController(initialScrollOffset: double.maxFinite);
    ref.listenManual(requestsProvider, (_, next) {
      _requests = next.list;
      updateRequestsThrottler();
    });
  }

  @override
  void dispose() {
    _revisionNotifier.dispose();
    _autoScrollNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void updateRequestsThrottler() {
    throttler.call(FunctionTag.requests, () {
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
      title: appLocalizations.requests,
      searchState: AppBarSearchState(onSearch: _onSearch),
      onKeywordsUpdate: _onKeywordsUpdate,
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
          final requests = _visibleRequests;
          if (requests.isEmpty) {
            return NullStatus(
              label: appLocalizations.nullTip(appLocalizations.requests),
            );
          }
          return ValueListenableBuilder<bool>(
            valueListenable: _autoScrollNotifier,
            builder: (_, autoScrollToEnd, _) {
              return Align(
                alignment: Alignment.topCenter,
                child: CommonScrollBar(
                  trackVisibility: false,
                  controller: _scrollController,
                  child: ScrollToEndBox(
                    controller: _scrollController,
                    dataToken: requests.last,
                    enable: autoScrollToEnd,
                    onCancelToEnd: () {
                      _autoScrollNotifier.value = false;
                    },
                    child: SuperListView.separated(
                      reverse: true,
                      physics: const NextClampingScrollPhysics(),
                      controller: _scrollController,
                      itemBuilder: (_, index) {
                        final trackerInfo = requests[index];
                        return TrackerInfoItem(
                          key: ValueKey(trackerInfo.id),
                          trackerInfo: trackerInfo,
                          onClickKeyword: (value) {
                            context.commonScaffoldState?.addKeyword(value);
                          },
                          detailTitle: appLocalizations.details(
                            appLocalizations.request,
                          ),
                        );
                      },
                      separatorBuilder: (_, _) => const Divider(height: 0),
                      itemCount: requests.length,
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
