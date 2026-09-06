// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'debt_transaction_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DebtTransactionAdapter extends TypeAdapter<DebtTransaction> {
  @override
  final int typeId = 9;

  @override
  DebtTransaction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DebtTransaction(
      id: fields[0] as String,
      customerId: fields[1] as String,
      type: fields[2] as DebtTransactionType,
      amount: fields[3] as double,
      saleId: fields[4] as String?,
      note: fields[5] as String?,
      userId: fields[6] as String,
      isSynced: fields[7] as bool,
      createdAt: fields[8] as DateTime?,
      updatedAt: fields[9] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, DebtTransaction obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.customerId)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.amount)
      ..writeByte(4)
      ..write(obj.saleId)
      ..writeByte(5)
      ..write(obj.note)
      ..writeByte(6)
      ..write(obj.userId)
      ..writeByte(7)
      ..write(obj.isSynced)
      ..writeByte(8)
      ..write(obj.createdAt)
      ..writeByte(9)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DebtTransactionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
