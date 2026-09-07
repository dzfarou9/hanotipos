// lib/models/sale_model.dart

import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../helpers/quantity_format.dart';

class SaleItem {
  final String id;

  final String productId;

  final String productName;

  final double price;

  final double quantity;

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
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
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

class Sale extends HiveObject {
  final String id;

  final List<SaleItem> items;

  final double subtotal;

  final double discount;

  final double tax;

  final double total;

  final String paymentMethod;

  final DateTime createdAt;

  bool isSynced;

  final String userId;

  final String? customerName;

  final String? customerPhone;

  // ⭐ حقل جديد: نوع العملية (بيع عادي أو مرتجع)
  final String saleType; // 'sale', 'return'

  // ⭐ حقل جديد: مرجع للمبيعة الأصلية في حالة المرتجع
  final String? originalSaleId;

  // ⭐⭐⭐ حقول جديدة للمرتجعات (بدلاً من إنشاء Sale جديدة)
  // ⭐ المنتجات المرتجعة من هذه المبيعة
  final List<SaleItem>? returnedItems;

  // ⭐ إجمالي قيمة المرتجعات
  final double? returnTotal;

  // ⭐ هل تم إرجاع كل المنتجات؟
  final bool isFullyReturned;

  /// معرّف العميل — يُملأ في مبيعات الدين وعند ربط العميل اختيارياً.
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
    if (returnedItems == null || returnedItems!.isEmpty) return true;
    final totalOriginal =
        items.fold(0.0, (sum, item) => sum + item.quantity);
    final totalReturned =
        returnedItems!.fold(0.0, (sum, item) => sum + item.quantity);
    return !QuantityFormat.exceedsQty(totalReturned, totalOriginal) &&
        !QuantityFormat.isZeroQty(totalOriginal - totalReturned);
  }

  // ⭐ الحصول على المنتجات التي لم يتم إرجاعها بعد
  List<SaleItem> get availableForReturn {
    if (returnedItems == null || returnedItems!.isEmpty) {
      return items;
    }

    final Map<String, double> returnedQuantities = {};
    for (var item in returnedItems!) {
      returnedQuantities[item.productId] =
          (returnedQuantities[item.productId] ?? 0.0) + item.quantity;
    }

    final List<SaleItem> available = [];
    for (var item in items) {
      final returnedQty = returnedQuantities[item.productId] ?? 0.0;
      if (QuantityFormat.greaterThanQty(item.quantity, returnedQty)) {
        final remainder = item.quantity - returnedQty;
        available.add(SaleItem(
          id: item.id,
          productId: item.productId,
          productName: item.productName,
          price: item.price,
          quantity: remainder,
          subtotal: item.price * remainder,
        ));
      }
    }
    return available;
  }
}
