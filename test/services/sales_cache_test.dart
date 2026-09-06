import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pos_app/models/sale_model.dart';
import 'package:pos_app/services/sales_cache.dart';

Sale _makeSale(String id, DateTime createdAt) {
  return Sale(
    id: id,
    items: [
      SaleItem(
        id: 'i1',
        productId: 'p1',
        productName: 'Coffee',
        price: 100,
        quantity: 1,
        subtotal: 100,
      ),
    ],
    subtotal: 100,
    discount: 0,
    tax: 0,
    total: 100,
    paymentMethod: 'Cash',
    createdAt: createdAt,
    userId: 'u1',
  );
}

void main() {
  late Directory tempDir;
  late Box<Sale> box;
  late SalesCache cache;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sales_cache_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(SaleAdapter());
    Hive.registerAdapter(SaleItemAdapter());
    box = await Hive.openBox<Sale>('test_sales');
  });

  setUp(() async {
    await box.clear();
    cache = SalesCache(box);
  });

  tearDownAll(() async {
    await box.close();
    tempDir.deleteSync(recursive: true);
  });

  test('returns sales sorted by createdAt descending', () {
    box.put('a', _makeSale('a', DateTime(2026, 1, 1)));
    box.put('b', _makeSale('b', DateTime(2026, 1, 3)));
    box.put('c', _makeSale('c', DateTime(2026, 1, 2)));

    final sales = cache.getAllSorted();

    expect(sales.map((s) => s.id).toList(), ['b', 'c', 'a']);
  });

  test('returns the same cached list instance on repeated calls', () {
    box.put('a', _makeSale('a', DateTime(2026, 1, 1)));

    final first = cache.getAllSorted();
    final second = cache.getAllSorted();

    expect(second, same(first));
  });

  test('invalidate forces a fresh sorted read', () {
    box.put('a', _makeSale('a', DateTime(2026, 1, 1)));
    cache.getAllSorted();

    box.put('b', _makeSale('b', DateTime(2026, 1, 2)));
    expect(cache.getAllSorted().map((s) => s.id).toList(), ['a']);

    cache.invalidate();
    final fresh = cache.getAllSorted();

    expect(fresh.map((s) => s.id).toList(), ['b', 'a']);
  });
}