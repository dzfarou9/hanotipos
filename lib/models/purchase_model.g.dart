// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'purchase_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PurchaseItemAdapter extends TypeAdapter<PurchaseItem> {
  @override
  final int typeId = 6;

  @override
  PurchaseItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PurchaseItem(
      id: fields[0] as String,
      productId: fields[1] as String,
      productName: fields[2] as String,
      costPrice: fields[3] as double,
      quantity: fields[4] as int,
      subtotal: fields[5] as double,
    );
  }

  @override
  void write(BinaryWriter writer, PurchaseItem obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.productId)
      ..writeByte(2)
      ..write(obj.productName)
      ..writeByte(3)
      ..write(obj.costPrice)
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
      other is PurchaseItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PurchaseAdapter extends TypeAdapter<Purchase> {
  @override
  final int typeId = 7;

  @override
  Purchase read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Purchase(
      id: fields[0] as String,
      items: (fields[1] as List).cast<PurchaseItem>(),
      supplierId: fields[2] as String,
      supplierName: fields[3] as String,
      total: fields[4] as double,
      note: fields[5] as String?,
      purchaseType: fields[6] as String,
      originalPurchaseId: fields[7] as String?,
      userId: fields[8] as String,
      isSynced: fields[9] as bool,
      createdAt: fields[10] as DateTime?,
      invoiceNumber: fields[11] as String?,
      returnedItems: (fields[12] as List?)?.cast<PurchaseItem>(),
      returnTotal: fields[13] as double?,
      isFullyReturned: fields[14] as bool,
      updatedAt: fields[15] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Purchase obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.items)
      ..writeByte(2)
      ..write(obj.supplierId)
      ..writeByte(3)
      ..write(obj.supplierName)
      ..writeByte(4)
      ..write(obj.total)
      ..writeByte(5)
      ..write(obj.note)
      ..writeByte(6)
      ..write(obj.purchaseType)
      ..writeByte(7)
      ..write(obj.originalPurchaseId)
      ..writeByte(8)
      ..write(obj.userId)
      ..writeByte(9)
      ..write(obj.isSynced)
      ..writeByte(10)
      ..write(obj.createdAt)
      ..writeByte(11)
      ..write(obj.invoiceNumber)
      ..writeByte(12)
      ..write(obj.returnedItems)
      ..writeByte(13)
      ..write(obj.returnTotal)
      ..writeByte(14)
      ..write(obj.isFullyReturned)
      ..writeByte(15)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PurchaseAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
