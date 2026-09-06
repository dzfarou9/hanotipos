// lib/models/inventory_movement_enum_adapters.dart

// Adapters مكتوبة يدوياً لأن hive_generator يفشل على الenums مع
// نسخة الأدوات الحالية ("MovementType does not have any enum value").
// معرفات الأنواع 20 و21 غير مستخدمة في أي @HiveType آخر.

import 'package:hive/hive.dart';

import 'inventory_movement_model.dart';

class MovementTypeAdapter extends TypeAdapter<MovementType> {
  @override
  final int typeId = 20;

  @override
  MovementType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return MovementType.outgoing;
      case 1:
        return MovementType.incoming;
      case 2:
        return MovementType.return_in;
      case 3:
        return MovementType.return_out;
      case 4:
        return MovementType.adjustment;
      default:
        return MovementType.outgoing;
    }
  }

  @override
  void write(BinaryWriter writer, MovementType obj) {
    switch (obj) {
      case MovementType.outgoing:
        writer.writeByte(0);
      case MovementType.incoming:
        writer.writeByte(1);
      case MovementType.return_in:
        writer.writeByte(2);
      case MovementType.return_out:
        writer.writeByte(3);
      case MovementType.adjustment:
        writer.writeByte(4);
    }
  }
}

class MovementStatusAdapter extends TypeAdapter<MovementStatus> {
  @override
  final int typeId = 21;

  @override
  MovementStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return MovementStatus.pending;
      case 1:
        return MovementStatus.completed;
      case 2:
        return MovementStatus.cancelled;
      default:
        return MovementStatus.completed;
    }
  }

  @override
  void write(BinaryWriter writer, MovementStatus obj) {
    switch (obj) {
      case MovementStatus.pending:
        writer.writeByte(0);
      case MovementStatus.completed:
        writer.writeByte(1);
      case MovementStatus.cancelled:
        writer.writeByte(2);
    }
  }
}
