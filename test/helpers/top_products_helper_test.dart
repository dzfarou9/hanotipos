import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/helpers/top_products_helper.dart';
import 'package:pos_app/models/product_model.dart';
import 'package:pos_app/models/sale_model.dart';

Product _product(String id, {double price = 100}) => Product(
      id: id,
      name: 'Product $id',
      category: 'General',
      price: price,
      quantity: 0,
      userId: 'user1',
    );

SaleItem _item(String id, String productId, double price, int qty) => SaleItem(
      id: id,
      productId: productId,
      productName: 'Product $productId',
      price: price,
      quantity: qty,
      subtotal: price * qty,
    );

Sale _sale(
  String id,
  List<SaleItem> items, {
  List<SaleItem>? returnedItems,
  bool isReturn = false,
  DateTime? createdAt,
}) =>
    Sale(
      id: id,
      items: items,
      subtotal: items.fold(0.0, (sum, i) => sum + i.subtotal),
      discount: 0,
      tax: 0,
      total: items.fold(0.0, (sum, i) => sum + i.subtotal),
      paymentMethod: 'Cash',
      createdAt: createdAt ?? DateTime.now(),
      userId: 'user1',
      saleType: isReturn ? 'return' : 'sale',
      returnedItems: returnedItems,
      returnTotal: returnedItems == null
          ? null
          : returnedItems
              .fold<double>(0.0, (sum, i) => sum + i.subtotal),
      isFullyReturned: returnedItems != null && items.length == returnedItems.length,
    );

void main() {
  group('calculateTopProducts', () {
    test('returns top 3 products by quantity with their total sales', () {
      final milk = _product('milk', price: 100);
      final bread = _product('bread', price: 50);
      final eggs = _product('eggs', price: 30);
      final juice = _product('juice', price: 200);

      final result = calculateTopProducts(
        [
          _sale('s1', [_item('i1', 'milk', 100, 5)]),
          _sale('s2', [_item('i2', 'bread', 50, 4)]),
          _sale('s3', [_item('i3', 'eggs', 30, 3)]),
          _sale('s4', [_item('i4', 'juice', 200, 2)]),
        ],
        [milk, bread, eggs, juice],
      );

      expect(result.length, 3);
      expect(result[0].product.id, 'milk');
      expect(result[0].quantity, 5);
      expect(result[0].totalSales, 500.0);
      expect(result[1].product.id, 'bread');
      expect(result[2].product.id, 'eggs');
    });

    test('excludes return sales from the ranking', () {
      final milk = _product('milk', price: 100);
      final bread = _product('bread', price: 50);

      final result = calculateTopProducts(
        [
          _sale('s1', [_item('i1', 'milk', 100, 5)]),
          _sale('s2', [_item('i2', 'bread', 50, 4)], isReturn: true),
        ],
        [milk, bread],
      );

      expect(result.length, 1);
      expect(result[0].product.id, 'milk');
    });

    test('excludes sales outside the current month', () {
      final milk = _product('milk', price: 100);
      final now = DateTime.now();
      final lastMonth = DateTime(now.year, now.month - 1, 15);

      final result = calculateTopProducts(
        [
          _sale('s1', [_item('i1', 'milk', 100, 5)], createdAt: lastMonth),
        ],
        [milk],
      );

      expect(result, isEmpty);
    });

    test('partial returns reduce quantity and total sales', () {
      final milk = _product('milk', price: 100);

      final result = calculateTopProducts(
        [
          _sale(
            's1',
            [_item('i1', 'milk', 100, 5)],
            returnedItems: [_item('r1', 'milk', 100, 2)],
          ),
        ],
        [milk],
      );

      expect(result.length, 1);
      expect(result[0].quantity, 3);
      expect(result[0].totalSales, 300.0);
    });

    test('respects a custom limit', () {
      final milk = _product('milk', price: 100);
      final bread = _product('bread', price: 50);

      final result = calculateTopProducts(
        [
          _sale('s1', [_item('i1', 'milk', 100, 5)]),
          _sale('s2', [_item('i2', 'bread', 50, 4)]),
        ],
        [milk, bread],
        limit: 1,
      );

      expect(result.length, 1);
      expect(result[0].product.id, 'milk');
    });
  });
}