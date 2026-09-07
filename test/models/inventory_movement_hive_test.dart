// اختبار انحدار: كتابة حركة مخزون في Hive تتطلب adapters مسجلة للenums
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pos_app/models/hive_adapters/legacy_tolerant_adapters.dart';
import 'package:pos_app/models/inventory_movement_enum_adapters.dart';
import 'package:pos_app/models/inventory_movement_model.dart';

void main() {
  late Directory tempDir;
  late Box<InventoryMovement> box;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_movement_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(MovementTypeAdapter());
    Hive.registerAdapter(MovementStatusAdapter());
    Hive.registerAdapter(InventoryMovementAdapter());
    box = await Hive.openBox<InventoryMovement>('movement_regression');
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('movement_regression');
    await tempDir.delete(recursive: true);
  });

  test('InventoryMovement roundtrips through Hive including enum fields', () async {
    final movement = InventoryMovement(
      id: 'm1',
      productId: 'p1',
      productName: 'منتج',
      type: MovementType.incoming,
      quantity: 5.0,
      price: 100,
      total: 500,
      userId: 'u1',
      status: MovementStatus.completed,
      supplierName: 'مورد',
    );

    await box.put('m1', movement);

    final read = box.get('m1')!;
    expect(read.id, 'm1');
    expect(read.type, MovementType.incoming);
    expect(read.status, MovementStatus.completed);
    expect(read.quantity, 5.0);
    expect(read.supplierName, 'مورد');
  });
}
