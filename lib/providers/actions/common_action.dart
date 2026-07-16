import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:url_launcher/url_launcher.dart';

part '../generated/actions/common_action.g.dart';

typedef TrafficSnapshot = ({Traffic now, Traffic total});
typedef TrafficSnapshotLoader =
    Future<TrafficSnapshot> Function(bool onlyStatisticsProxy);

final trafficSnapshotLoaderProvider = Provider<TrafficSnapshotLoader>(
  (_) => coreController.getTrafficSnapshot,
);

@visibleForTesting
class TrafficRateSampler {
  static const minimumSampleInterval = Duration(milliseconds: 500);
  static const maximumSampleInterval = Duration(seconds: 2);

  _TrafficRateBaseline? _baseline;

  Traffic sample({
    required Traffic fallback,
    required Traffic total,
    required Duration elapsed,
    required Object session,
  }) {
    final safeFallback = _safeTraffic(fallback);
    if (!_isValidTraffic(total)) {
      _baseline = null;
      return safeFallback;
    }

    final current = _TrafficRateBaseline(
      total: total,
      elapsed: elapsed,
      session: session,
    );
    final previous = _baseline;
    _baseline = current;
    if (previous == null || previous.session != session) {
      return safeFallback;
    }

    final elapsedMicroseconds =
        elapsed.inMicroseconds - previous.elapsed.inMicroseconds;
    final upDelta = total.up - previous.total.up;
    final downDelta = total.down - previous.total.down;
    if (elapsedMicroseconds < minimumSampleInterval.inMicroseconds ||
        elapsedMicroseconds > maximumSampleInterval.inMicroseconds ||
        upDelta < 0 ||
        downDelta < 0) {
      return safeFallback;
    }

    final elapsedSeconds = elapsedMicroseconds / Duration.microsecondsPerSecond;
    final up = upDelta / elapsedSeconds;
    final down = downDelta / elapsedSeconds;
    if (!up.isFinite || !down.isFinite) {
      return safeFallback;
    }
    return Traffic(up: up, down: down);
  }

  void reset() {
    _baseline = null;
  }

  static bool _isValidTraffic(Traffic traffic) {
    return traffic.up.isFinite &&
        traffic.down.isFinite &&
        traffic.up >= 0 &&
        traffic.down >= 0;
  }

  static Traffic _safeTraffic(Traffic traffic) {
    return Traffic(
      up: traffic.up.isFinite && traffic.up >= 0 ? traffic.up : 0,
      down: traffic.down.isFinite && traffic.down >= 0 ? traffic.down : 0,
    );
  }
}

class _TrafficRateBaseline {
  const _TrafficRateBaseline({
    required this.total,
    required this.elapsed,
    required this.session,
  });

  final Traffic total;
  final Duration elapsed;
  final Object session;
}

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  int _trafficEpoch = 0;
  Future<void>? _trafficRequest;
  final Stopwatch _trafficClock = Stopwatch()..start();
  final TrafficRateSampler _trafficRateSampler = TrafficRateSampler();

  @override
  void build() {
    ref.listen(coreStatusProvider, (previous, next) {
      if (previous == CoreStatus.connected && next != CoreStatus.connected) {
        invalidateTraffic();
      }
    });
    ref.listen(
      appSettingProvider.select((state) => state.onlyStatisticsProxy),
      (previous, next) {
        if (previous != next) {
          invalidateTraffic();
        }
      },
    );
  }

  Future<bool> updateStart() {
    return ref
        .read(setupActionProvider.notifier)
        .updateStatus(!ref.read(isStartProvider));
  }

  void updateSpeedStatistics() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(showTrayTitle: !state.showTrayTitle));
  }

  void updateMode() {
    ref.read(patchClashConfigProvider.notifier).update((state) {
      final index = Mode.values.indexWhere((item) => item == state.mode);
      if (index == -1) return state;
      final nextIndex = index + 1 > Mode.values.length - 1 ? 0 : index + 1;
      return state.copyWith(mode: Mode.values[nextIndex]);
    });
  }

  void updateRunTime() {
    final startTime = ref.read(setupActionProvider.notifier).startTime;
    if (startTime != null) {
      final startTimeStamp = startTime.millisecondsSinceEpoch;
      final nowTimeStamp = DateTime.now().millisecondsSinceEpoch;
      ref.read(runTimeProvider.notifier).value = nowTimeStamp - startTimeStamp;
    } else {
      ref.read(runTimeProvider.notifier).value = null;
    }
  }

  Future<void> updateTraffic() async {
    final inFlight = _trafficRequest;
    if (inFlight != null) {
      return inFlight;
    }
    final epoch = _trafficEpoch;
    late final Future<void> request;
    request = _updateTraffic(epoch).whenComplete(() {
      if (identical(_trafficRequest, request)) {
        _trafficRequest = null;
      }
    });
    _trafficRequest = request;
    return request;
  }

  Future<void> _updateTraffic(int epoch) async {
    final onlyStatisticsProxy = ref.read(
      appSettingProvider.select((state) => state.onlyStatisticsProxy),
    );
    try {
      final snapshot = await ref.read(trafficSnapshotLoaderProvider)(
        onlyStatisticsProxy,
      );
      if (epoch != _trafficEpoch || !ref.mounted) {
        return;
      }
      final traffic = _trafficRateSampler.sample(
        fallback: snapshot.now,
        total: snapshot.total,
        elapsed: _trafficClock.elapsed,
        session: (epoch, onlyStatisticsProxy),
      );
      ref.read(trafficsProvider.notifier).addTraffic(traffic);
      ref.read(totalTrafficProvider.notifier).value = snapshot.total;
    } catch (e, s) {
      commonPrint.log(
        'update traffic failed: $e, $s',
        logLevel: LogLevel.warning,
      );
    }
  }

  /// Invalidates a pending core response and allows the next session to poll.
  void invalidateTraffic() {
    _trafficEpoch++;
    _trafficRequest = null;
    _trafficRateSampler.reset();
  }

  Future<void> autoCheckUpdate() async {
    if (!ref.read(appSettingProvider).autoCheckUpdate) return;
    final res = await request.checkForUpdate();
    await checkUpdateResultHandle(data: res);
  }

  Future<void> checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool isUser = false,
  }) async {
    if (data != null) {
      final tagName = data['tag_name'];
      final body = data['body'];
      final submits = utils.parseReleaseBody(body);
      final context = globalState.navigatorKey.currentContext;
      if (context == null) {
        return;
      }
      final textTheme = context.textTheme;
      final res = await globalState.showMessage(
        title: currentAppLocalizations.discoverNewVersion,
        message: TextSpan(
          text: '$tagName \n',
          style: textTheme.headlineSmall,
          children: [
            TextSpan(text: '\n', style: textTheme.bodyMedium),
            for (final submit in submits)
              TextSpan(text: '- $submit \n', style: textTheme.bodyMedium),
          ],
        ),
        confirmText: currentAppLocalizations.goDownload,
        cancelText: isUser ? null : currentAppLocalizations.noLongerRemind,
      );
      if (res == true) {
        launchUrl(Uri.parse('https://github.com/$repository/releases/latest'));
      } else if (!isUser && res == false) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(autoCheckUpdate: false));
      }
    } else if (isUser) {
      globalState.showMessage(
        title: currentAppLocalizations.checkUpdate,
        message: TextSpan(text: currentAppLocalizations.checkUpdateError),
      );
    }
  }
}
