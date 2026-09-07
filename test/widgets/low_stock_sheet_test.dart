import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_app/models/product_model.dart';
import 'package:pos_app/widgets/empty_state.dart';
import 'package:pos_app/widgets/low_stock_sheet.dart';

Product _product(String id, String name, double quantity) => Product(
      id: id,
      name: name,
      category: 'General',
      price: 100,
      quantity: quantity,
      userId: 'user1',
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        startLocale: const Locale('en', 'US'),
        useOnlyLangCode: true,
        saveLocale: false,
        child: MaterialApp(
          home: Scaffold(
            body: sheet,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows low stock and out of stock product rows', (tester) async {
    await pumpSheet(
      tester,
      LowStockProductsSheet(
        lowStock: [_product('1', 'Milk', 4.0)],
        outOfStock: [_product('2', 'Bread', 0.0)],
      ),
    );

    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('Bread'), findsOneWidget);
  });

  testWidgets('shows empty state when there are no affected products',
      (tester) async {
    await pumpSheet(
      tester,
      const LowStockProductsSheet(lowStock: [], outOfStock: []),
    );

    expect(find.byType(EmptyState), findsOneWidget);
  });
}