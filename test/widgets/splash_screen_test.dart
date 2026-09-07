// test/widgets/splash_screen_test.dart
//
// اختبارات شاشة البداية المعاد تصميمها: العلامة المونوغرام، الكلمة،
// واللودر النقطي — بدون أي منطق جلسات/مزامنة.

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_app/screens/splash_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  Future<void> pumpSplash(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    Future<void> Function()? onSplashVisible,
  }) async {
    // تحميل ترجمات easy_localization يتطلب async حقيقي
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
              theme: ThemeData(brightness: brightness),
              home: SplashScreen(
                themeMode: ThemeMode.system,
                onThemeModeChange: (_) {},
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    // تمرير مؤقتات التتابع (250/550/900ms): حركات الدخول تكتمل والشاشة معروضة
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    // الفحوصات تُنفَّذ والشاشة لا تزال ظاهرة (قبل تفريغ مؤقت التنقل)
    if (onSplashVisible != null) await onSplashVisible();

    // تفريغ مؤقت الحد الأدنى للبداية (1600ms): بعد فشل فحص الجلسة في بيئة
    // الاختبار ينتقل التطبيق إلى شاشة الدخول بأمان — لا مؤقتات معلقة عند النهاية
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }

  testWidgets('shows monogram H glyph inside a rounded mark', (tester) async {
    await pumpSplash(
      tester,
      onSplashVisible: () async {
        // حرف العلامة داخل الحاوية المتدرجة
        expect(find.text('H'), findsOneWidget);
      },
    );
  });

  testWidgets('shows brand name wordmark', (tester) async {
    await pumpSplash(
      tester,
      onSplashVisible: () async {
        expect(find.text('HANOTI'), findsOneWidget);
      },
    );
  });

  testWidgets('shows tagline pill and bottom subtagline', (tester) async {
    await pumpSplash(
      tester,
      onSplashVisible: () async {
        expect(find.text('Point of Sale System'), findsOneWidget);
        expect(find.text('Smart Business Management'), findsOneWidget);
      },
    );
  });

  testWidgets('uses breathing dots loader, not a material spinner',
      (tester) async {
    await pumpSplash(
      tester,
      onSplashVisible: () async {
        // الشكل الجديد: ثلاث نقاط صغيرة نابضة (حاويات دائرية 6px)
        final dots = find.byWidgetPredicate((w) =>
            w is Container &&
            w.constraints != null &&
            w.constraints!.maxWidth == 6 &&
            w.constraints!.maxHeight == 6);
        expect(dots, findsNWidgets(3));

        // الشكل القديم: CircularProgressIndicator ممنوع
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  });

  testWidgets('renders in dark theme without errors', (tester) async {
    await pumpSplash(
      tester,
      brightness: Brightness.dark,
      onSplashVisible: () async {
        expect(find.text('HANOTI'), findsOneWidget);
      },
    );
  });
}
