// lib/models/purchase_model.dart

import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../helpers/quantity_format.dart';

class PurchaseItem {
  final String id;

  final String productId;

  final String productName;

  final double costPrice;

  /// الكمية: عدد القطع أو الوزن/الحجم (كغ/لتر) حسب وحدة المنتج.
  final double quantity;

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
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
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

class Purchase extends HiveObject {
  final String id;

  final List<PurchaseItem> items;

  final String supplierId;

  final String supplierName;

  final double total;

  final String? note;

  // 'purchase' أو 'return'
  final String purchaseType;

  final String? originalPurchaseId;

  final String userId;

  bool isSynced;

  final DateTime createdAt;

  // رقم فاتورة المورد (اختياري)
  final String? invoiceNumber;

  // ⭐ المرتجعات داخل نفس السجل (نمط Sale): الأصناف المرتجعة
  final List<PurchaseItem>? returnedItems;

  final double? returnTotal;

  final bool isFullyReturned;

  // للسحب التزايدي التحديثي (LWW)
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
      {Map<String, double> extraReturned = const {}}) {
    final returned = <String, double>{};
    for (final item in returnedItems ?? const <PurchaseItem>[]) {
      returned[item.productId] =
          (returned[item.productId] ?? 0.0) + item.quantity;
    }
    extraReturned.forEach((productId, qty) {
      returned[productId] = (returned[productId] ?? 0.0) + qty;
    });

    final available = <PurchaseItem>[];
    for (final item in items) {
      final already = returned[item.productId] ?? 0.0;
      final remaining = item.quantity - already;
      if (QuantityFormat.greaterThanQty(remaining, 0)) {
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
