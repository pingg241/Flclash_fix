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

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  int _trafficEpoch = 0;
  Future<void>? _trafficRequest;

  @override
  void build() {}

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
      ref.read(trafficsProvider.notifier).addTraffic(snapshot.now);
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
  }

  Future<void> autoCheckUpdate() async {
    if (!ref.read(appSettingProvider).autoCheckUpdate) return;
    final res = await request.checkForUpdate();
    checkUpdateResultHandle(data: res);
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
