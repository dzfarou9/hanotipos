import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_app/screens/reports_screen.dart';
import 'package:pos_app/widgets/stat_tile.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [
            Locale('en'),
            Locale('ar'),
            Locale('fr'),
          ],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          useOnlyLangCode: true,
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: const ReportsScreen(),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('ReportsScreen renders the filter chips and KPI sections',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Reports'), findsOneWidget);

    // Time filters, including Custom.
    expect(find.text('This Week'), findsOneWidget);
    expect(find.text('This Month'), findsOneWidget);
    expect(find.text('This Year'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);

    // Main profit card: net profit is a pinned placeholder for now.
    expect(find.text('Net Profit'), findsOneWidget);
    expect(find.text('Sales Count'), findsOneWidget);
    expect(find.text('Average Sale'), findsOneWidget);

    // Quad cards.
    expect(find.byType(StatTile), findsNWidgets(4));
    expect(find.text('Imports'), findsOneWidget);
    expect(find.text('Exports'), findsOneWidget);
    expect(find.text('Debts'), findsOneWidget);
    expect(find.text('Products'), findsOneWidget);
  });

  testWidgets('ReportsScreen shows the chart empty state without data',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('No data for this period'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
  });

  testWidgets('ReportsScreen switches the selected time filter',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('This Year'));
    await tester.pumpAndSettle();

    // The chips stay in place; switching must not tear down the screen.
    expect(find.text('This Year'), findsOneWidget);
    expect(find.text('Net Profit'), findsOneWidget);
  });
}
