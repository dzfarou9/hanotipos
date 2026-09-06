// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sale_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

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
      price: fields[3] as double,
      quantity: fields[4] as int,
      subtotal: fields[5] as double,
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
      subtotal: fields[2] as double,
      discount: fields[3] as double,
      tax: fields[4] as double,
      total: fields[5] as double,
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
      returnTotal: fields[15] as double?,
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
