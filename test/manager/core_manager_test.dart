import 'package:fl_clash/manager/core_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
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
