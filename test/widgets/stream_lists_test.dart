import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/connection/item.dart';
import 'package:fl_clash/views/connection/requests.dart';
import 'package:fl_clash/views/logs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('logs build only visible items for a full history', (
    tester,
  ) async {
    final logs = List.generate(
      maxLength,
      (index) => Log(payload: 'log $index', dateTime: 'same-second'),
    );
    final history = FixedList<Log>(maxLength, list: logs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [logsProvider.overrideWithBuild((_, _) => history)],
        child: const _TestApp(child: LogsView()),
      ),
    );
    await tester.pump();

    final builtItems = find.byType(LogItem).evaluate().length;
    expect(builtItems, greaterThan(0));
    expect(builtItems, lessThan(100));
  });

  testWidgets('logs with the same timestamp keep distinct stable keys', (
    tester,
  ) async {
    final logs = [
      const Log(payload: 'duplicate', dateTime: 'same-second'),
      const Log(payload: 'duplicate', dateTime: 'same-second'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          logsProvider.overrideWithBuild(
            (_, _) => FixedList<Log>(maxLength, list: logs),
          ),
        ],
        child: const _TestApp(child: LogsView()),
      ),
    );
    await tester.pump();

    final keys = tester
        .widgetList<LogItem>(find.byType(LogItem))
        .map((item) => item.key)
        .toList();
    expect(keys, hasLength(2));
    expect(keys, everyElement(isA<LocalKey>()));
    expect(keys.toSet(), hasLength(2));
  });

  testWidgets('requests build only visible items for a full history', (
    tester,
  ) async {
    final requests = List.generate(
      maxLength,
      (index) => TrackerInfo(
        id: '$index',
        start: DateTime(2026),
        metadata: const Metadata(
          network: 'tcp',
          destinationIP: '127.0.0.1',
          destinationPort: '443',
        ),
        chains: const ['DIRECT'],
        rule: 'MATCH',
        rulePayload: '',
      ),
    );
    final history = FixedList<TrackerInfo>(maxLength, list: requests);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [requestsProvider.overrideWithBuild((_, _) => history)],
        child: const _TestApp(child: RequestsView()),
      ),
    );
    await tester.pump();

    final builtItems = find.byType(TrackerInfoItem).evaluate().length;
    expect(builtItems, greaterThan(0));
    expect(builtItems, lessThan(100));
  });
}

class _TestApp extends StatelessWidget {
  final Widget child;

  const _TestApp({required this.child});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: globalState.navigatorKey,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      builder: (context, child) {
        globalState.theme = CommonTheme.of(context, 1);
        globalState.measure = Measure.of(context, 1);
        return child!;
      },
      home: child,
    );
  }
}
