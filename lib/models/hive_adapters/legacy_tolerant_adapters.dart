// lib/models/hive_adapters/legacy_tolerant_adapters.dart
//
// Adapters مكتوبة يدوياً للنماذج التي تحوَّلت من int إلى double في quantity.
// القراءة تتقبَّل int (بيانات قديمة) أو double، وتكتب double دائماً.
// هذه الملفات لا تُولَّد من build_runner — لا تحذفها.

import 'package:hive/hive.dart';
import '../product_model.dart';
import '../sale_model.dart';

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

class SaleItemAdapter extends TypeAdapter<SaleItem> {
  @override
  final int typeId = 2;

  @override
  SaleItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SaleItem(
      id: fields[0] as String,
      productId: fields[1] as String,
      productName: fields[2] as String,
      price: (fields[3] as num?)?.toDouble() ?? 0.0,
      // بيانات قديمة: int. بيانات جديدة: double.
      quantity: (fields[4] as num).toDouble(),
      subtotal: (fields[5] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  void write(BinaryWriter writer, SaleItem obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.productId)
      ..writeByte(2)
      ..write(obj.productName)
      ..writeByte(3)
      ..write(obj.price)
      ..writeByte(4)
      ..write(obj.quantity)
      ..writeByte(5)
      ..write(obj.subtotal);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaleItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SaleAdapter extends TypeAdapter<Sale> {
  @override
  final int typeId = 3;

  @override
  Sale read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Sale(
      id: fields[0] as String,
      items: (fields[1] as List).cast<SaleItem>(),
      subtotal: (fields[2] as num?)?.toDouble() ?? 0.0,
      discount: (fields[3] as num?)?.toDouble() ?? 0.0,
      tax: (fields[4] as num?)?.toDouble() ?? 0.0,
      total: (fields[5] as num?)?.toDouble() ?? 0.0,
      paymentMethod: fields[6] as String,
      createdAt: fields[7] as DateTime?,
      isSynced: fields[8] as bool,
      userId: fields[9] as String,
      customerName: fields[10] as String?,
      customerPhone: fields[11] as String?,
      customerId: fields[17] as String?,
      saleType: fields[12] as String,
      originalSaleId: fields[13] as String?,
      returnedItems: (fields[14] as List?)?.cast<SaleItem>(),
      returnTotal: (fields[15] as num?)?.toDouble(),
      isFullyReturned: fields[16] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Sale obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.items)
      ..writeByte(2)
      ..write(obj.subtotal)
      ..writeByte(3)
      ..write(obj.discount)
      ..writeByte(4)
      ..write(obj.tax)
      ..writeByte(5)
      ..write(obj.total)
      ..writeByte(6)
      ..write(obj.paymentMethod)
      ..writeByte(7)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.isSynced)
      ..writeByte(9)
      ..write(obj.userId)
      ..writeByte(10)
      ..write(obj.customerName)
      ..writeByte(11)
      ..write(obj.customerPhone)
      ..writeByte(12)
      ..write(obj.saleType)
      ..writeByte(13)
      ..write(obj.originalSaleId)
      ..writeByte(14)
      ..write(obj.returnedItems)
      ..writeByte(15)
      ..write(obj.returnTotal)
      ..writeByte(16)
      ..write(obj.isFullyReturned)
      ..writeByte(17)
      ..write(obj.customerId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
