// اختبار: Product بكمية double ووحدة بيع، مع adapter متسامح مع البيانات القديمة
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pos_app/models/product_model.dart';
import 'package:pos_app/models/hive_adapters/legacy_tolerant_adapters.dart';

void main() {
  late Directory tempDir;
  late Box<Product> box;

  setUpAll(() {
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductAdapter());
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_product_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox<Product>('product_roundtrip_test');
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('product_roundtrip_test');
    await tempDir.delete(recursive: true);
  });

  test('fromMap tolerates legacy int quantity and missing unit', () {
    final p = Product.fromMap('p1', {
      'name': 'Sugar', 'price': 120, 'quantity': 5, 'user_id': 'u1',
    });
    expect(p.quantity, 5.0);
    expect(p.unit, 'piece');
    expect(p.isWeighted, isFalse);
  });

  test('fromMap parses decimal quantity and unit', () {
    final p = Product.fromMap('p2', {
      'name': 'Oil', 'price': 800, 'quantity': 12.5, 'user_id': 'u1',
      'unit': 'kg',
    });
    expect(p.quantity, 12.5);
    expect(p.unit, 'kg');
    expect(p.isWeighted, isTrue);
  });

  test('Hive roundtrip keeps unit and double quantity', () async {
    final p = Product(
      id: 'p1', name: 'Oil', category: 'G', price: 800, quantity: 12.5,
      userId: 'u1', unit: 'kg',
    );

    await box.put('p1', p);

    final read = box.get('p1')!;
    expect(read.quantity, 12.5);
    expect(read.unit, 'kg');
  });

  test('Hive roundtrip defaults unit to piece when omitted', () async {
    final p = Product(
      id: 'p3', name: 'Sugar', category: 'G', price: 120, quantity: 5,
      userId: 'u1',
    );

    await box.put('p3', p);

    final read = box.get('p3')!;
    expect(read.quantity, 5.0);
    expect(read.unit, 'piece');
    expect(read.isWeighted, isFalse);
  });
}
