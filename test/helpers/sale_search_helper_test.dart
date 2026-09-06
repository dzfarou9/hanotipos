import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/helpers/sale_search_helper.dart';
import 'package:pos_app/models/sale_model.dart';

Sale _makeSale({String? customerName, List<String> productNames = const []}) {
  return Sale(
    id: 'ABC-123',
    items: productNames
        .map((name) => SaleItem(
              id: name,
              productId: name,
              productName: name,
              price: 10,
              quantity: 1,
              subtotal: 10,
            ))
        .toList(),
    subtotal: 10.0 * productNames.length,
    discount: 0,
    tax: 0,
    total: 10.0 * productNames.length,
    paymentMethod: 'Cash',
    userId: 'u1',
    customerName: customerName,
  );
}

void main() {
  test('buildSaleSearchText contains lowercased invoice id', () {
    final sale = _makeSale();

    final text = buildSaleSearchText(sale);

    expect(text, contains('abc-123'));
    expect(text, isNot(contains('ABC-123')));
  });

  test('buildSaleSearchText contains lowercased customer name', () {
    final sale = _makeSale(customerName: 'Karim Ben');

    final text = buildSaleSearchText(sale);

    expect(text, contains('karim ben'));
  });

  test('buildSaleSearchText contains all lowercased product names', () {
    final sale =
        _makeSale(productNames: ['Espresso', 'Croissant', 'Orange Juice']);

    final text = buildSaleSearchText(sale);

    expect(text, contains('espresso'));
    expect(text, contains('croissant'));
    expect(text, contains('orange juice'));
  });

  test('buildSaleSearchText handles missing customer and empty items', () {
    final sale = _makeSale();

    final text = buildSaleSearchText(sale);

    expect(text, 'abc-123');
  });
}