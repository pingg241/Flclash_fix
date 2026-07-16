import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/card.dart';
import 'package:fl_clash/views/proxies/common.dart';
import 'package:fl_clash/views/proxies/geo.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

const _groupName = 'Proxy group';

ProviderContainer _createContainer({
  required List<Proxy> proxies,
  required ProxiesData snapshot,
  required ProxyGeoState geoState,
  Profile? profile,
  RuntimeProxyChangeExecutor? runtimeChangeExecutor,
  ProxyChangeExecutor? legacyChangeExecutor,
  int? columns,
}) {
  final overrides = <Override>[
    runtimeProxiesProvider.overrideWithBuild((_, _) => snapshot),
    coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
    proxyGeoSessionActiveProvider.overrideWithValue(true),
    viewSizeProvider.overrideWithBuild((_, _) => const Size(320, 640)),
    selectedProxyNameProvider(_groupName).overrideWithValue(proxies.first.name),
  ];
  if (profile != null) {
    overrides.addAll([
      currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
      profilesProvider.overrideWith(() => _TestProfiles([profile])),
      proxyConnectionRefresherProvider.overrideWithValue(() async {}),
    ]);
  }
  if (runtimeChangeExecutor != null) {
    overrides.addAll([
      runtimeProxyChangeExecutorProvider.overrideWithValue(
        runtimeChangeExecutor,
      ),
      proxyExitGeoLoaderProvider.overrideWithValue(
        (params) async => ProxyExitGeo(
          generation: params.generation,
          requestId: params.requestId,
          leafId: params.memberId,
          ip: '198.51.100.1',
        ),
      ),
    ]);
  }
  if (legacyChangeExecutor != null) {
    overrides.add(
      proxyChangeExecutorProvider.overrideWithValue(legacyChangeExecutor),
    );
  }
  if (columns != null) {
    overrides.add(proxiesColumnsProvider.overrideWithValue(columns));
  }
  final delayNames = <String>{};
  final proxyDescriptions = <Proxy>{};
  for (final proxy in proxies) {
    if (proxyDescriptions.add(proxy)) {
      overrides.add(proxyDescProvider(proxy).overrideWithValue(proxy.type));
    }
    if (delayNames.add(proxy.name)) {
      overrides.add(
        delayProvider(
          proxyName: proxy.name,
          testUrl: null,
        ).overrideWithValue(90),
      );
    }
  }
  final container = ProviderContainer(overrides: overrides);
  container.read(proxyGeoDataSourceProvider.notifier).replace(geoState);
  return container;
}

