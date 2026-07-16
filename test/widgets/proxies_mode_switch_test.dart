import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
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

  @override
  Future<void> put(Profile profile) async {
    state = [
      for (final current in state)
        if (current.id == profile.id) profile else current,
    ];
  }

  void setCurrentGroup(int id, String groupName) {
    state = [
      for (final profile in state)
        if (profile.id == id)
          profile.copyWith(currentGroupName: groupName)
        else
          profile,
    ];
  }
}

void main() {
  testWidgets('proxy page survives rapid rule and global mode updates', (
    tester,
  ) async {
    final profile = Profile.normal(
      label: 'test',
    ).copyWith(currentGroupName: 'Rule group');
    final profiles = _TestProfiles([profile]);
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => profiles),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        viewSizeProvider.overrideWithBuild((_, _) => const Size(400, 800)),
        currentPageLabelProvider.overrideWithBuild((_, _) => PageLabel.proxies),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;

    List<Group> groups(int revision) => [
      Group(
        name: GroupName.GLOBAL.name,
        type: GroupType.Selector,
        now: 'global-$revision',
      ),
      Group(
        name: 'Rule group',
        type: GroupType.Selector,
        now: 'rule-$revision',
      ),
    ];

    container.read(groupsProvider.notifier).value = groups(0);
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
    await tester.pump();
    expect(tester.takeException(), isNull);

    final setup = container.read(setupActionProvider.notifier);
    for (var revision = 1; revision <= 6; revision++) {
      setup.changeMode(Mode.global);
      container.read(groupsProvider.notifier).value = groups(revision);
      profiles.setCurrentGroup(profile.id, GroupName.GLOBAL.name);
      setup.changeMode(Mode.rule);
      profiles.setCurrentGroup(profile.id, 'Rule group');
    }
    setup.changeMode(Mode.global);
    container.read(groupsProvider.notifier).value = groups(7);

    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(container.read(patchClashConfigProvider).mode, Mode.global);
    expect(find.byType(ProxiesView), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
  });
}
