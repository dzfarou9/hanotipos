// test/helpers/suppliers_stock_policy_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/helpers/suppliers_stock_policy.dart';
import 'package:pos_app/models/purchase_model.dart';

PurchaseItem _item(String pid, int qty) => PurchaseItem(
    id: 'i-$pid', productId: pid, productName: 'n', costPrice: 1, quantity: qty, subtotal: qty.toDouble());

void main() {
  group('returnCap', () {
    test('cap = purchased minus already returned', () {
      expect(SuppliersStockPolicy.returnCap(purchasedQuantity: 10, alreadyReturnedQuantity: 3), 7);
    });
    test('never below zero', () {
      expect(SuppliersStockPolicy.returnCap(purchasedQuantity: 5, alreadyReturnedQuantity: 9), 0);
    });
  });

  group('wouldGoNegative', () {
    test('true when decrease exceeds current stock', () {
      expect(SuppliersStockPolicy.wouldGoNegative(currentQuantity: 4, change: -5), isTrue);
    });
    test('false when enough stock', () {
      expect(SuppliersStockPolicy.wouldGoNegative(currentQuantity: 5, change: -5), isFalse);
    });
    test('increase never goes negative', () {
      expect(SuppliersStockPolicy.wouldGoNegative(currentQuantity: 0, change: 3), isFalse);
    });
  });

  group('invalidReturnProducts', () {
    test('valid when within caps', () {
      final result = SuppliersStockPolicy.invalidReturnProducts(
        originalItems: [_item('a', 10), _item('b', 4)],
        returnedSoFarByProductId: {'a': 2},
        newReturnByProductId: {'a': 8, 'b': 4},
      );
      expect(result, isEmpty);
    });
    test('flags product exceeding cap', () {
      final result = SuppliersStockPolicy.invalidReturnProducts(
        originalItems: [_item('a', 10)],
        returnedSoFarByProductId: {'a': 5},
        newReturnByProductId: {'a': 6},
      );
      expect(result, ['a']);
    });
    test('flags product not in original purchase', () {
      final result = SuppliersStockPolicy.invalidReturnProducts(
        originalItems: [_item('a', 10)],
        returnedSoFarByProductId: {},
        newReturnByProductId: {'zzz': 1},
      );
      expect(result, ['zzz']);
    });
  });
}