Future<void> _pumpCards(
  WidgetTester tester, {
  required ProviderContainer container,
  required List<Proxy> proxies,
  Group? group,
  ProxyCardType cardType = ProxyCardType.expand,
  double textScale = 1,
  Size surfaceSize = const Size(320, 640),
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          );
        },
        home: Scaffold(
          body: Builder(
            builder: (context) {
              globalState.measure = Measure.of(context, textScale);
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < proxies.length; index++) ...[
                      if (index > 0) const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: getItemHeight(cardType),
                          child: ProxyCard(
                            key: ValueKey(
                              proxies[index].runtimeId.isNotEmpty
                                  ? proxies[index].runtimeId
                                  : '$_groupName.$index.${proxies[index].name}',
                            ),
                            proxy: proxies[index],
                            group:
                                group ??
                                Group(
                                  name: _groupName,
                                  type: GroupType.Selector,
                                  all: proxies,
                                ),
                            type: cardType,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

ProxyServerGeo _serverGeo(
  String memberId, {
  required String ip,
  required String countryCode,
  String asn = '',
  String aso = '',
  bool multiRegion = false,
  List<ProxyGeoAddress>? addresses,
}) {
  return ProxyServerGeo(
    memberId: memberId,
    source: 'dns',
    status: 'ok',
    multiRegion: multiRegion,
    addresses:
        addresses ??
        [ProxyGeoAddress(ip: ip, countryCode: countryCode, asn: asn, aso: aso)],
  );
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('countryCodeToFlag validates ISO-shaped input', () {
    expect(countryCodeToFlag('us'), '🇺🇸');
    expect(countryCodeToFlag('1A'), isEmpty);
    expect(countryCodeToFlag('USA'), isEmpty);
  });

  testWidgets('geo slots keep a stable height across async states', (
    tester,
  ) async {
    const proxy = Proxy(
      name: 'Stable node',
      type: 'Vless',
      runtimeId: 'leaf-stable',
      stableKey: 'stable-leaf',
    );
    const snapshot = ProxiesData(
      generation: 7,
      nodesById: {
        'leaf-stable': ProxyNodeSnapshot(
          id: 'leaf-stable',
          stableKey: 'stable-leaf',
          name: 'Stable node',
          type: 'Vless',
        ),
      },
    );
    final container = _createContainer(
      proxies: const [proxy],
      snapshot: snapshot,
      geoState: const ProxyGeoState(
        generation: 7,
        serverLoadingMemberIds: {'leaf-stable'},
        exitLoadingMemberIds: {'leaf-stable'},
        activeExitLeafId: 'leaf-stable',
      ),
    );
    addTearDown(container.dispose);
    globalState.container = container;

    await _pumpCards(tester, container: container, proxies: const [proxy]);
    final initialSectionHeight = tester
        .getSize(find.byType(ProxyGeoSection))
        .height;
    final initialCardHeight = tester.getSize(find.byType(ProxyCard)).height;
    expect(initialSectionHeight, proxyGeoLineHeight * 2 + 4);
    expect(initialCardHeight, getItemHeight(ProxyCardType.expand));
    expect(tester.takeException(), isNull);

    container
        .read(proxyGeoDataSourceProvider.notifier)
        .replace(
          ProxyGeoState(
            generation: 7,
            activeExitLeafId: 'leaf-stable',
            serverByMemberId: {
              'leaf-stable': _serverGeo(
                'leaf-stable',
                ip: '2001:db8:1234:5678:90ab:cdef:1234:5678',
                countryCode: 'US',
              ),
            },
            exitByMemberId: const {
              'leaf-stable': ProxyExitGeo(
                generation: 7,
                leafId: 'leaf-stable',
                ip: '2606:4700:4700::1111',
                countryCode: 'JP',
                stale: true,
                cached: true,
              ),
            },
            staleExitMemberIds: const {'leaf-stable'},
          ),
        );
    await tester.pump();

    expect(
      tester.getSize(find.byType(ProxyGeoSection)).height,
      initialSectionHeight,
    );
    expect(tester.getSize(find.byType(ProxyCard)).height, initialCardHeight);
    expect(find.text('US'), findsOneWidget);
    expect(find.text('JP'), findsOneWidget);
    expect(find.text('2606:4700:4700::1111'), findsOneWidget);
    expect(tester.takeException(), isNull);

    container
        .read(proxyGeoDataSourceProvider.notifier)
        .replace(
          const ProxyGeoState(
            generation: 7,
            activeExitLeafId: 'leaf-stable',
            serverErrorsByMemberId: {'leaf-stable': 'resolve failed'},
            exitErrorsByMemberId: {'leaf-stable': 'probe failed'},
          ),
        );
    await tester.pump();

    expect(
      tester.getSize(find.byType(ProxyGeoSection)).height,
      initialSectionHeight,
    );
    expect(tester.getSize(find.byType(ProxyCard)).height, initialCardHeight);
    expect(find.text('Location unavailable'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicate names keep runtime identity and geo separate', (
    tester,
  ) async {
    const first = Proxy(
      name: 'Same name',
      type: 'Vless',
      runtimeId: 'leaf-us',
      stableKey: 'stable-us',
    );
    const second = Proxy(
      name: 'Same name',
      type: 'Vless',
      runtimeId: 'leaf-jp',
      stableKey: 'stable-jp',
    );
    const snapshot = ProxiesData(
      generation: 3,
      groups: [
        ProxyGroupSnapshot(
          id: 'runtime-group',
          name: _groupName,
          type: 'Selector',
          nowId: 'leaf-jp',
          memberIds: ['leaf-us', 'leaf-jp'],
        ),
      ],
      nodesById: {
        'runtime-group': ProxyNodeSnapshot(
          id: 'runtime-group',
          stableKey: 'runtime-group-key',
          name: _groupName,
          type: 'Selector',
        ),
        'leaf-us': ProxyNodeSnapshot(
          id: 'leaf-us',
          stableKey: 'stable-us',
          name: 'Same name',
          type: 'Vless',
        ),
        'leaf-jp': ProxyNodeSnapshot(
          id: 'leaf-jp',
          stableKey: 'stable-jp',
          name: 'Same name',
          type: 'Vless',
        ),
      },
    );
    final container = _createContainer(
      proxies: const [first, second],
      snapshot: snapshot,
      geoState: ProxyGeoState(
        generation: 3,
        serverByMemberId: {
          'leaf-us': _serverGeo('leaf-us', ip: '104.16.1.1', countryCode: 'US'),
          'leaf-jp': _serverGeo(
            'leaf-jp',
            ip: '203.0.113.8',
            countryCode: 'JP',
          ),
        },
      ),
    );
    addTearDown(container.dispose);
    globalState.container = container;

    await _pumpCards(
      tester,
      container: container,
      proxies: const [first, second],
      group: const Group(
        name: _groupName,
        type: GroupType.Selector,
        runtimeId: 'runtime-group',
        stableKey: 'runtime-group-key',
        nowId: 'leaf-jp',
        now: 'Same name',
        all: [first, second],
      ),
      textScale: 1.3,
    );

    expect(find.byType(ProxyCard), findsNWidgets(2));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is EmojiText && widget.text == 'Same name',
      ),
      findsNWidgets(2),
    );
    expect(find.text('US'), findsOneWidget);
    expect(find.text('JP'), findsOneWidget);
    final cards = tester
        .widgetList<CommonCard>(find.byType(CommonCard))
        .toList();
    expect(cards.where((card) => card.isSelected), hasLength(1));
    expect(cards.first.isSelected, isFalse);
    expect(cards.last.isSelected, isTrue);
    expect(find.textContaining('Same name US'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy duplicate names never select or submit by name', (
    tester,
  ) async {
    const first = Proxy(name: 'Same name', type: 'Vless');
    const second = Proxy(name: 'Same name', type: 'Vless');
    const group = Group(
      name: _groupName,
      type: GroupType.Selector,
      all: [first, second],
    );
    var calls = 0;
    final container = _createContainer(
      proxies: const [first, second],
      snapshot: const ProxiesData(),
      geoState: const ProxyGeoState(),
      legacyChangeExecutor: (_, _) async {
        calls++;
        return '';
      },
    );
    addTearDown(container.dispose);
    globalState.container = container;

    await _pumpCards(
      tester,
      container: container,
      proxies: const [first, second],
      group: group,
    );

    final cards = tester
        .widgetList<CommonCard>(find.byType(CommonCard))
        .toList();
    expect(cards.where((card) => card.isSelected), isEmpty);
    await tester.tap(find.byType(ProxyCard).last);
    await tester.pump(const Duration(milliseconds: 650));
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicate name click submits exact runtime IDs and generation', (
    tester,
  ) async {
    addTearDown(() => debouncer.cancel(FunctionTag.updateGroups));
    const first = Proxy(
      name: 'Same name',
      type: 'Vless',
      runtimeId: 'leaf-us',
      stableKey: 'stable-us',
    );
    const second = Proxy(
      name: 'Same name',
      type: 'Vless',
      runtimeId: 'leaf-jp',
      stableKey: 'stable-jp',
    );
    const group = Group(
      name: _groupName,
      type: GroupType.Selector,
      runtimeId: 'runtime-group',
      stableKey: 'runtime-group-key',
      nowId: 'leaf-us',
      now: 'Same name',
      all: [first, second],
    );
    const snapshot = ProxiesData(
      generation: 17,
      groups: [
        ProxyGroupSnapshot(
          id: 'runtime-group',
          name: _groupName,
          type: 'Selector',
          nowId: 'leaf-us',
          memberIds: ['leaf-us', 'leaf-jp'],
        ),
      ],
      nodesById: {
        'runtime-group': ProxyNodeSnapshot(
          id: 'runtime-group',
          stableKey: 'runtime-group-key',
          name: _groupName,
          type: 'Selector',
        ),
        'leaf-us': ProxyNodeSnapshot(
          id: 'leaf-us',
          stableKey: 'stable-us',
          name: 'Same name',
          type: 'Vless',
        ),
        'leaf-jp': ProxyNodeSnapshot(
          id: 'leaf-jp',
          stableKey: 'stable-jp',
          name: 'Same name',
          type: 'Vless',
        ),
      },
    );
    final profile = Profile.normal(label: 'profile');
    ChangeProxyParams? invoked;
    final container = _createContainer(
      proxies: const [first, second],
      snapshot: snapshot,
      geoState: const ProxyGeoState(generation: 17),
      profile: profile,
      columns: 1,
      runtimeChangeExecutor: (params) async {
        invoked = params;
        return '';
      },
    );
    addTearDown(container.dispose);
    globalState.container = container;

    await _pumpCards(
      tester,
      container: container,
      proxies: const [first, second],
      group: group,
    );
    await tester.tap(find.byType(ProxyCard).last);
    await tester.pump(const Duration(milliseconds: 650));

    expect(
      invoked,
      const ChangeProxyParams(
        groupId: 'runtime-group',
        memberId: 'leaf-jp',
        generation: 17,
      ),
    );
    final cards = tester
        .widgetList<CommonCard>(find.byType(CommonCard))
        .toList();
    expect(cards.where((card) => card.isSelected), hasLength(1));
    expect(cards.first.isSelected, isFalse);
    expect(cards.last.isSelected, isTrue);
    expect(
      getScrollToSelectedOffset(group: group, proxies: const [first, second]),
      getItemHeight(ProxyCardType.expand) + 8,
    );
    debouncer.cancel(FunctionTag.updateGroups);
  });

  testWidgets('an old-generation tap cannot fake or overwrite selection', (
    tester,
  ) async {
    const first = Proxy(
      name: 'Same name',
      type: 'Vless',
      runtimeId: 'leaf-us',
      stableKey: 'stable-us',
    );
    const second = Proxy(
      name: 'Same name',
      type: 'Vless',
      runtimeId: 'leaf-jp',
      stableKey: 'stable-jp',
    );
    const group = Group(
      name: _groupName,
      type: GroupType.Selector,
      runtimeId: 'runtime-group',
      stableKey: 'runtime-group-key',
      nowId: 'leaf-us',
      now: 'Same name',
      all: [first, second],
    );
    const snapshot = ProxiesData(
      generation: 21,
      groups: [
        ProxyGroupSnapshot(
          id: 'runtime-group',
          name: _groupName,
          type: 'Selector',
          nowId: 'leaf-us',
          memberIds: ['leaf-us', 'leaf-jp'],
        ),
      ],
      nodesById: {
        'runtime-group': ProxyNodeSnapshot(
          id: 'runtime-group',
          stableKey: 'runtime-group-key',
          name: _groupName,
          type: 'Selector',
        ),
        'leaf-us': ProxyNodeSnapshot(
          id: 'leaf-us',
          stableKey: 'stable-us',
          name: 'Same name',
          type: 'Vless',
        ),
        'leaf-jp': ProxyNodeSnapshot(
          id: 'leaf-jp',
          stableKey: 'stable-jp',
          name: 'Same name',
          type: 'Vless',
        ),
      },
    );
    final profile = Profile.normal(label: 'profile');
    var calls = 0;
    final container = _createContainer(
      proxies: const [first, second],
      snapshot: snapshot,
      geoState: const ProxyGeoState(generation: 21),
      profile: profile,
      runtimeChangeExecutor: (_) async {
        calls++;
        return '';
      },
    );
    addTearDown(container.dispose);
    globalState.container = container;

    await _pumpCards(
      tester,
      container: container,
      proxies: const [first, second],
      group: group,
    );
    await tester.tap(find.byType(ProxyCard).last);
    container.read(runtimeProxiesProvider.notifier).value = snapshot.copyWith(
      generation: 22,
    );
    await tester.pump();

    var cards = tester.widgetList<CommonCard>(find.byType(CommonCard)).toList();
    expect(cards.where((card) => card.isSelected), hasLength(1));
    expect(cards.first.isSelected, isTrue);
    expect(cards.last.isSelected, isFalse);
    await tester.pump(const Duration(milliseconds: 650));

    expect(calls, 0);
    expect(container.read(runtimeProxiesProvider).generation, 22);
    expect(
      container.read(runtimeProxiesProvider).groupById('runtime-group')?.nowId,
      'leaf-us',
    );
    expect(
      container.read(profilesProvider).single.selectedMap[_groupName],
      isNull,
    );
    cards = tester.widgetList<CommonCard>(find.byType(CommonCard)).toList();
    expect(cards.where((card) => card.isSelected), hasLength(1));
    expect(cards.first.isSelected, isTrue);
    expect(cards.last.isSelected, isFalse);
  });

  testWidgets('group cards show current leaf server and never exit geo', (
    tester,
  ) async {
    const validGroup = Proxy(
      name: 'Automatic',
      type: 'URLTest',
      runtimeId: 'group-valid',
      stableKey: 'group-valid',
    );
    const cyclicGroup = Proxy(
      name: 'Cyclic',
      type: 'Selector',
      runtimeId: 'group-cycle',
      stableKey: 'group-cycle',
    );
    const snapshot = ProxiesData(
      generation: 11,
      groups: [
        ProxyGroupSnapshot(
          id: 'group-valid',
          name: 'Automatic',
          type: 'URLTest',
          nowId: 'leaf-current',
          memberIds: ['leaf-current'],
        ),
        ProxyGroupSnapshot(
          id: 'group-cycle',
          name: 'Cyclic',
          type: 'Selector',
          nowId: 'group-cycle',
          memberIds: ['group-cycle'],
        ),
      ],
      nodesById: {
        'leaf-current': ProxyNodeSnapshot(
          id: 'leaf-current',
          stableKey: 'leaf-current',
          name: 'Current leaf',
          type: 'Vless',
        ),
        'group-cycle': ProxyNodeSnapshot(
          id: 'group-cycle',
          stableKey: 'group-cycle',
          name: 'Cyclic',
          type: 'Selector',
        ),
      },
    );
    final container = _createContainer(
      proxies: const [validGroup, cyclicGroup],
      snapshot: snapshot,
      geoState: ProxyGeoState(
        generation: 11,
        activeExitLeafId: 'leaf-current',
        serverByMemberId: {
          'leaf-current': _serverGeo(
            'leaf-current',
            ip: '198.51.100.2',
            countryCode: 'DE',
          ),
        },
        exitByMemberId: const {
          'leaf-current': ProxyExitGeo(
            generation: 11,
            leafId: 'leaf-current',
            ip: '192.0.2.44',
            countryCode: 'CA',
          ),
        },
      ),
    );
    addTearDown(container.dispose);
    globalState.container = container;

    await _pumpCards(
      tester,
      container: container,
      proxies: const [validGroup, cyclicGroup],
    );

    expect(find.text('Dynamic · Current leaf'), findsOneWidget);
    expect(find.text('Dynamic · Unknown'), findsOneWidget);
    expect(find.text('DE'), findsOneWidget);
    expect(find.text('198.51.100.2'), findsOneWidget);
    expect(find.text('CA'), findsNothing);
    expect(find.text('192.0.2.44'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all card types fit two 320px columns at large text scale', (
    tester,
  ) async {
    const first = Proxy(
      name: 'A very long node name that must stay independent',
      type: 'Shadowsocks2022',
      runtimeId: 'leaf-long-a',
      stableKey: 'leaf-long-a',
    );
    const second = Proxy(
      name: 'Another very long node name',
      type: 'Hysteria2',
      runtimeId: 'leaf-long-b',
      stableKey: 'leaf-long-b',
    );
    const snapshot = ProxiesData(
      generation: 9,
      nodesById: {
        'leaf-long-a': ProxyNodeSnapshot(
          id: 'leaf-long-a',
          stableKey: 'leaf-long-a',
          name: 'A very long node name that must stay independent',
          type: 'Shadowsocks2022',
        ),
        'leaf-long-b': ProxyNodeSnapshot(
          id: 'leaf-long-b',
          stableKey: 'leaf-long-b',
          name: 'Another very long node name',
          type: 'Hysteria2',
        ),
      },
    );
    final container = _createContainer(
      proxies: const [first, second],
      snapshot: snapshot,
      geoState: ProxyGeoState(
        generation: 9,
        serverByMemberId: {
          'leaf-long-a': _serverGeo(
            'leaf-long-a',
            ip: '2001:db8:1234:5678:90ab:cdef:1234:5678',
            countryCode: 'US',
            multiRegion: true,
          ),
          'leaf-long-b': _serverGeo(
            'leaf-long-b',
            ip: '2001:db8:ffff:eeee:dddd:cccc:bbbb:aaaa',
            countryCode: 'JP',
          ),
        },
      ),
    );
    addTearDown(container.dispose);
    globalState.container = container;

    for (final width in [320.0, 360.0]) {
      for (final cardType in ProxyCardType.values) {
        await _pumpCards(
          tester,
          container: container,
          proxies: const [first, second],
          cardType: cardType,
          textScale: 2,
          surfaceSize: Size(width, 640),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '$width ${cardType.name}',
        );
        expect(
          tester.getSize(find.byType(ProxyCard).first).height,
          getItemHeight(cardType),
        );
      }
    }
  });

  testWidgets('details keep full IPv6 ASN ASO and every server address', (
    tester,
  ) async {
    const proxy = Proxy(
      name: '1',
      type: 'Vless',
      runtimeId: 'leaf-detail',
      stableKey: 'leaf-detail',
    );
    const snapshot = ProxiesData(
      generation: 5,
      nodesById: {
        'leaf-detail': ProxyNodeSnapshot(
          id: 'leaf-detail',
          stableKey: 'leaf-detail',
          name: '1',
          type: 'Vless',
        ),
      },
    );
    final container = _createContainer(
      proxies: const [proxy],
      snapshot: snapshot,
      geoState: ProxyGeoState(
        generation: 5,
        activeExitLeafId: 'leaf-detail',
        serverByMemberId: {
          'leaf-detail': _serverGeo(
            'leaf-detail',
            ip: '203.0.113.1',
            countryCode: 'US',
            addresses: const [
              ProxyGeoAddress(
                ip: '203.0.113.1',
                countryCode: 'US',
                asn: '64500',
                aso: 'Example Network',
              ),
              ProxyGeoAddress(
                ip: '2001:db8:1234:5678:90ab:cdef:1234:5678',
                countryCode: 'JP',
                asn: '64501',
                aso: 'Example IPv6 Network',
              ),
            ],
          ),
        },
        exitByMemberId: const {
          'leaf-detail': ProxyExitGeo(
            generation: 5,
            leafId: 'leaf-detail',
            ip: '2606:4700:4700::1111',
            countryCode: 'CA',
            asn: '13335',
            aso: 'Cloudflare',
            cached: true,
            routeSample: true,
          ),
        },
      ),
    );
    addTearDown(container.dispose);
    globalState.container = container;

    const titleCases = [
      (locale: Locale('en'), title: 'Details', combined: '1 details'),
      (locale: Locale('zh', 'CN'), title: '详情', combined: '1详情'),
      (locale: Locale('ja'), title: '詳細', combined: '1詳細'),
      (locale: Locale('ru'), title: 'Детали', combined: 'Детали 1'),
    ];
    for (var index = 0; index < titleCases.length; index++) {
      final titleCase = titleCases[index];
      await _pumpCards(
        tester,
        container: container,
        proxies: const [proxy],
        locale: titleCase.locale,
      );
      await tester.longPress(find.byType(CommonCard));
      await tester.pumpAndSettle();

      final sheet = find.byType(AdaptiveSheetScaffold);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.text(titleCase.title)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sheet,
          matching: find.byWidgetPredicate(
            (widget) => widget is EmojiText && widget.text == '1',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(titleCase.combined), findsNothing);
      if (index < titleCases.length - 1) {
        await Navigator.of(tester.element(sheet)).maybePop();
        await tester.pumpAndSettle();
      }
    }

    expect(find.text('2001:db8:1234:5678:90ab:cdef:1234:5678'), findsOneWidget);
    expect(find.text('AS64500'), findsOneWidget);
    expect(find.text('Example IPv6 Network'), findsOneWidget);
    expect(find.text('2606:4700:4700::1111'), findsNWidgets(2));
    expect(find.text('AS13335'), findsOneWidget);
    expect(find.text('Cloudflare'), findsOneWidget);
    expect(find.byIcon(Icons.copy_outlined), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}

class _TestProfiles extends Profiles {
  final List<Profile> initial;

  _TestProfiles(this.initial);

  @override
  List<Profile> build() => initial;

  @override
  Future<void> put(Profile profile) async {
    final next = List<Profile>.from(state);
    final index = next.indexWhere((item) => item.id == profile.id);
    if (index == -1) {
      next.add(profile);
    } else {
      next[index] = profile;
    }
    state = next;
  }
}
