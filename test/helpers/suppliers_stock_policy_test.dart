// test/helpers/suppliers_stock_policy_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/helpers/suppliers_stock_policy.dart';
import 'package:pos_app/models/purchase_model.dart';

PurchaseItem _item(String pid, double qty) => PurchaseItem(
    id: 'i-$pid', productId: pid, productName: 'n', costPrice: 1, quantity: qty, subtotal: qty);

void main() {
  group('returnCap', () {
    test('cap = purchased minus already returned', () {
      expect(SuppliersStockPolicy.returnCap(purchasedQuantity: 10.0, alreadyReturnedQuantity: 3.0), 7.0);
    });
    test('never below zero', () {
      expect(SuppliersStockPolicy.returnCap(purchasedQuantity: 5.0, alreadyReturnedQuantity: 9.0), 0.0);
    });
    test('returnCap honors fractional returns', () {
      expect(SuppliersStockPolicy.returnCap(
          purchasedQuantity: 25.5, alreadyReturnedQuantity: 0.5), 25.0);
      expect(SuppliersStockPolicy.returnCap(
          purchasedQuantity: 25.5, alreadyReturnedQuantity: 30), 0.0);
    });
  });

  group('wouldGoNegative', () {
    test('true when decrease exceeds current stock', () {
      expect(SuppliersStockPolicy.wouldGoNegative(currentQuantity: 4.0, change: -5.0), isTrue);
    });
    test('false when enough stock', () {
      expect(SuppliersStockPolicy.wouldGoNegative(currentQuantity: 5.0, change: -5.0), isFalse);
    });
    test('increase never goes negative', () {
      expect(SuppliersStockPolicy.wouldGoNegative(currentQuantity: 0.0, change: 3.0), isFalse);
    });
    test('wouldGoNegative tolerates epsilon', () {
      expect(SuppliersStockPolicy.wouldGoNegative(currentQuantity: 0.0009, change: 0), isFalse);
      expect(SuppliersStockPolicy.wouldGoNegative(currentQuantity: 0.5, change: -0.6), isTrue);
    });
  });

  group('invalidReturnProducts', () {
    test('valid when within caps', () {
      final result = SuppliersStockPolicy.invalidReturnProducts(
        originalItems: [_item('a', 10.0), _item('b', 4.0)],
        returnedSoFarByProductId: {'a': 2.0},
        newReturnByProductId: {'a': 8.0, 'b': 4.0},
      );
      expect(result, isEmpty);
    });
    test('flags product exceeding cap', () {
      final result = SuppliersStockPolicy.invalidReturnProducts(
        originalItems: [_item('a', 10.0)],
        returnedSoFarByProductId: {'a': 5.0},
        newReturnByProductId: {'a': 6.0},
      );
      expect(result, ['a']);
    });
    test('flags product not in original purchase', () {
      final result = SuppliersStockPolicy.invalidReturnProducts(
        originalItems: [_item('a', 10.0)],
        returnedSoFarByProductId: {},
        newReturnByProductId: {'zzz': 1.0},
      );
      expect(result, ['zzz']);
    });
  });
}
