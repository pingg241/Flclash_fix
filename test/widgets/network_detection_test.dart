import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/widgets/network_detection.dart'
    as dashboard;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a compact refresh indicator with a cached IP', (
    tester,
  ) async {
    const ipInfo = IpInfo(ip: '1.1.1.1', countryCode: 'US');

    await tester.pumpWidget(
      const _TestApp(
        state: NetworkDetectionState(isLoading: true, ipInfo: ipInfo),
      ),
    );
    await tester.pump();

    expect(find.text(ipInfo.ip), findsOneWidget);
    expect(
      find.byKey(const ValueKey('network-detection-refreshing')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      const _TestApp(
        state: NetworkDetectionState(isLoading: false, ipInfo: ipInfo),
      ),
    );
    await tester.pump();

    expect(find.text(ipInfo.ip), findsOneWidget);
    expect(
      find.byKey(const ValueKey('network-detection-refreshing')),
      findsNothing,
    );
  });
}

class _TestApp extends StatelessWidget {
  final NetworkDetectionState state;

  const _TestApp({required this.state});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      key: ValueKey(state.isLoading),
      overrides: [networkDetectionProvider.overrideWithBuild((_, _) => state)],
      child: MaterialApp(
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
        home: const Scaffold(body: dashboard.NetworkDetection()),
      ),
    );
  }
}
