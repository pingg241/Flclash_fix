import 'dart:math' as math;

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/common.dart';
import 'package:flutter/foundation.dart';

@visibleForTesting
String? formatDelayTestProgress({
  required bool running,
  required int done,
  required int total,
}) {
  if (!running) {
    return null;
  }
  final safeTotal = total < 0 ? 0 : total;
  final totalText = '$safeTotal';
  final doneText = '$done'.padLeft(totalText.length);
  return '$doneText/$totalText';
}

String delayTestProgressMeasureText(int total) {
  final safeTotal = total < 0 ? 0 : total;
  final digitCount = math.max(3, '$safeTotal'.length);
  final digits = List.filled(digitCount, '0').join();
  return '$digits/$digits';
}

@visibleForTesting
({int done, int total}) aggregateDelayTestProgress({
  required int batchTotal,
  required int completedBeforeGroup,
  required int groupDone,
}) {
  final done = completedBeforeGroup + groupDone;
  return (done: done, total: math.max(batchTotal, done));
}

/// Global delay-test session: single-flight, generation-guarded.
/// UI listens with [ListenableBuilder] so only the progress chip rebuilds.
class DelayTestController extends ChangeNotifier {
  DelayTestController._();

  static final DelayTestController instance = DelayTestController._();

  int done = 0;
  int total = 0;
  bool running = false;

  String? get progressText =>
      formatDelayTestProgress(running: running, done: done, total: total);

  int _sessionGen = 0;
  DateTime? _lastProgressNotify;

  void _emit({bool force = false}) {
    if (!force && running) {
      final now = DateTime.now();
      if (_lastProgressNotify != null &&
          now.difference(_lastProgressNotify!) <
              const Duration(milliseconds: 80)) {
        return;
      }
      _lastProgressNotify = now;
    }
    notifyListeners();
  }

  /// Idle: always show 0/N for the nodes currently on screen.
  void syncIdleTotal({required bool isTab}) {
    if (running) {
      return;
    }
    final next = countDelayTestTargetsForCurrentScope(isTab: isTab);
    if (done == 0 && total == next) {
      return;
    }
    done = 0;
    total = next;
    _emit(force: true);
  }

  Future<void> runForCurrentScope({required bool isTab}) async {
    if (running || isDelayTestBusy) {
      return;
    }
    final session = ++_sessionGen;
    final gen = beginDelayTestBatch();
    running = true;
    done = 0;
    final batchTotal = countDelayTestTargetsForCurrentScope(isTab: isTab);
    total = batchTotal;
    _lastProgressNotify = null;
    _emit(force: true);

    void onProgress(int d, int t) {
      if (session != _sessionGen) {
        return;
      }
      done = d;
      total = t;
      _emit();
    }

    try {
      if (isTab) {
        final tab = globalState.container.read(proxiesTabStateProvider);
        final groups = tab.groups;
        if (groups.isEmpty) {
          return;
        }
        final name = tab.currentGroupName;
        final group = name == null
            ? groups.first
            : groups.firstWhere(
                (g) => g.name == name,
                orElse: () => groups.first,
              );
        await delayTest(
          group.all,
          testUrl: group.testUrl,
          generation: gen,
          isStale: () => session != _sessionGen,
          acquireGlobalLock: false,
          onProgress: onProgress,
        );
      } else {
        final query = globalState.container.read(
          queryProvider(QueryTag.proxies),
        );
        final groups = globalState.container
            .read(filterGroupsStateProvider(query))
            .value;
        var baseDone = 0;
        for (final group in groups) {
          if (session != _sessionGen) {
            return;
          }
          var groupTotal = 0;
          await delayTest(
            group.all,
            testUrl: group.testUrl,
            generation: gen,
            isStale: () => session != _sessionGen,
            acquireGlobalLock: false,
            onProgress: (d, t) {
              if (session != _sessionGen) {
                return;
              }
              if (t > groupTotal) {
                groupTotal = t;
              }
              final progress = aggregateDelayTestProgress(
                batchTotal: batchTotal,
                completedBeforeGroup: baseDone,
                groupDone: d,
              );
              onProgress(progress.done, progress.total);
            },
          );
          if (session != _sessionGen) {
            return;
          }
          baseDone += groupTotal;
          final progress = aggregateDelayTestProgress(
            batchTotal: batchTotal,
            completedBeforeGroup: baseDone,
            groupDone: 0,
          );
          onProgress(progress.done, progress.total);
        }
      }
    } finally {
      endDelayTestBatch(gen);
      if (session == _sessionGen) {
        running = false;
        done = 0;
        total = countDelayTestTargetsForCurrentScope(isTab: isTab);
        _emit(force: true);
      }
    }
  }

  void invalidate() {
    _sessionGen += 1;
    invalidateDelayTests();
    if (running) {
      running = false;
      done = 0;
      final style = globalState.container.read(proxiesStyleSettingProvider);
      total = countDelayTestTargetsForCurrentScope(
        isTab: style.type == ProxiesType.tab,
      );
      _emit(force: true);
    }
  }
}
