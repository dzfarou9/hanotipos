import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pos_app/models/hive_adapters/legacy_tolerant_adapters.dart';
import 'package:pos_app/models/product_model.dart';
import 'package:pos_app/services/products_cache.dart';

Product _makeProduct(String id, DateTime updatedAt) {
  return Product(
    id: id,
    name: 'Product $id',
    category: 'General',
    price: 100,
    quantity: 5,
    barcode: null,
    userId: 'u1',
    createdAt: updatedAt,
    updatedAt: updatedAt,
  );
}

void main() {
  late Directory tempDir;
  late Box<Product> box;
  late ProductsCache cache;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('products_cache_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(ProductAdapter());
    box = await Hive.openBox<Product>('test_products');
  });

  setUp(() async {
    await box.clear();
    cache = ProductsCache(box);
  });

  tearDownAll(() async {
    await box.close();
    tempDir.deleteSync(recursive: true);
  });

  test('returns products sorted by updatedAt descending', () {
    box.put('a', _makeProduct('a', DateTime(2026, 1, 1)));
    box.put('b', _makeProduct('b', DateTime(2026, 1, 3)));
    box.put('c', _makeProduct('c', DateTime(2026, 1, 2)));

    final products = cache.getAllSorted();

    expect(products.map((p) => p.id).toList(), ['b', 'c', 'a']);
  });

  test('returns the same cached list instance on repeated calls', () {
    box.put('a', _makeProduct('a', DateTime(2026, 1, 1)));

    final first = cache.getAllSorted();
    final second = cache.getAllSorted();

    expect(second, same(first));
  });

  test('invalidate forces a fresh sorted read', () {
    box.put('a', _makeProduct('a', DateTime(2026, 1, 1)));
    cache.getAllSorted();

    box.put('b', _makeProduct('b', DateTime(2026, 1, 2)));
    expect(cache.getAllSorted().map((p) => p.id).toList(), ['a']);

    cache.invalidate();
    final fresh = cache.getAllSorted();

    expect(fresh.map((p) => p.id).toList(), ['b', 'a']);
  });
}