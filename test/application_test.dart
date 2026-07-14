import 'package:fl_clash/application.dart';
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application initialization awaits each phase in order', () async {
    final events = <String>[];

    await initializeApplicationAfterFrame(
      attach: () async => events.add('attach'),
      initializeLinks: () async => events.add('links'),
      initializeShortcuts: () async => events.add('shortcuts'),
    );

    expect(events, ['attach', 'links', 'shortcuts']);
  });

  test('application initialization stops after a phase failure', () async {
    final events = <String>[];

    await expectLater(
      initializeApplicationAfterFrame(
        attach: () async => events.add('attach'),
        initializeLinks: () => throw StateError('link failed'),
        initializeShortcuts: () async => events.add('shortcuts'),
      ),
      throwsStateError,
    );

    expect(events, ['attach']);
  });

  test(
    'newer connectivity update wins when an older update is slower',
    () async {
      final coordinator = ConnectivityUpdateCoordinator();
      final firstReady = Completer<void>();
      final secondReady = Completer<void>();
      final committed = <String>[];
      var checks = 0;

      final first = coordinator.update(
        results: const [ConnectivityResult.wifi],
        refreshLocalIp: (isCurrent) async {
          await firstReady.future;
          if (!isCurrent()) return false;
          committed.add('first');
          return true;
        },
        checkIp: () => checks++,
      );
      final second = coordinator.update(
        results: const [ConnectivityResult.wifi],
        refreshLocalIp: (isCurrent) async {
          await secondReady.future;
          if (!isCurrent()) return false;
          committed.add('second');
          return true;
        },
        checkIp: () => checks++,
      );

      secondReady.complete();
      await second;
      firstReady.complete();
      await first;

      expect(committed, ['second']);
      expect(checks, 1);
    },
  );

  test(
    'stale connectivity failure does not override a newer success',
    () async {
      final coordinator = ConnectivityUpdateCoordinator();
      final firstReady = Completer<void>();
      final committed = <String>[];

      final first = coordinator.update(
        results: const [ConnectivityResult.wifi],
        refreshLocalIp: (_) async {
          await firstReady.future;
          throw StateError('stale failure');
        },
        checkIp: () {},
      );
      await coordinator.update(
        results: const [ConnectivityResult.wifi],
        refreshLocalIp: (isCurrent) async {
          if (!isCurrent()) return false;
          committed.add('second');
          return true;
        },
        checkIp: () {},
      );

      firstReady.complete();
      await expectLater(first, completes);
      expect(committed, ['second']);
    },
  );

  test('stale completion cannot roll back rapid VPN state changes', () async {
    final coordinator = ConnectivityUpdateCoordinator();
    final staleReady = Completer<void>();
    var checks = 0;

    final stale = coordinator.update(
      results: const [ConnectivityResult.wifi],
      refreshLocalIp: (isCurrent) async {
        await staleReady.future;
        return isCurrent();
      },
      checkIp: () => checks++,
    );
    await coordinator.update(
      results: const [ConnectivityResult.vpn],
      refreshLocalIp: (isCurrent) async => isCurrent(),
      checkIp: () => checks++,
    );
    await coordinator.update(
      results: const [ConnectivityResult.wifi],
      refreshLocalIp: (isCurrent) async => isCurrent(),
      checkIp: () => checks++,
    );
    staleReady.complete();
    await stale;

    expect(coordinator.hasVpn, isFalse);
    expect(checks, 0);
  });
}
