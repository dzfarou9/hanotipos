// test/models/purchase_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/purchase_model.dart';

PurchaseItem pitem(String pid, double cost, double qty) => PurchaseItem(
      id: 'i-$pid-$qty', productId: pid, productName: 'P$pid',
      costPrice: cost, quantity: qty, subtotal: cost * qty,
    );

void main() {
  test('PurchaseItem parses fractional from Firestore map', () {
    final pi = PurchaseItem.fromJson({
      'id': 'i1', 'product_id': 'p1', 'product_name': 'P',
      'cost_price': 600, 'quantity': 25.5, 'subtotal': 15300,
    });
    expect(pi.quantity, 25.5);
  });

  test('availableForReturn returns fractional remainder', () {
    final p = Purchase(
      id: 'pu1', items: [pitem('p1', 600, 25.5)],
      supplierId: 's1', supplierName: 'S', total: 15300, userId: 'u1',
      returnedItems: [pitem('p1', 600, 0.5)],
    );
    final avail = p.availableForReturn();
    expect(avail.single.quantity, closeTo(25.0, 0.0001));
  });

  test('availableForReturn accepts fractional extraReturned', () {
    final p = Purchase(
      id: 'pu1', items: [pitem('p1', 600, 10)],
      supplierId: 's1', supplierName: 'S', total: 6000, userId: 'u1',
    );
    final avail = p.availableForReturn(extraReturned: {'p1': 2.5});
    expect(avail.single.quantity, closeTo(7.5, 0.0001));
  });
}
