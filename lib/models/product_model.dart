// lib/models/product_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class Product {
  final String id;

  String name;

  String category;

  double price;

  /// الكمية: عدد القطع أو الوزن/الحجم (كغ/لتر) حسب الوحدة.
  double quantity;

  String? description;

  DateTime createdAt;

  DateTime updatedAt;

  String? barcode;

  bool isSynced;

  String userId;

  int minStockLevel;

  /// ⭐ سعر الشراء (التكلفة). null يعني «غير محدد».
  /// نُبقيه nullable حتى تقرأ السجلات القديمة (بلا الحقل 12) بأمان،
  /// ويُحدَّث تلقائياً إلى تكلفة آخر عملية شراء لهذا المنتج.
  double? costPrice;

  /// ⭐ وحدة البيع: 'piece' | 'kg' | 'litre'
  String unit;

  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.quantity,
    this.description,
    this.barcode,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isSynced = false,
    required this.userId,
    this.minStockLevel = 10,
    this.costPrice,
    this.unit = 'piece',
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// التكلفة كرقم للحسابات (غير المحدد = 0).
  double get costOrZero => costPrice ?? 0.0;

  /// هل للمنتج تكلفة شراء محددة؟
  bool get hasCost => (costPrice ?? 0) > 0;

  /// منتج يُباع بالوزن/الحجم وليس بالقطعة؟
  bool get isWeighted => unit != 'piece';

  // ⭐ من Firestore إلى Product - مع إصلاح تحويل Timestamp
  factory Product.fromFirestore(DocumentSnapshot doc) {
    return Product.fromMap(doc.id, doc.data() as Map<String, dynamic>);
  }

  /// يبني Product من Map مستخرجة من Firestore (اختبارها أسهل من DocumentSnapshot).
  factory Product.fromMap(String id, Map<String, dynamic> data) {
    // ⭐ دالة مساعدة لتحويل Timestamp إلى DateTime
    DateTime? parseTimestamp(dynamic value) {
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

    final createdAtValue = data['created_at'];
    final updatedAtValue = data['updated_at'];

    return Product(
      id: id,
      name: data['name'] as String? ?? '',
      category: data['category'] as String? ?? 'General',
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0.0,
      description: data['description'] as String?,
      barcode: data['barcode'] as String?,
      createdAt: parseTimestamp(createdAtValue) ?? DateTime.now(),
      updatedAt: parseTimestamp(updatedAtValue) ?? DateTime.now(),
      isSynced: true,
      userId: data['user_id'] as String? ?? '',
      minStockLevel: (data['min_stock_level'] as num?)?.toInt() ?? 10,
      costPrice: (data['cost_price'] as num?)?.toDouble(),
      unit: data['unit'] as String? ?? 'piece',
    );
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      price: (json['price'] as num).toDouble(),
      quantity: (json['quantity'] as num).toDouble(),
      description: json['description'] as String?,
      barcode: json['barcode'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      isSynced: true,
      userId: json['user_id'] as String,
      minStockLevel: (json['min_stock_level'] as num?)?.toInt() ?? 10,
      costPrice: (json['cost_price'] as num?)?.toDouble(),
      unit: json['unit'] as String? ?? 'piece',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'price': price,
      'quantity': quantity,
      'description': description,
      'barcode': barcode,
      'user_id': userId,
      'min_stock_level': minStockLevel,
      'cost_price': costPrice,
      'unit': unit,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
