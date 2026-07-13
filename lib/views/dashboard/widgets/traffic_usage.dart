import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TrafficUsage extends StatelessWidget {
  const TrafficUsage({super.key});

  Widget _buildTrafficDataItem(
    BuildContext context,
    Icon icon,
    num trafficValue,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      mainAxisSize: MainAxisSize.max,
      children: [
        Flexible(
          flex: 1,
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: 8),
              Flexible(
                flex: 1,
                child: Text(
                  trafficValue.traffic.value,
                  style: context.textTheme.bodySmall,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
        Text(
          trafficValue.traffic.unit,
          style: context.textTheme.bodySmall?.toLighter,
        ),
      ],
    );
  }

  Widget _legendDot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final scheme = context.colorScheme;
    final upColor = scheme.chartUp;
    final downColor = scheme.chartDown;
    return SizedBox(
      height: getWidgetHeight(2),
      child: RepaintBoundary(
        child: CommonCard(
          info: Info(
            label: appLocalizations.trafficUsage,
            iconData: Icons.data_saver_off,
          ),
          onPressed: () {},
          child: Consumer(
            builder: (_, ref, _) {
              final totalTraffic = ref.watch(totalTrafficProvider);
              final upTotalTrafficValue = totalTraffic.up;
              final downTotalTrafficValue = totalTraffic.down;
              return Padding(
                padding: baseInfoEdgeInsets.copyWith(top: 0),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            AspectRatio(
                              aspectRatio: 1,
                              child: DonutChart(
                                data: [
                                  DonutChartData(
                                    value: upTotalTrafficValue.toDouble(),
                                    color: upColor,
                                  ),
                                  DonutChartData(
                                    value: downTotalTrafficValue.toDouble(),
                                    color: downColor,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: LayoutBuilder(
                                builder: (_, container) {
                                  final uploadText = Text(
                                    maxLines: 1,
                                    appLocalizations.upload,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.textTheme.bodySmall,
                                  );
                                  final downloadText = Text(
                                    maxLines: 1,
                                    appLocalizations.download,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.textTheme.bodySmall,
                                  );
                                  final uploadTextSize = globalState.measure
                                      .computeTextSize(uploadText);
                                  final downloadTextSize = globalState.measure
                                      .computeTextSize(downloadText);
                                  final maxTextWidth = max(
                                    uploadTextSize.width,
                                    downloadTextSize.width,
                                  );
                                  if (maxTextWidth + 24 > container.maxWidth) {
                                    return Container();
                                  }
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _legendDot(upColor),
                                          const SizedBox(width: 6),
                                          Text(
                                            maxLines: 1,
                                            appLocalizations.upload,
                                            overflow: TextOverflow.ellipsis,
                                            style: context.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: scheme.onSurface,
                                                ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _legendDot(downColor),
                                          const SizedBox(width: 6),
                                          Text(
                                            maxLines: 1,
                                            appLocalizations.download,
                                            overflow: TextOverflow.ellipsis,
                                            style: context.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: scheme.onSurface,
                                                ),
                                          ),
                                        ],
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
                    _buildTrafficDataItem(
                      context,
                      Icon(Icons.arrow_upward, color: upColor, size: 14),
                      upTotalTrafficValue,
                    ),
                    const SizedBox(height: 8),
                    _buildTrafficDataItem(
                      context,
                      Icon(Icons.arrow_downward, color: downColor, size: 14),
                      downTotalTrafficValue,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
