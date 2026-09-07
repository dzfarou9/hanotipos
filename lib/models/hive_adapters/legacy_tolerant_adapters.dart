// lib/models/hive_adapters/legacy_tolerant_adapters.dart
//
// Adapters مكتوبة يدوياً للنماذج التي تحوَّلت من int إلى double في quantity.
// القراءة تتقبَّل int (بيانات قديمة) أو double، وتكتب double دائماً.
// هذه الملفات لا تُولَّد من build_runner — لا تحذفها.

import 'package:hive/hive.dart';
import '../product_model.dart';

class ProductAdapter extends TypeAdapter<Product> {
  @override
  final int typeId = 0;

  @override
  Product read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Product(
      id: fields[0] as String,
      name: fields[1] as String,
      category: fields[2] as String,
      price: (fields[3] as num).toDouble(),
      // بيانات قديمة: int. بيانات جديدة: double.
      quantity: (fields[4] as num).toDouble(),
      description: fields[5] as String?,
      barcode: fields[8] as String?,
      createdAt: fields[6] as DateTime?,
      updatedAt: fields[7] as DateTime?,
      isSynced: fields[9] as bool,
      userId: fields[10] as String,
      minStockLevel: (fields[11] as num).toInt(),
      costPrice: (fields[12] as num?)?.toDouble(),
      // صناديق قديمة بلا الحقل 13 → piece
      unit: (fields[13] as String?) ?? 'piece',
    );
  }

  @override
  void write(BinaryWriter writer, Product obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.name)
      ..writeByte(2)..write(obj.category)
      ..writeByte(3)..write(obj.price)
      ..writeByte(4)..write(obj.quantity)
      ..writeByte(5)..write(obj.description)
      ..writeByte(6)..write(obj.createdAt)
      ..writeByte(7)..write(obj.updatedAt)
      ..writeByte(8)..write(obj.barcode)
      ..writeByte(9)..write(obj.isSynced)
      ..writeByte(10)..write(obj.userId)
      ..writeByte(11)..write(obj.minStockLevel)
      ..writeByte(12)..write(obj.costPrice)
      ..writeByte(13)..write(obj.unit);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
