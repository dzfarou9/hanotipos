// lib/models/debt_transaction_model.dart

import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'debt_transaction_model.g.dart';

// ⭐ لا تضف @HiveType على هذا enum — hive_generator يفشل عليه.
// المحوّل مكتوب يدوياً في debt_transaction_enum_adapter.dart (typeId 22).
enum DebtTransactionType { debt, payment, adjustment }

@HiveType(typeId: 9)
class DebtTransaction extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String customerId;

  @HiveField(2)
  final DebtTransactionType type;

  /// موقّع: دين > 0، دفعة < 0، تسوية أي إشارة.
  @HiveField(3)
  final double amount;

  @HiveField(4)
  final String? saleId;

  @HiveField(5)
  final String? note;

  @HiveField(6)
  final String userId;

  @HiveField(7)
  bool isSynced;

  @HiveField(8)
  final DateTime createdAt;

  @HiveField(9)
  DateTime updatedAt;

  DebtTransaction({
    required this.id,
    required this.customerId,
    required this.type,
    required this.amount,
    this.saleId,
    this.note,
    required this.userId,
    this.isSynced = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    if (value is DateTime) return value;
    return null;
  }

  static DebtTransactionType parseType(String value) {
    switch (value) {
      case 'payment':
        return DebtTransactionType.payment;
      case 'adjustment':
        return DebtTransactionType.adjustment;
      default:
        return DebtTransactionType.debt;
    }
  }

  factory DebtTransaction.fromJson(Map<String, dynamic> json) {
    return DebtTransaction(
      id: json['id'] as String,
      customerId: json['customer_id'] as String? ?? '',
      type: parseType(json['type'] as String? ?? 'debt'),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      saleId: json['sale_id'] as String?,
      note: json['note'] as String?,
      userId: json['user_id'] as String? ?? '',
      isSynced: true,
      createdAt: _parseTimestamp(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseTimestamp(json['updated_at']) ?? DateTime.now(),
    );
  }

  factory DebtTransaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DebtTransaction.fromJson({...data, 'id': doc.id, 'is_synced': true});
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_id': customerId,
      'type': type.name,
      'amount': amount,
      'sale_id': saleId,
      'note': note,
      'user_id': userId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
