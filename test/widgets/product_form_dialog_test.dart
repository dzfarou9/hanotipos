import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_app/models/product_model.dart';
import 'package:pos_app/widgets/inventory/product_form_dialog.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  Future<void> pumpOpener(
    WidgetTester tester, {
    required Future<void> Function(BuildContext ctx) onOpen,
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
                  builder: (context) => Center(
                    child: ElevatedButton(
                      onPressed: () => onOpen(context),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
    await tester.pump();
  }

  testWidgets('form parses decimal quantity and unit', (tester) async {
    ProductFormData? captured;
    await pumpOpener(tester, onOpen: (ctx) async {
      final result = await showProductFormDialog(ctx);
      captured = result?.data;
    });
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('product_name_field')), 'Sugar');
    await tester.enterText(find.byKey(const Key('product_price_field')), '100');
    await tester.enterText(
        find.byKey(const Key('product_quantity_field')), '12.5');
    await tester.tap(find.byKey(const Key('product_unit_kg')));
    await tester.ensureVisible(find.byKey(const Key('product_form_save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('product_form_save')));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.quantity, 12.5);
    expect(captured!.unit, 'kg');
  });

  testWidgets('editing prefills unit and quantity', (tester) async {
    ProductFormData? captured;
    final product = Product(
      id: 'p1',
      name: 'Flour',
      category: 'General',
      price: 120,
      quantity: 3.5,
      userId: 'u1',
      unit: 'litre',
    );
    await pumpOpener(tester, onOpen: (ctx) async {
      final result = await showProductFormDialog(ctx, product: product);
      captured = result?.data;
    });
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('product_unit_liter')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('product_form_save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('product_form_save')));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.quantity, 3.5);
    expect(captured!.unit, 'litre');
  });
}
