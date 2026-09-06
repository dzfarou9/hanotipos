// lib/models/product_model.dart

import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'product_model.g.dart';

@HiveType(typeId: 0)
class Product extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String category;

  @HiveField(3)
  double price;

  @HiveField(4)
  int quantity;

  @HiveField(5)
  String? description;

  @HiveField(6)
  DateTime createdAt;

  @HiveField(7)
  DateTime updatedAt;

  @HiveField(8)
  String? barcode;

  @HiveField(9)
  bool isSynced;

  @HiveField(10)
  String userId;

  @HiveField(11)
  int minStockLevel;

  /// ⭐ سعر الشراء (التكلفة). null يعني «غير محدد».
  /// نُبقيه nullable حتى تقرأ السجلات القديمة (بلا الحقل 12) بأمان،
  /// ويُحدَّث تلقائياً إلى تكلفة آخر عملية شراء لهذا المنتج.
  @HiveField(12)
  double? costPrice;

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
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// التكلفة كرقم للحسابات (غير المحدد = 0).
  double get costOrZero => costPrice ?? 0.0;

  /// هل للمنتج تكلفة شراء محددة؟
  bool get hasCost => (costPrice ?? 0) > 0;

  // ⭐ من Firestore إلى Product - مع إصلاح تحويل Timestamp
  factory Product.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

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
      id: doc.id,
      name: data['name'] as String? ?? '',
      category: data['category'] as String? ?? 'General',
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      quantity: data['quantity'] as int? ?? 0,
      description: data['description'] as String?,
      barcode: data['barcode'] as String?,
      createdAt: parseTimestamp(createdAtValue) ?? DateTime.now(),
      updatedAt: parseTimestamp(updatedAtValue) ?? DateTime.now(),
      isSynced: true,
      userId: data['user_id'] as String? ?? '',
      minStockLevel: (data['min_stock_level'] as num?)?.toInt() ?? 10,
      costPrice: (data['cost_price'] as num?)?.toDouble(),
    );
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      price: (json['price'] as num).toDouble(),
      quantity: json['quantity'] as int,
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
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
