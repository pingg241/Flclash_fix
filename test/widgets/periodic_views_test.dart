import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/connection/connections.dart';
import 'package:fl_clash/views/dashboard/widgets/memory_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) {
  return MaterialApp(
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
        globalState.theme = CommonTheme.of(context, 1);
        return child;
      },
    ),
  );
}

void main() {
  testWidgets('memory polling recovers and stops after dispose', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(
        MemoryInfo(
          sampler: () async {
            calls++;
            if (calls == 1) throw StateError('temporary failure');
            return 1024;
          },
        ),
      ),
    );
    await tester.pump();
    expect(calls, 1);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(calls, 2);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    expect(calls, 2);
  });

  testWidgets('connection polling recovers and stops after dispose', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(
        ConnectionsView(
          loader: () async {
            calls++;
            if (calls == 1) throw StateError('temporary failure');
            return const [];
          },
        ),
      ),
    );
    await tester.pump();
    expect(calls, 1);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(calls, 2);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 2);
  });
}
