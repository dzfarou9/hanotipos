// lib/models/inventory_movement_model.dart

import 'package:hive/hive.dart';

part 'inventory_movement_model.g.dart';

/// نوع حركة المخزون
// ملاحظة: الenums تُخزَّن عبر adapters مكتوبة يدوياً في
// inventory_movement_enum_adapters.dart لأن hive_generator لا يدعمها
// مع نسخة الأدوات الحالية — لا تضف @HiveType هنا وإلا فشل build_runner.
enum MovementType {
  /// صادر (بيع)
  outgoing,

  /// وارد (شراء/توريد)
  incoming,

  /// مرتجع (من عميل)
  return_in,

  /// مرتجع (لمورد)
  return_out,

  /// تعديل يدوي
  adjustment,
}

/// حالة حركة المخزون
enum MovementStatus {
  pending,
  completed,
  cancelled,
}

@HiveType(typeId: 4)
class InventoryMovement extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String productId;

  @HiveField(2)
  final String productName;

  @HiveField(3)
  final MovementType type;

  @HiveField(4)
  final int quantity;

  @HiveField(5)
  final double price;

  @HiveField(6)
  final double total;

  @HiveField(7)
  final String? referenceId;

  @HiveField(8)
  final String? referenceNumber;

  @HiveField(9)
  final String? note;

  @HiveField(10)
  final DateTime createdAt;

  @HiveField(11)
  final String userId;

  @HiveField(12)
  MovementStatus status;

  @HiveField(13)
  bool isSynced;

  @HiveField(14)
  final String? customerName;

  @HiveField(15)
  final String? supplierName;

  InventoryMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.type,
    required this.quantity,
    required this.price,
    required this.total,
    this.referenceId,
    this.referenceNumber,
    this.note,
    DateTime? createdAt,
    required this.userId,
    this.status = MovementStatus.completed,
    this.isSynced = false,
    this.customerName,
    this.supplierName,
  }) : createdAt = createdAt ?? DateTime.now();

  /// تحويل من JSON (من Supabase)
  factory InventoryMovement.fromJson(Map<String, dynamic> json) {
    return InventoryMovement(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      productName: json['product_name'] as String,
      type: _parseMovementType(json['type'] as String),
      quantity: json['quantity'] as int,
      price: (json['price'] as num).toDouble(),
      total: (json['total'] as num).toDouble(),
      referenceId: json['reference_id'] as String?,
      referenceNumber: json['reference_number'] as String?,
      note: json['note'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      userId: json['user_id'] as String,
      status: _parseMovementStatus(json['status'] as String? ?? 'completed'),
      isSynced: true,
      customerName: json['customer_name'] as String?,
      supplierName: json['supplier_name'] as String?,
    );
  }

  /// تحويل إلى JSON (إلى Supabase)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'product_name': productName,
      'type': _movementTypeToString(type),
      'quantity': quantity,
      'price': price,
      'total': total,
      'reference_id': referenceId,
      'reference_number': referenceNumber,
      'note': note,
      'user_id': userId,
      'status': _movementStatusToString(status),
      'customer_name': customerName,
      'supplier_name': supplierName,
      'created_at': createdAt.toIso8601String(),
    };
  }

  static MovementType _parseMovementType(String value) {
    switch (value) {
      case 'outgoing':
        return MovementType.outgoing;
      case 'incoming':
        return MovementType.incoming;
      case 'return_in':
        return MovementType.return_in;
      case 'return_out':
        return MovementType.return_out;
      case 'adjustment':
        return MovementType.adjustment;
      default:
        return MovementType.outgoing;
    }
  }

  static String _movementTypeToString(MovementType type) {
    switch (type) {
      case MovementType.outgoing:
        return 'outgoing';
      case MovementType.incoming:
        return 'incoming';
      case MovementType.return_in:
        return 'return_in';
      case MovementType.return_out:
        return 'return_out';
      case MovementType.adjustment:
        return 'adjustment';
    }
  }

  static MovementStatus _parseMovementStatus(String value) {
    switch (value) {
      case 'pending':
        return MovementStatus.pending;
      case 'completed':
        return MovementStatus.completed;
      case 'cancelled':
        return MovementStatus.cancelled;
      default:
        return MovementStatus.completed;
    }
  }

  static String _movementStatusToString(MovementStatus status) {
    switch (status) {
      case MovementStatus.pending:
        return 'pending';
      case MovementStatus.completed:
        return 'completed';
      case MovementStatus.cancelled:
        return 'cancelled';
    }
  }

  /// الحصول على التأثير على المخزون (موجب أو سالب)
  int getStockEffect() {
    switch (type) {
      case MovementType.outgoing:
      case MovementType.return_out:
        return -quantity;
      case MovementType.incoming:
      case MovementType.return_in:
        return quantity;
      case MovementType.adjustment:
        return quantity;
    }
  }
}
