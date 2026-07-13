import 'package:fl_clash/features/overwrite/rule.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/profiles/overwrite/custom/rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('rule parameter switches update their matching fields', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [ruleProvider.overrideWithBuild((_, _) => Rule.init())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                RuleParameterSwitch(parameter: RuleParameter.noResolve),
                RuleParameterSwitch(parameter: RuleParameter.src),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch).at(0));
    await tester.pump();
    expect(container.read(ruleProvider).noResolve, isTrue);
    expect(container.read(ruleProvider).src, isFalse);

    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();
    expect(container.read(ruleProvider).noResolve, isTrue);
    expect(container.read(ruleProvider).src, isTrue);
  });

  testWidgets('unknown explicit rules are read-only in the rule dialog', (
    tester,
  ) async {
    const value = 'FUTURE-RULE,payload,DIRECT,option';

    await tester.pumpWidget(
      _testApp(AddOrEditRuleDialog(rule: Rule.parse(value, id: 1))),
    );

    expect(find.text(value), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });
}

Widget _testApp(Widget child) {
  return ProviderScope(
    overrides: [
      viewSizeProvider.overrideWithBuild((_, _) => const Size(1200, 1000)),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}
