// lib/models/sale_model.dart

import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'sale_model.g.dart';

@HiveType(typeId: 2)
class SaleItem {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String productId;

  @HiveField(2)
  final String productName;

  @HiveField(3)
  final double price;

  @HiveField(4)
  final int quantity;

  @HiveField(5)
  final double subtotal;

  SaleItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    required this.subtotal,
  });

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      id: json['id'] ?? '',
      productId: json['product_id'] ?? '',
      productName: json['product_name'] ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      quantity: json['quantity'] ?? 0,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'product_name': productName,
      'price': price,
      'quantity': quantity,
      'subtotal': subtotal,
    };
  }
}

@HiveType(typeId: 3)
class Sale extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final List<SaleItem> items;

  @HiveField(2)
  final double subtotal;

  @HiveField(3)
  final double discount;

  @HiveField(4)
  final double tax;

  @HiveField(5)
  final double total;

  @HiveField(6)
  final String paymentMethod;

  @HiveField(7)
  final DateTime createdAt;

  @HiveField(8)
  bool isSynced;

  @HiveField(9)
  final String userId;

  @HiveField(10)
  final String? customerName;

  @HiveField(11)
  final String? customerPhone;

  // ⭐ حقل جديد: نوع العملية (بيع عادي أو مرتجع)
  @HiveField(12)
  final String saleType; // 'sale', 'return'

  // ⭐ حقل جديد: مرجع للمبيعة الأصلية في حالة المرتجع
  @HiveField(13)
  final String? originalSaleId;

  // ⭐⭐⭐ حقول جديدة للمرتجعات (بدلاً من إنشاء Sale جديدة)
  // ⭐ المنتجات المرتجعة من هذه المبيعة
  @HiveField(14)
  final List<SaleItem>? returnedItems;

  // ⭐ إجمالي قيمة المرتجعات
  @HiveField(15)
  final double? returnTotal;

  // ⭐ هل تم إرجاع كل المنتجات؟
  @HiveField(16)
  final bool isFullyReturned;

  /// معرّف العميل — يُملأ في مبيعات الدين وعند ربط العميل اختيارياً.
  @HiveField(17)
  final String? customerId;

  Sale({
    required this.id,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.paymentMethod,
    DateTime? createdAt,
    this.isSynced = false,
    required this.userId,
    this.customerName,
    this.customerPhone,
    this.customerId,
    this.saleType = 'sale',
    this.originalSaleId,
    this.returnedItems,
    this.returnTotal,
    this.isFullyReturned = false,
  }) : createdAt = createdAt ?? DateTime.now();

  // ⭐ دالة مساعدة لتحويل Timestamp إلى DateTime
  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return null;
      }
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  factory Sale.fromJson(Map<String, dynamic> json) {
    final items = (json['sale_items'] as List?)
            ?.map((item) => SaleItem.fromJson(item as Map<String, dynamic>))
            .toList() ??
        [];

    final returnedItems = (json['returned_items'] as List?)
            ?.map((item) => SaleItem.fromJson(item as Map<String, dynamic>))
            .toList() ??
        null;

    // ⭐ تحويل created_at من Timestamp أو String
    final createdAtValue = json['created_at'];
    final createdAt = _parseTimestamp(createdAtValue) ?? DateTime.now();

    return Sale(
      id: json['id'] as String,
      items: items,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0.0,
      tax: (json['tax'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: json['payment_method'] as String? ?? 'Cash',
      createdAt: createdAt,
      isSynced: true,
      userId: json['user_id'] as String,
      customerName: json['customer_name'] as String?,
      customerPhone: json['customer_phone'] as String?,
      customerId: json['customer_id'] as String?,
      saleType: json['sale_type'] as String? ?? 'sale',
      originalSaleId: json['original_sale_id'] as String?,
      returnedItems: returnedItems,
      returnTotal: (json['return_total'] as num?)?.toDouble(),
      isFullyReturned: json['is_fully_returned'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'subtotal': subtotal,
      'discount': discount,
      'tax': tax,
      'total': total,
      'payment_method': paymentMethod,
      'user_id': userId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_id': customerId,
      'sale_type': saleType,
      'original_sale_id': originalSaleId,
      'returned_items': returnedItems?.map((item) => item.toJson()).toList(),
      'return_total': returnTotal,
      'is_fully_returned': isFullyReturned,
      'created_at': createdAt.toIso8601String(),
      'sale_items': items.map((item) => item.toJson()).toList(),
    };
  }

  bool get isReturn => saleType == 'return';

  bool get isReturned =>
      isReturn || isFullyReturned || (returnedItems?.isNotEmpty ?? false);

  // ⭐ حساب المبلغ المتبقي (الإجمالي - المرتجع)
  double get remainingTotal {
    if (returnTotal == null) return total;
    return total - returnTotal!;
  }

  // ⭐ هل يمكن إرجاع منتجات من هذه المبيعة؟
  bool get canReturn {
    if (isReturn) return false;
    if (isFullyReturned) return false;
    if (returnedItems == null) return true;
    // تحقق إذا كانت جميع المنتجات قد تم إرجاعها
    final totalOriginalQuantity =
        items.fold(0, (sum, item) => sum + item.quantity);
    final totalReturnedQuantity =
        returnedItems!.fold(0, (sum, item) => sum + item.quantity);
    return totalReturnedQuantity < totalOriginalQuantity;
  }

  // ⭐ الحصول على المنتجات التي لم يتم إرجاعها بعد
  List<SaleItem> get availableForReturn {
    if (returnedItems == null || returnedItems!.isEmpty) {
      return items;
    }

    final Map<String, int> returnedQuantities = {};
    for (var item in returnedItems!) {
      returnedQuantities[item.productId] =
          (returnedQuantities[item.productId] ?? 0) + item.quantity;
    }

    final List<SaleItem> available = [];
    for (var item in items) {
      final returnedQty = returnedQuantities[item.productId] ?? 0;
      if (item.quantity > returnedQty) {
        available.add(SaleItem(
          id: item.id,
          productId: item.productId,
          productName: item.productName,
          price: item.price,
          quantity: item.quantity - returnedQty,
          subtotal: item.price * (item.quantity - returnedQty),
        ));
      }
    }
    return available;
  }
}
