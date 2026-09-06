import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_app/widgets/language_switcher.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  Future<void> pumpSwitcher(WidgetTester tester) async {
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
              home: const Scaffold(
                body: Center(child: LanguageSwitcher()),
              ),
            ),
          ),
        ),
      );
    });
    await tester.pumpAndSettle();
  }

  testWidgets('shows current language code on the button', (tester) async {
    await pumpSwitcher(tester);

    expect(find.text('EN'), findsOneWidget);
  });

  testWidgets('menu lists the three languages', (tester) async {
    await pumpSwitcher(tester);

    await tester.tap(find.byType(PopupMenuButton<Locale>));
    await tester.pumpAndSettle();

    expect(find.text('English'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
    expect(find.text('Français'), findsOneWidget);
  });

  testWidgets('selecting a language changes the locale', (tester) async {
    await pumpSwitcher(tester);

    await tester.tap(find.byType(PopupMenuButton<Locale>));
    await tester.pumpAndSettle();

    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();

    expect(find.text('AR'), findsOneWidget);
  });
}
