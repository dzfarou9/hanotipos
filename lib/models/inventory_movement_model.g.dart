// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inventory_movement_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class InventoryMovementAdapter extends TypeAdapter<InventoryMovement> {
  @override
  final int typeId = 4;

  @override
  InventoryMovement read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InventoryMovement(
      id: fields[0] as String,
      productId: fields[1] as String,
      productName: fields[2] as String,
      type: fields[3] as MovementType,
      quantity: fields[4] as int,
      price: fields[5] as double,
      total: fields[6] as double,
      referenceId: fields[7] as String?,
      referenceNumber: fields[8] as String?,
      note: fields[9] as String?,
      createdAt: fields[10] as DateTime?,
      userId: fields[11] as String,
      status: fields[12] as MovementStatus,
      isSynced: fields[13] as bool,
      customerName: fields[14] as String?,
      supplierName: fields[15] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, InventoryMovement obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.productId)
      ..writeByte(2)
      ..write(obj.productName)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.quantity)
      ..writeByte(5)
      ..write(obj.price)
      ..writeByte(6)
      ..write(obj.total)
      ..writeByte(7)
      ..write(obj.referenceId)
      ..writeByte(8)
      ..write(obj.referenceNumber)
      ..writeByte(9)
      ..write(obj.note)
      ..writeByte(10)
      ..write(obj.createdAt)
      ..writeByte(11)
      ..write(obj.userId)
      ..writeByte(12)
      ..write(obj.status)
      ..writeByte(13)
      ..write(obj.isSynced)
      ..writeByte(14)
      ..write(obj.customerName)
      ..writeByte(15)
      ..write(obj.supplierName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryMovementAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
