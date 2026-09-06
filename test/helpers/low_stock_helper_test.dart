import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/helpers/low_stock_helper.dart';
import 'package:pos_app/models/product_model.dart';

Product _product(String id, int quantity) => Product(
      id: id,
      name: 'Product $id',
      category: 'General',
      price: 100,
      quantity: quantity,
      userId: 'user1',
    );

void main() {
  group('classifyLowStockProducts', () {
    test('splits products into out of stock and low stock buckets', () {
      final result = classifyLowStockProducts([
        _product('a', 0),
        _product('b', 5),
        _product('c', 10),
        _product('d', 11),
        _product('e', 100),
      ]);

      expect(result.outOfStock.map((p) => p.id), ['a']);
      expect(result.lowStock.map((p) => p.id), ['b', 'c']);
    });

    test('quantity 0 is out of stock, not low stock', () {
      final result = classifyLowStockProducts([_product('a', 0)]);

      expect(result.outOfStock.map((p) => p.id), ['a']);
      expect(result.lowStock, isEmpty);
    });

    test('returns empty lists when nothing is low or out of stock', () {
      final result = classifyLowStockProducts([_product('a', 50)]);

      expect(result.lowStock, isEmpty);
      expect(result.outOfStock, isEmpty);
    });
  });
}