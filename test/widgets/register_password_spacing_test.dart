import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_app/screens/register_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  Future<void> pumpRegister(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Size size = const Size(320, 800),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: locale,
          useOnlyLangCode: true,
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: RegisterScreen(
                themeMode: ThemeMode.light,
                onThemeModeChange: (_) {},
              ),
            ),
          ),
        ),
      );
    });
    await tester.pumpAndSettle();
    tester.takeException();
  }

  Rect rectOfIcon(WidgetTester tester, IconData icon) {
    final elements = tester.elementList(find.byIcon(icon)).toList();
    // Use the first icon (Password field) — confirm field icons mirror it.
    final r = tester.getRect(find.byElementPredicate((e) => e == elements.first));
    return r;
  }

  testWidgets(
      'password fields keep placeholder clear of icons and wide enough (en, 320w)',
      (tester) async {
    await pumpRegister(tester, locale: const Locale('en'), size: const Size(320, 800));

    for (final hintText in ['Create a password', 'Confirm your password']) {
      final hintFinder = find.text(hintText);
      expect(hintFinder, findsOneWidget, reason: 'hint "$hintText" visible');
      final hintRect = tester.getRect(hintFinder);

      final lockRect = rectOfIcon(tester, Icons.lock_rounded);
      final eyeRect = rectOfIcon(tester, Icons.visibility_off_rounded);

      // Placeholder must not overlap either icon glyph.
      expect(hintRect.overlaps(lockRect), isFalse,
          reason: 'hint "$hintText" must not overlap prefix icon');
      expect(hintRect.overlaps(eyeRect), isFalse,
          reason: 'hint "$hintText" must not overlap eye icon');

      // Placeholder must have enough room to not be clipped.
      expect(hintRect.width, greaterThanOrEqualTo(180),
          reason: 'hint "$hintText" has too little horizontal space ($hintRect)');
    }
  });

  testWidgets(
      'password fields keep placeholder clear of icons and wide enough (ar, 320w)',
      (tester) async {
    await pumpRegister(tester, locale: const Locale('ar'), size: const Size(320, 800));

    for (final hintText in ['أنشئ كلمة مرور', 'أكد كلمة المرور']) {
      final hintFinder = find.text(hintText);
      expect(hintFinder, findsOneWidget, reason: 'hint "$hintText" visible');
      final hintRect = tester.getRect(hintFinder);

      final lockRect = rectOfIcon(tester, Icons.lock_rounded);
      final eyeRect = rectOfIcon(tester, Icons.visibility_off_rounded);

      expect(hintRect.overlaps(lockRect), isFalse,
          reason: 'hint "$hintText" must not overlap prefix icon');
      expect(hintRect.overlaps(eyeRect), isFalse,
          reason: 'hint "$hintText" must not overlap eye icon');
      expect(hintRect.width, greaterThanOrEqualTo(180),
          reason: 'hint "$hintText" has too little horizontal space ($hintRect)');
    }
  });
}