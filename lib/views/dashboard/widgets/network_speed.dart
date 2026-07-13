import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NetworkSpeed extends StatefulWidget {
  const NetworkSpeed({super.key});

  @override
  State<NetworkSpeed> createState() => _NetworkSpeedState();
}

class _NetworkSpeedState extends State<NetworkSpeed> {
  static const List<Point> _seedPoints = [Point(0, 0), Point(1, 0)];

  List<Point> _getPoints(List<Traffic> traffics) {
    final trafficPoints = traffics
        .asMap()
        .map(
          (index, e) => MapEntry(
            index,
            Point(
              (index + _seedPoints.length).toDouble(),
              e.speed.toDouble(),
            ),
          ),
        )
        .values
        .toList();
    return [..._seedPoints, ...trafficPoints];
  }

  Traffic _getLastTraffic(List<Traffic> traffics) {
    if (traffics.isEmpty) {
      return const Traffic();
    }
    return traffics.last;
  }

  Widget _speedChip({
    required BuildContext context,
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: context.textTheme.labelMedium?.copyWith(
            color: context.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final scheme = context.colorScheme;
    return SizedBox(
      height: getWidgetHeight(2),
      child: RepaintBoundary(
        child: CommonCard(
          onPressed: () {},
          child: Consumer(
            builder: (_, ref, _) {
              final traffics = ref.watch(trafficsProvider).list;
              final last = _getLastTraffic(traffics);
              final hasLiveData = traffics.any((t) => t.speed > 0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: baseInfoEdgeInsets.copyWith(bottom: 0),
                    child: Row(
                      children: [
                        Flexible(
                          child: InfoHeader(
                            padding: EdgeInsets.zero,
                            info: Info(
                              label: appLocalizations.networkSpeed,
                              iconData: Icons.speed_sharp,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _speedChip(
                          context: context,
                          icon: Icons.arrow_upward_rounded,
                          text: '${last.up.traffic.show}/s',
                          color: scheme.chartUp,
                        ),
                        const SizedBox(width: 12),
                        _speedChip(
                          context: context,
                          icon: Icons.arrow_downward_rounded,
                          text: '${last.down.traffic.show}/s',
                          color: scheme.chartDown,
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          LineChart(
                            gradient: true,
                            color: scheme.chartUp,
                            points: _getPoints(traffics),
                          ),
                          if (!hasLiveData)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Container(
                                  height: 1,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  color: scheme.outlineVariant.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
