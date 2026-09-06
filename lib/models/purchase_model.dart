// lib/models/purchase_model.dart

import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'purchase_model.g.dart';

@HiveType(typeId: 6)
class PurchaseItem {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String productId;

  @HiveField(2)
  final String productName;

  @HiveField(3)
  final double costPrice;

  @HiveField(4)
  final int quantity;

  @HiveField(5)
  final double subtotal;

  PurchaseItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.costPrice,
    required this.quantity,
    required this.subtotal,
  });

  factory PurchaseItem.fromJson(Map<String, dynamic> json) {
    return PurchaseItem(
      id: json['id'] ?? '',
      productId: json['product_id'] ?? '',
      productName: json['product_name'] ?? '',
      costPrice: (json['cost_price'] as num?)?.toDouble() ?? 0.0,
      quantity: json['quantity'] ?? 0,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'product_name': productName,
      'cost_price': costPrice,
      'quantity': quantity,
      'subtotal': subtotal,
    };
  }
}

@HiveType(typeId: 7)
class Purchase extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final List<PurchaseItem> items;

  @HiveField(2)
  final String supplierId;

  @HiveField(3)
  final String supplierName;

  @HiveField(4)
  final double total;

  @HiveField(5)
  final String? note;

  // 'purchase' أو 'return'
  @HiveField(6)
  final String purchaseType;

  @HiveField(7)
  final String? originalPurchaseId;

  @HiveField(8)
  final String userId;

  @HiveField(9)
  bool isSynced;

  @HiveField(10)
  final DateTime createdAt;

  // رقم فاتورة المورد (اختياري)
  @HiveField(11)
  final String? invoiceNumber;

  // ⭐ المرتجعات داخل نفس السجل (نمط Sale): الأصناف المرتجعة
  @HiveField(12)
  final List<PurchaseItem>? returnedItems;

  @HiveField(13)
  final double? returnTotal;

  @HiveField(14)
  final bool isFullyReturned;

  // للسحب التزايدي التحديثي (LWW)
  @HiveField(15)
  final DateTime updatedAt;

  Purchase({
    required this.id,
    required this.items,
    required this.supplierId,
    required this.supplierName,
    required this.total,
    this.note,
    this.purchaseType = 'purchase',
    this.originalPurchaseId,
    required this.userId,
    this.isSynced = false,
    DateTime? createdAt,
    this.invoiceNumber,
    this.returnedItems,
    this.returnTotal,
    this.isFullyReturned = false,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isReturn => purchaseType == 'return';

  bool get canBeReturned => !isReturn && !isFullyReturned;

  // الصافي بعد الإرجاع
  double get remainingTotal {
    if (returnTotal == null) return total;
    return total - returnTotal!;
  }

  // المتاح للإرجاع لكل صنف: المشترى − المرتجع المحفوظ − مرتجعات قديمة مستقلة
  List<PurchaseItem> availableForReturn(
      {Map<String, int> extraReturned = const {}}) {
    final returned = <String, int>{};
    for (final item in returnedItems ?? const <PurchaseItem>[]) {
      returned[item.productId] = (returned[item.productId] ?? 0) + item.quantity;
    }
    extraReturned.forEach((productId, qty) {
      returned[productId] = (returned[productId] ?? 0) + qty;
    });

    final available = <PurchaseItem>[];
    for (final item in items) {
      final already = returned[item.productId] ?? 0;
      final remaining = item.quantity - already;
      if (remaining > 0) {
        available.add(PurchaseItem(
          id: item.id,
          productId: item.productId,
          productName: item.productName,
          costPrice: item.costPrice,
          quantity: remaining,
          subtotal: item.costPrice * remaining,
        ));
      }
    }
    return available;
  }

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

  factory Purchase.fromJson(Map<String, dynamic> json) {
    final items = (json['purchase_items'] as List?)
            ?.map((e) => PurchaseItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    final returnedItems = (json['returned_items'] as List?)
        ?.map((e) => PurchaseItem.fromJson(e as Map<String, dynamic>))
        .toList();

    final createdAt = _parseTimestamp(json['created_at']) ?? DateTime.now();

    return Purchase(
      id: json['id'] as String,
      items: items,
      supplierId: json['supplier_id'] as String? ?? '',
      supplierName: json['supplier_name'] as String? ?? '',
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      note: json['note'] as String?,
      purchaseType: json['purchase_type'] as String? ?? 'purchase',
      originalPurchaseId: json['original_purchase_id'] as String?,
      userId: json['user_id'] as String? ?? '',
      isSynced: true,
      createdAt: createdAt,
      invoiceNumber: json['invoice_number'] as String?,
      returnedItems: returnedItems,
      returnTotal: (json['return_total'] as num?)?.toDouble(),
      isFullyReturned: json['is_fully_returned'] as bool? ?? false,
      updatedAt: _parseTimestamp(json['updated_at']) ?? createdAt,
    );
  }

  factory Purchase.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final fixed = data.map((k, v) => MapEntry(k, v is Timestamp ? v.toDate().toIso8601String() : v));
    // ⭐ عناصر Firestore المتداخلة تصل كـ Map<dynamic, dynamic>؛ نطبّعها
    // قبل fromJson حتى لا يفشل التحويل داخل PurchaseItem.fromJson.
    final normalized = <String, dynamic>{...fixed, 'id': doc.id};
    for (final key in ['purchase_items', 'returned_items']) {
      final list = normalized[key] as List?;
      if (list != null) {
        normalized[key] =
            list.map((e) => e is Map ? Map<String, dynamic>.from(e) : e).toList();
      }
    }
    return Purchase.fromJson(normalized);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'total': total,
      'note': note,
      'purchase_type': purchaseType,
      'original_purchase_id': originalPurchaseId,
      'user_id': userId,
      'created_at': createdAt.toIso8601String(),
      'invoice_number': invoiceNumber,
      'returned_items': returnedItems?.map((e) => e.toJson()).toList(),
      'return_total': returnTotal,
      'is_fully_returned': isFullyReturned,
      'updated_at': updatedAt.toIso8601String(),
      'purchase_items': items.map((e) => e.toJson()).toList(),
    };
  }
}
