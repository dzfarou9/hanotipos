import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_app/models/product_model.dart';
import 'package:pos_app/widgets/pos/weighted_quantity_sheet.dart';

Product weighted() => Product(
      id: 'p1', name: 'Oil', category: 'G', price: 800,
      quantity: 10.0, userId: 'u1', unit: 'kg',
    );

/// يغلّف التطبيق بـ EasyLocalization لأن الورقة تستخدم .tr()
/// (نفس نمط payment_method_sheet_test).
Future<void> pumpOpener(
  WidgetTester tester, {
  required ValueChanged<double?> onDone,
}) async {
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
          builder: (localizationContext) => MaterialApp(
            locale: localizationContext.locale,
            supportedLocales: localizationContext.supportedLocales,
            localizationsDelegates: localizationContext.localizationDelegates,
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      final result = await showWeightedQuantitySheet(
                        ctx,
                        product: weighted(),
                        currency: 'DZD',
                      );
                      onDone(result);
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // انتظار تحميل ملفات الترجمة قبل فتح الورقة.
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('accepts decimal quantity and returns it', (tester) async {
    double? result;
    await pumpOpener(tester, onDone: (r) => result = r);

    await tester.enterText(find.byKey(const Key('weighted_qty_field')), '0.85');
    // نبض لتفعيل إعادة البناء بعد onChanged قبل النقر على الزر.
    await tester.pump();
    await tester.tap(find.byKey(const Key('weighted_add_btn')));
    await tester.pumpAndSettle();

    expect(result, 0.85);
  });

  testWidgets('blocks quantity above stock', (tester) async {
    double? result;
    await pumpOpener(tester, onDone: (r) => result = r);

    await tester.enterText(find.byKey(const Key('weighted_qty_field')), '99');
    await tester.pump();
    await tester.tap(find.byKey(const Key('weighted_add_btn')));
    await tester.pumpAndSettle();

    expect(result, isNull);
    // الورقة ما زالت مفتوحة (الزر معطل ولا يغلق).
    expect(find.byKey(const Key('weighted_add_btn')), findsOneWidget);
  });

  testWidgets('quick chips insert values', (tester) async {
    double? result;
    await pumpOpener(tester, onDone: (r) => result = r);

    await tester.tap(find.byKey(const Key('weighted_chip_0.5')));
    await tester.pumpAndSettle();

    // نقرأ نص حقل الإدخال مباشرة (تسمية الرقاقة نفسها تساوي '0.5'
    // لذا نتحقق من قيمة الحقل لا من العثور على نص واحد).
    final field = tester.widget<TextField>(
      find.byKey(const Key('weighted_qty_field')),
    );
    expect(field.controller!.text, '0.5');
  });
}
