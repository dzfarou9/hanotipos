// lib/models/debt_transaction_enum_adapter.dart

// Adapter مكتوب يدوياً لأن hive_generator يفشل على الenums مع
// نسخة الأدوات الحالية. معرّف النوع 22 غير مستخدم في أي @HiveType آخر.

import 'package:hive/hive.dart';

import 'debt_transaction_model.dart';

class DebtTransactionTypeAdapter extends TypeAdapter<DebtTransactionType> {
  @override
  final int typeId = 22;

  @override
  DebtTransactionType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return DebtTransactionType.debt;
      case 1:
        return DebtTransactionType.payment;
      case 2:
        return DebtTransactionType.adjustment;
      default:
        return DebtTransactionType.debt;
    }
  }

  @override
  void write(BinaryWriter writer, DebtTransactionType obj) {
    switch (obj) {
      case DebtTransactionType.debt:
        writer.writeByte(0);
      case DebtTransactionType.payment:
        writer.writeByte(1);
      case DebtTransactionType.adjustment:
        writer.writeByte(2);
    }
  }
}
