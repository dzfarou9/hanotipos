// test/models/sale_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/sale_model.dart';

SaleItem item(String pid, double price, double qty) => SaleItem(
      id: 'i-$pid-$qty', productId: pid, productName: 'P$pid',
      price: price, quantity: qty, subtotal: price * qty,
    );

Sale sale({required List<SaleItem> items, List<SaleItem>? returned}) => Sale(
      id: 's1', items: items, subtotal: 0, discount: 0, tax: 0, total: 0,
      paymentMethod: 'Cash', userId: 'u1',
      returnedItems: returned,
    );

void main() {
  test('SaleItem parses fractional quantity from Firestore map', () {
    final si = SaleItem.fromJson({
      'id': 'i1', 'product_id': 'p1', 'product_name': 'P',
      'price': 800, 'quantity': 0.85, 'subtotal': 680,
    });
    expect(si.quantity, 0.85);
  });

  test('canReturn honors fractional partial returns with epsilon', () {
    final s = sale(items: [item('p1', 800, 0.85)], returned: [item('p1', 800, 0.3)]);
    expect(s.canReturn, isTrue);
  });

  test('canReturn false when returned equals sold (within epsilon)', () {
    final s = sale(items: [item('p1', 800, 0.85)], returned: [item('p1', 800, 0.85)]);
    expect(s.canReturn, isFalse);
  });

  test('availableForReturn returns fractional remainder', () {
    final s = sale(items: [item('p1', 800, 0.85)], returned: [item('p1', 800, 0.3)]);
    final avail = s.availableForReturn;
    expect(avail.single.quantity, closeTo(0.55, 0.0001));
  });
}
