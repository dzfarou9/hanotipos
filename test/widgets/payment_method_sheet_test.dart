import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_app/models/product_model.dart';
import 'package:pos_app/services/cart_service.dart';
import 'package:pos_app/widgets/pos/payment_method_sheet.dart';

Product _product(String id, String name, double price) => Product(
      id: id,
      name: name,
      category: 'General',
      price: price,
      quantity: 10,
      userId: 'user1',
    );

CartService _cartWith({double price = 250, double quantity = 2}) {
  final cart = CartService();
  cart.addProduct(_product('1', 'Milk', price), quantity: quantity);
  return cart;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  /// يبني زراً يفتح الورقة، فتُختبر الورقة عبر مسار العرض الحقيقي
  /// (showModalBottomSheet) بدلاً من إدراج الودجت مباشرة.
  Future<void> pumpOpener(
    WidgetTester tester, {
    required CartService cart,
    VoidCallback? onCash,
    VoidCallback? onCard,
    VoidCallback? onDebt,
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
                  builder: (context) => ElevatedButton(
                    onPressed: () => showPaymentMethodSheet(
                      context,
                      cart: cart,
                      onCash: onCash ?? () {},
                      onCard: onCard ?? () {},
                      onDebt: onDebt ?? () {},
                    ),
                    child: const Text('open'),
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

  testWidgets('renders the three payment methods and the cart total',
      (tester) async {
    await pumpOpener(tester, cart: _cartWith(price: 250, quantity: 2));

    expect(find.text('Payment Method'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Edahabia / CIB'), findsOneWidget);
    expect(find.text('Debt / Credit'), findsOneWidget);
    expect(find.text('500.00 DZD'), findsOneWidget);
    expect(find.text('2.0 items'), findsOneWidget);
  });

  testWidgets('tapping cash closes the sheet and fires onCash only',
      (tester) async {
    var cashCalls = 0;
    var cardCalls = 0;
    var debtCalls = 0;

    await pumpOpener(
      tester,
      cart: _cartWith(),
      onCash: () => cashCalls++,
      onCard: () => cardCalls++,
      onDebt: () => debtCalls++,
    );

    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();

    expect(cashCalls, 1);
    expect(cardCalls, 0);
    expect(debtCalls, 0);
    expect(find.text('Payment Method'), findsNothing);
  });

  testWidgets('tapping debt closes the sheet and fires onDebt only',
      (tester) async {
    var cashCalls = 0;
    var debtCalls = 0;

    await pumpOpener(
      tester,
      cart: _cartWith(),
      onCash: () => cashCalls++,
      onDebt: () => debtCalls++,
    );

    await tester.tap(find.text('Debt / Credit'));
    await tester.pumpAndSettle();

    expect(debtCalls, 1);
    expect(cashCalls, 0);
    expect(find.text('Payment Method'), findsNothing);
  });

  testWidgets('close button dismisses without selecting a method',
      (tester) async {
    var calls = 0;

    await pumpOpener(
      tester,
      cart: _cartWith(),
      onCash: () => calls++,
      onCard: () => calls++,
      onDebt: () => calls++,
    );

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.text('Payment Method'), findsNothing);
  });

  testWidgets('marks the currently selected method with a check',
      (tester) async {
    final cart = _cartWith();
    cart.setPaymentMethod('Edahabia/CIB');

    await pumpOpener(tester, cart: cart);

    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    // الطريقتان غير المختارتين تُظهران سهم الانتقال.
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));
  });
}
