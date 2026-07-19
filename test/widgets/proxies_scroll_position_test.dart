import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/card.dart';
import 'package:fl_clash/views/proxies/proxies.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestProfiles extends Profiles {
  _TestProfiles(this.initial);

  final List<Profile> initial;

  @override
  List<Profile> build() => initial;
}

void main() {
  testWidgets(
    'proxy refreshes and a failed group refresh preserve tab offset',
    (tester) async {
      final proxies = List.generate(
        30,
        (index) => Proxy(
          name: 'Node $index',
          type: 'Vless',
          runtimeId: 'node-$index',
          stableKey: 'node-$index',
        ),
      );
      final group = Group(
        name: 'Group',
        type: GroupType.Selector,
        runtimeId: 'group',
        stableKey: 'group',
        hidden: false,
        all: proxies,
      );
      final profile = Profile.normal(
        label: 'profile',
      ).copyWith(currentGroupName: group.name);
      final profiles = _TestProfiles([profile]);
      final container = ProviderContainer(
        overrides: [
          profilesProvider.overrideWith(() => profiles),
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          viewSizeProvider.overrideWithBuild((_, _) => const Size(400, 800)),
          currentPageLabelProvider.overrideWithBuild(
            (_, _) => PageLabel.proxies,
          ),
          proxiesSnapshotLoaderProvider.overrideWithValue(
            () async => throw StateError('temporary IPC failure'),
          ),
        ],
      );
      addTearDown(container.dispose);
      globalState.container = container;
      container.read(groupsProvider.notifier).value = [group];

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.delegate.supportedLocales,
            home: Builder(
              builder: (context) {
                globalState.measure = Measure.of(context, 1);
                return const ProxiesView();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gridFinder = find.byType(GridView);
      expect(gridFinder, findsOneWidget);
      await tester.drag(gridFinder, const Offset(0, -1200));
      await tester.pumpAndSettle();
      final controller = tester.widget<GridView>(gridFinder).controller!;
      final offset = controller.offset;
      expect(offset, greaterThan(0));
      final gridRect = tester.getRect(gridFinder);
      final visibleBefore = tester
          .widgetList<ProxyCard>(find.byType(ProxyCard))
          .where((card) {
            final rect = tester.getRect(find.byWidget(card));
            return rect.bottom > gridRect.top && rect.top < gridRect.bottom;
          })
          .map((card) => card.proxy.name)
          .toSet();
      expect(visibleBefore, isNotEmpty);

      container.read(delayDataSourceProvider.notifier).value = {
        defaultTestUrl: {'Node 10': 42},
      };
      container
          .read(trafficsProvider.notifier)
          .addTraffic(const Traffic(up: 1));
      container.read(providersProvider.notifier).value = [
        ExternalProvider(
          name: 'provider',
          type: 'Proxy',
          vehicleType: 'HTTP',
          count: proxies.length,
          updateAt: DateTime.now(),
        ),
      ];
      container
          .read(proxyGeoDataSourceProvider.notifier)
          .replace(const ProxyGeoState(generation: 1));
      container.read(groupsProvider.notifier).value = [
        group.copyWith(now: 'Node 1'),
      ];
      await tester.pump();

      expect(controller.offset, closeTo(offset, 0.1));

      await container.read(proxiesActionProvider.notifier).updateGroups();
      await tester.pump();
      container.read(groupsProvider.notifier).value = [group];
      await tester.pumpAndSettle();

      final refreshedController = tester
          .widget<GridView>(gridFinder)
          .controller!;
      expect(refreshedController.offset, closeTo(offset, 0.1));
      final visibleAfter = tester
          .widgetList<ProxyCard>(find.byType(ProxyCard))
          .where((card) {
            final rect = tester.getRect(find.byWidget(card));
            return rect.bottom > gridRect.top && rect.top < gridRect.bottom;
          })
          .map((card) => card.proxy.name)
          .toSet();
      expect(visibleAfter, containsAll(visibleBefore));
      expect(tester.takeException(), isNull);
    },
  );
}
