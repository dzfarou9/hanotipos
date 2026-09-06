import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_app/screens/login_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  Future<void> pumpLogin(WidgetTester tester) async {
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
              home: LoginScreen(
                themeMode: ThemeMode.light,
                onThemeModeChange: (_) {},
              ),
            ),
          ),
        ),
      );
    });
    await tester.pumpAndSettle();
  }

  testWidgets('shows no validation error while typing a valid phone',
      (tester) async {
    await pumpLogin(tester);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone Number'), '0551234567');
    await tester.pump();

    expect(find.text('Phone number is required'), findsNothing);
    expect(find.text('Enter a valid phone number'), findsNothing);
  });

  testWidgets('shows required error after clearing an empty phone',
      (tester) async {
    await pumpLogin(tester);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone Number'), '05');
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone Number'), '');
    await tester.pump();

    expect(find.text('Phone number is required'), findsOneWidget);
  });

  testWidgets('shows minimum 6 characters error for short password',
      (tester) async {
    await pumpLogin(tester);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone Number'), '0551234567');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), '123');
    await tester.pump();

    expect(find.text('Minimum 6 characters'), findsOneWidget);
  });

  testWidgets('sign in button is disabled when form is incomplete',
      (tester) async {
    await pumpLogin(tester);

    final button = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Sign In'),
        matching: find.byType(ElevatedButton),
      ),
    );

    expect(button.onPressed, isNull);
  });

  testWidgets('sign in button is enabled when form is valid', (tester) async {
    await pumpLogin(tester);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone Number'), '0551234567');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), '123456');
    await tester.pump();

    final button = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Sign In'),
        matching: find.byType(ElevatedButton),
      ),
    );

    expect(button.onPressed, isNotNull);
  });
}