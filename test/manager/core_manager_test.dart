import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/manager/core_manager.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
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

  test('only successful MMDB and ASN updates invalidate proxy geo', () {
    expect(
      invalidatesProxyGeoDatabase(GeoResource.MMDB, GeoUpdateNotice.updated),
      isTrue,
    );
    expect(
      invalidatesProxyGeoDatabase(GeoResource.ASN, GeoUpdateNotice.updated),
      isTrue,
    );
    expect(
      invalidatesProxyGeoDatabase(GeoResource.GEOIP, GeoUpdateNotice.updated),
      isFalse,
    );
    expect(
      invalidatesProxyGeoDatabase(GeoResource.MMDB, GeoUpdateNotice.skipped),
      isFalse,
    );
    expect(
      invalidatesProxyGeoDatabase(GeoResource.ASN, GeoUpdateNotice.error),
      isFalse,
    );
  });

  testWidgets('a delay burst refreshes runtime groups once', (tester) async {
    debouncer.cancel(FunctionTag.updateDelay);
    addTearDown(() => debouncer.cancel(FunctionTag.updateDelay));
    var refreshCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          proxyGroupsRefreshSchedulerProvider.overrideWithValue(
            () => refreshCalls++,
          ),
        ],
        child: const CoreManager(child: SizedBox()),
      ),
    );

    for (var index = 0; index < 4; index++) {
      await coreEventManager.sendEvent(
        CoreEvent(
          type: CoreEventType.delay,
          data: Delay(
            url: 'https://delay.example',
            name: 'node-$index',
            value: index + 1,
          ).toJson(),
        ),
      );
    }
    await tester.pump();
    await tester.pump(
      proxyGroupsRuntimeRefreshDebounce - const Duration(milliseconds: 1),
    );
    expect(refreshCalls, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(refreshCalls, 1);
  });

  testWidgets('provider sync sentinel refreshes all providers once', (
    tester,
  ) async {
    debouncer.cancel(FunctionTag.loadedProvider);
    addTearDown(() => debouncer.cancel(FunctionTag.loadedProvider));
    var syncCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          providersProvider.overrideWith(
            () => _CountingProviders(() => syncCalls++),
          ),
        ],
        child: const CoreManager(child: SizedBox()),
      ),
    );

    await coreEventManager.sendEvent(
      const CoreEvent(type: CoreEventType.loaded, data: providerSyncEventName),
    );
    await tester.pump();

    expect(syncCalls, 1);
    debouncer.cancel(FunctionTag.loadedProvider);
  });

  testWidgets('an external profile selection is applied exactly once', (
    tester,
  ) async {
    final first = Profile.normal(label: 'first');
    final second = Profile.normal(label: 'second');
    var applyCalls = 0;
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => first.id),
          profilesProvider.overrideWith(() => _TestProfiles([first, second])),
          profileSwitchApplierProvider.overrideWithValue(() async {
            applyCalls++;
          }),
          profileSwitchPersisterProvider.overrideWithValue(() async {}),
          profileRollbackFailureHandlerProvider.overrideWithValue(() async {}),
        ],
        child: CoreManager(
          child: Consumer(
            builder: (context, ref, child) {
              container = ProviderScope.containerOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    container.read(currentProfileIdProvider.notifier).value = second.id;
    await tester.pump();
    await tester.pump();

    expect(applyCalls, 1);
    expect(container.read(currentProfileIdProvider), second.id);
  });

  testWidgets('an explicit profile selection does not double apply', (
    tester,
  ) async {
    final first = Profile.normal(label: 'first');
    final second = Profile.normal(label: 'second');
    var applyCalls = 0;
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => first.id),
          profilesProvider.overrideWith(() => _TestProfiles([first, second])),
          profileSwitchApplierProvider.overrideWithValue(() async {
            applyCalls++;
          }),
          profileSwitchPersisterProvider.overrideWithValue(() async {}),
          profileRollbackFailureHandlerProvider.overrideWithValue(() async {}),
        ],
        child: CoreManager(
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(
      await container
          .read(profilesActionProvider.notifier)
          .selectProfile(second.id),
      isTrue,
    );
    await tester.pump();

    expect(applyCalls, 1);
    expect(container.read(currentProfileIdProvider), second.id);
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

class _TestProfiles extends Profiles {
  final List<Profile> initial;

  _TestProfiles(this.initial);

  @override
  List<Profile> build() => initial;
}

class _CountingProviders extends Providers {
  final VoidCallback onSync;

  _CountingProviders(this.onSync);

  @override
  List<ExternalProvider> build() => [];

  @override
  Future<void> syncProviders() async {
    onSync();
  }
}
