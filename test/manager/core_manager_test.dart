import 'dart:async';

import 'package:fl_clash/manager/core_manager.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('geo update notice gives errors precedence over success', () {
    expect(
      resolveGeoUpdateNotice(
        updating: false,
        skipped: false,
        error: 'download failed',
      ),
      GeoUpdateNotice.error,
    );
    expect(
      resolveGeoUpdateNotice(updating: true, skipped: false, error: null),
      GeoUpdateNotice.updating,
    );
    expect(
      resolveGeoUpdateNotice(updating: false, skipped: true, error: null),
      GeoUpdateNotice.skipped,
    );
    expect(
      resolveGeoUpdateNotice(updating: false, skipped: false, error: null),
      GeoUpdateNotice.updated,
    );
  });

  test(
    'failed profile setup restores and reapplies the previous profile',
    () async {
      var current = 2;
      final events = <String>[];
      final errors = <ProfileSwitchException>[];

      await performProfileSwitchTransaction(
        isCurrent: () => current == 2,
        applyNext: () => throw StateError('broken profile'),
        restorePreviousId: () async {
          current = 1;
          events.add('restore-id');
        },
        persistPreviousId: () async => events.add('persist-id'),
        applyPrevious: () async => events.add('apply-previous'),
        markRollbackFailure: () async => events.add('mark-failed'),
        reportError: (error, _) => errors.add(error),
      );

      expect(current, 1);
      expect(events, ['restore-id', 'persist-id', 'apply-previous']);
      expect(errors, hasLength(1));
      expect(errors.single.rollbackErrors, isEmpty);
    },
  );

  test('an old successful switch cannot overwrite a newer profile', () async {
    var generation = 1;
    var current = 2;
    final oldSetupStarted = Completer<void>();
    final releaseOldSetup = Completer<void>();
    final events = <String>[];

    final oldSwitch = performProfileSwitchTransaction(
      isCurrent: () => generation == 1 && current == 2,
      applyNext: () async {
        oldSetupStarted.complete();
        await releaseOldSetup.future;
        events.add('old-success');
      },
      restorePreviousId: () async => events.add('old-restore'),
      persistPreviousId: () async {},
      applyPrevious: () async {},
      markRollbackFailure: () async {},
      reportError: (_, _) => events.add('old-error'),
    );
    await oldSetupStarted.future;

    generation = 2;
    current = 3;
    await performProfileSwitchTransaction(
      isCurrent: () => generation == 2 && current == 3,
      applyNext: () async => events.add('new-success'),
      restorePreviousId: () async => current = 2,
      persistPreviousId: () async {},
      applyPrevious: () async {},
      markRollbackFailure: () async {},
      reportError: (_, _) => events.add('new-error'),
    );
    releaseOldSetup.complete();
    await oldSwitch;

    expect(current, 3);
    expect(events, ['new-success', 'old-success']);
  });

  test('an old failure does not roll back a newer successful switch', () async {
    var generation = 1;
    var current = 2;
    final oldSetupStarted = Completer<void>();
    final releaseOldSetup = Completer<void>();
    final events = <String>[];

    final oldSwitch = performProfileSwitchTransaction(
      isCurrent: () => generation == 1 && current == 2,
      applyNext: () async {
        oldSetupStarted.complete();
        await releaseOldSetup.future;
        throw StateError('old failure');
      },
      restorePreviousId: () async {
        current = 1;
        events.add('old-restore');
      },
      persistPreviousId: () async {},
      applyPrevious: () async {},
      markRollbackFailure: () async {},
      reportError: (_, _) => events.add('old-error'),
    );
    await oldSetupStarted.future;

    generation = 2;
    current = 3;
    await performProfileSwitchTransaction(
      isCurrent: () => generation == 2 && current == 3,
      applyNext: () async => events.add('new-success'),
      restorePreviousId: () async => current = 2,
      persistPreviousId: () async {},
      applyPrevious: () async {},
      markRollbackFailure: () async {},
      reportError: (_, _) => events.add('new-error'),
    );
    releaseOldSetup.complete();
    await oldSwitch;

    expect(current, 3);
    expect(events, ['new-success']);
  });

  test(
    'rollback setup failure is reported and marks the session failed',
    () async {
      final errors = <ProfileSwitchException>[];
      var markedFailed = false;

      await performProfileSwitchTransaction(
        isCurrent: () => true,
        applyNext: () => throw StateError('new setup failed'),
        restorePreviousId: () async {},
        persistPreviousId: () async {},
        applyPrevious: () => throw StateError('rollback setup failed'),
        markRollbackFailure: () async {
          markedFailed = true;
        },
        reportError: (error, _) => errors.add(error),
      );

      expect(markedFailed, isTrue);
      expect(errors, hasLength(1));
      expect(errors.single.rollbackErrors, hasLength(1));
      expect(errors.single.toString(), contains('rollback setup failed'));
    },
  );

  test('reported profile errors do not escape as unhandled futures', () async {
    var reported = false;

    await expectLater(
      performProfileSwitchTransaction(
        isCurrent: () => true,
        applyNext: () => throw StateError('setup failed'),
        restorePreviousId: () async {},
        persistPreviousId: () async {},
        applyPrevious: () async {},
        markRollbackFailure: () async {},
        reportError: (_, _) => reported = true,
      ),
      completes,
    );
    expect(reported, isTrue);
  });

  testWidgets('pending profile callback is ignored after dispose', (
    tester,
  ) async {
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const CoreManager(child: SizedBox());
          },
        ),
      ),
    );

    container.read(currentProfileIdProvider.notifier).value = 1;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
