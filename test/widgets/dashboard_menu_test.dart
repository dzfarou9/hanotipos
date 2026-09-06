import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_app/widgets/dashboard_menu.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  final scaffoldKey = GlobalKey<ScaffoldState>();
  var closeCount = 0;

  setUp(() => closeCount = 0);

  /// يبني القائمة كـ endDrawer ثم يفتحها، تماماً كما تفعل MainScreen.
  Future<void> pumpMenu(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
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
              home: Scaffold(
                key: scaffoldKey,
                endDrawer: DashboardMenu(
                  onClose: () => closeCount++,
                  themeMode: ThemeMode.light,
                  onThemeModeChange: (_) {},
                ),
                body: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    scaffoldKey.currentState!.openEndDrawer();
    await tester.pumpAndSettle();
  }

  testWidgets('DashboardMenu lists the six destinations once each',
      (tester) async {
    await pumpMenu(tester);

    expect(find.byIcon(Icons.inventory_2_rounded), findsOneWidget);
    expect(find.byIcon(Icons.people_rounded), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_rounded), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
    expect(find.byIcon(Icons.bar_chart_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
  });

  testWidgets('DashboardMenu groups rows under two section labels',
      (tester) async {
    await pumpMenu(tester);

    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('App'), findsOneWidget);
    // كل صف يحمل شيفرون واحد — ستة صفوف، ستة أسهم.
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(6));
  });

  testWidgets('DashboardMenu close button calls onClose', (tester) async {
    await pumpMenu(tester);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(closeCount, 1);
  });
}
