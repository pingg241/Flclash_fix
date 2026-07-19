import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';

typedef MemorySampler = Future<num> Function();

class MemoryInfo extends StatefulWidget {
  final MemorySampler? sampler;

  const MemoryInfo({super.key, @visibleForTesting this.sampler});

  @override
  State<MemoryInfo> createState() => _MemoryInfoState();
}

class _MemoryInfoState extends State<MemoryInfo> {
  final _memoryStateNotifier = ValueNotifier<num>(0);
  late final AsyncPeriodicTask _poller;

  @override
  void initState() {
    super.initState();
    _poller = AsyncPeriodicTask(
      interval: const Duration(seconds: 2),
      task: _updateMemory,
      onError: (error, stackTrace) {
        commonPrint.log(
          'Memory polling failed: $error\n$stackTrace',
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

  @override
  void dispose() {
    _poller.stop();
    _memoryStateNotifier.dispose();
    super.dispose();
  }

  Future<void> _updateMemory() async {
    final sampler = widget.sampler;
    final num memory;
    if (sampler != null) {
      memory = await sampler();
    } else {
      final rss = ProcessInfo.currentRss;
      memory = coreController.isCompleted
          ? await coreController.getMemory() + rss
          : rss;
    }
    if (mounted) {
      _memoryStateNotifier.value = memory;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return SizedBox(
      height: getWidgetHeight(1),
      child: RepaintBoundary(
        child: CommonCard(
          info: Info(
            iconData: Icons.memory,
            label: appLocalizations.memoryInfo,
          ),
          onPressed: () {
            coreController.requestGc();
          },
          child: Container(
            padding: baseInfoEdgeInsets.copyWith(top: 0),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: globalState.measure.bodyMediumHeight + 2,
                  child: ValueListenableBuilder(
                    valueListenable: _memoryStateNotifier,
                    builder: (_, memory, _) {
                      final traffic = memory.traffic;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Text(
                            traffic.value,
                            style: context.textTheme.bodyMedium?.toLight
                                .adjustSize(1),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            traffic.unit,
                            style: context.textTheme.bodyMedium?.toLight
                                .adjustSize(1),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
