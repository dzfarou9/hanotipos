# نظام الموردين والمشتريات — خطة التنفيذ

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** إضافة نظام موردين كامل Offline First: إدارة موردون، شراء يرفع المخزون، إرجاع ينقصه، حذف يعكس الأثر، مزامنة Firebase + Hive.

**Architecture:** نفس نمط المشروع الحالي — نماذج Hive مع `isSynced`، كتابة محلية أولاً ثم رفع مباشر عند الاتصال (write-through)، رفع Batch للمعلّق، سحب تزايدي بـ `updated_at/created_at`، Tombstones للحذف. المرتجع سجل `Purchase` مستقل بنوع `'return'` يشير للأصلية بـ `originalPurchaseId`.

**Tech Stack:** Flutter, Hive (مشفّر), Cloud Firestore, easy_localization, google_mlkit_barcode_scanning (موجودة كلها — لا اعتماديات جديدة).

**Spec:** `docs/superpowers/specs/2026-08-25-suppliers-purchases-design.md`

## Global Constraints

- Dart SDK: `>=3.1.0 <4.0.0` (من pubspec.yaml)
- TypeIds الجديدة إلزامياً: Supplier=`5`, PurchaseItem=`6`, Purchase=`7` (المستخدمة: 0,1,2,3,4)
- مفاتيح JSON بنمط snake_case (`user_id`, `created_at`, `supplier_id`, `cost_price`, `purchase_type`, `original_purchase_id`)
- Offline First دائماً: حفظ في Hive أولاً بـ `isSynced = false`، ثم محاولة Firebase إذا `_isOnline && _firebase.currentUser != null`؛ الفشل لا يرمي استثناءً للمستخدم
- لا كميات سالبة أبداً؛ الإرجاع محدود بأصناف الشراء الأصلي فقط
- التعليقات بالعربية بنفس أسلوب الكود الموجود، ومقتضبة
- اسم المشروع في الاستيرادات: `package:pos_app/...`
- توليد مهايئات Hive بعد أي تعديل نماذج: `flutter pub run build_runner build --delete-conflicting-outputs`
- التحقق الدائم قبل كل commit: `flutter analyze` بدون أخطاء جديدة

---

### Task 1: النماذج — Supplier و Purchase و PurchaseItem

**Files:**
- Create: `lib/models/supplier_model.dart`
- Create: `lib/models/purchase_model.dart`
- Create (مولَّد): `lib/models/supplier_model.g.dart`, `lib/models/purchase_model.g.dart`
- Test: `test/models/supplier_purchase_model_test.dart`

**Interfaces:**
- Produces:
  - `Supplier(id, name, phone?, address?, notes?, userId, isSynced, createdAt, updatedAt)` + `fromJson/toJson`
  - `PurchaseItem(id, productId, productName, costPrice, quantity, subtotal)` + `fromJson/toJson`
  - `Purchase(id, items, supplierId, supplierName, total, note?, purchaseType='purchase', originalPurchaseId?, userId, isSynced=false, createdAt)` + `isReturn` getter + `fromJson/toJson`

- [ ] **Step 1: اكتب الاختبار الفاشل**

```dart
// test/models/supplier_purchase_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/purchase_model.dart';
import 'package:pos_app/models/supplier_model.dart';

void main() {
  group('Supplier JSON roundtrip', () {
    test('toJson then fromJson preserves fields', () {
      final now = DateTime(2026, 8, 25, 10);
      final supplier = Supplier(
        id: 's1',
        name: 'مورد الأمل',
        phone: '0555000111',
        address: 'الجزائر',
        notes: 'عميل ذهبي',
        userId: 'u1',
        isSynced: false,
        createdAt: now,
        updatedAt: now,
      );
      final restored = Supplier.fromJson(supplier.toJson());
      expect(restored.id, 's1');
      expect(restored.name, 'مورد الأمل');
      expect(restored.phone, '0555000111');
      expect(restored.address, 'الجزائر');
      expect(restored.notes, 'عميل ذهبي');
      expect(restored.userId, 'u1');
      expect(restored.createdAt, now);
    });

    test('fromJson tolerates null optionals', () {
      final map = {
        'id': 's2',
        'name': 'x',
        'user_id': 'u1',
        'created_at': '2026-01-01T00:00:00.000',
        'updated_at': '2026-01-01T00:00:00.000',
      };
      final s = Supplier.fromJson(map);
      expect(s.phone, isNull);
      expect(s.address, isNull);
      expect(s.notes, isNull);
    });
  });

  group('Purchase JSON roundtrip', () {
    test('purchase with items roundtrips', () {
      final purchase = Purchase(
        id: 'p1',
        supplierId: 's1',
        supplierName: 'مورد',
        items: [
          PurchaseItem(
            id: 'i1',
            productId: 'pr1',
            productName: 'سكر',
            costPrice: 100,
            quantity: 5,
            subtotal: 500,
          ),
        ],
        total: 500,
        note: 'دفعة أولى',
        userId: 'u1',
        createdAt: DateTime(2026, 8, 25),
      );
      final restored = Purchase.fromJson(purchase.toJson());
      expect(restored.id, 'p1');
      expect(restored.items.length, 1);
      expect(restored.items.first.costPrice, 100);
      expect(restored.total, 500);
      expect(restored.purchaseType, 'purchase');
      expect(restored.isReturn, isFalse);
      expect(restored.originalPurchaseId, isNull);
    });

    test('return purchase roundtrips with original reference', () {
      final ret = Purchase(
        id: 'r1',
        supplierId: 's1',
        supplierName: 'مورد',
        items: [
          PurchaseItem(
              id: 'i2',
              productId: 'pr1',
              productName: 'سكر',
              costPrice: 100,
              quantity: 2,
              subtotal: 200),
        ],
        total: 200,
        purchaseType: 'return',
        originalPurchaseId: 'p1',
        userId: 'u1',
      );
      final restored = Purchase.fromJson(ret.toJson());
      expect(restored.isReturn, isTrue);
      expect(restored.originalPurchaseId, 'p1');
    });
  });
}
```

- [ ] **Step 2: شغّل الاختبار وتأكد أنه فاشل**

Run: `flutter test test/models/supplier_purchase_model_test.dart`
Expected: FAIL — الملفات غير موجودة

- [ ] **Step 3: أنشئ نموذج Supplier**

```dart
// lib/models/supplier_model.dart

import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'supplier_model.g.dart';

@HiveType(typeId: 5)
class Supplier extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String? phone;

  @HiveField(3)
  String? address;

  @HiveField(4)
  String? notes;

  @HiveField(5)
  final String userId;

  @HiveField(6)
  bool isSynced;

  @HiveField(7)
  final DateTime createdAt;

  @HiveField(8)
  DateTime updatedAt;

  Supplier({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.notes,
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

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      notes: json['notes'] as String?,
      userId: json['user_id'] as String? ?? '',
      isSynced: true,
      createdAt: _parseTimestamp(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseTimestamp(json['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'notes': notes,
      'user_id': userId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
```

- [ ] **Step 4: أنشئ نموذج Purchase و PurchaseItem**

```dart
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
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isReturn => purchaseType == 'return';

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
      createdAt: _parseTimestamp(json['created_at']) ?? DateTime.now(),
    );
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
      'purchase_items': items.map((e) => e.toJson()).toList(),
    };
  }
}
```

- [ ] **Step 5: ولّد مهايئات Hive**

Run: `flutter pub run build_runner build --delete-conflicting-outputs`
Expected: BUILD SUCCEEDED ويظهر `supplier_model.g.dart` و `purchase_model.g.dart`

- [ ] **Step 6: شغّل الاختبار**

Run: `flutter test test/models/supplier_purchase_model_test.dart`
Expected: PASS

- [ ] **Step 7: تحقق واعمل commit**

Run: `flutter analyze`
Expected: No issues

```bash
git add lib/models/supplier_model.dart lib/models/purchase_model.dart lib/models/supplier_model.g.dart lib/models/purchase_model.g.dart test/models/supplier_purchase_model_test.dart
git commit -m "feat: add Supplier and Purchase models with Hive adapters"
```

---

### Task 2: منطق قواعد المخزون — SuppliersStockPolicy (TDD)

**Files:**
- Create: `lib/helpers/suppliers_stock_policy.dart`
- Test: `test/helpers/suppliers_stock_policy_test.dart`

**Interfaces:**
- Consumes: `PurchaseItem` من Task 1
- Produces (يستخدمها SyncService في Task 6):

```dart
abstract class SuppliersStockPolicy {
  // السقف المتاح للإرجاع لمنتج داخل شراء أصلي
  static int returnCap({required int purchasedQuantity, required int alreadyReturnedQuantity});
  // هل التعديل سيجعل الكمية سالبة؟
  static bool wouldGoNegative({required int currentQuantity, required int change}); // change سالب عادةً
  // يتحقق من صحة كميات مرتجع جديد ضد الشراء الأصلي؛ يعيد قائمة معرفات المنتجات المخالفة
  static List<String> invalidReturnProducts({required List<PurchaseItem> originalItems, required Map<String, int> returnedSoFarByProductId, required Map<String, int> newReturnByProductId});
}
```

- [ ] **Step 1: اكتب الاختبارات الفاشلة**

```dart
// test/helpers/suppliers_stock_policy_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/helpers/suppliers_stock_policy.dart';
import 'package:pos_app/models/purchase_model.dart';

PurchaseItem _item(String pid, int qty) => PurchaseItem(
    id: 'i-$pid', productId: pid, productName: 'n', costPrice: 1, quantity: qty, subtotal: qty);

void main() {
  group('returnCap', () {
    test('cap = purchased minus already returned', () {
      expect(SuppliersStockPolicy.returnCap(purchasedQuantity: 10, alreadyReturnedQuantity: 3), 7);
    });
    test('never below zero', () {
      expect(SuppliersStockPolicy.returnCap(purchasedQuantity: 5, alreadyReturnedQuantity: 9), 0);
    });
  });

  group('wouldGoNegative', () {
    test('true when decrease exceeds current stock', () {
      expect(SuppliersStockPolicy.wouldGoNegative(currentQuantity: 4, change: -5), isTrue);
    });
    test('false when enough stock', () {
      expect(SuppliersStockPolicy.wouldGoNegative(currentQuantity: 5, change: -5), isFalse);
    });
    test('increase never goes negative', () {
      expect(SuppliersStockPolicy.wouldGoNegative(currentQuantity: 0, change: 3), isFalse);
    });
  });

  group('invalidReturnProducts', () {
    test('valid when within caps', () {
      final result = SuppliersStockPolicy.invalidReturnProducts(
        originalItems: [_item('a', 10), _item('b', 4)],
        returnedSoFarByProductId: {'a': 2},
        newReturnByProductId: {'a': 8, 'b': 4},
      );
      expect(result, isEmpty);
    });
    test('flags product exceeding cap', () {
      final result = SuppliersStockPolicy.invalidReturnProducts(
        originalItems: [_item('a', 10)],
        returnedSoFarByProductId: {'a': 5},
        newReturnByProductId: {'a': 6},
      );
      expect(result, ['a']);
    });
    test('flags product not in original purchase', () {
      final result = SuppliersStockPolicy.invalidReturnProducts(
        originalItems: [_item('a', 10)],
        returnedSoFarByProductId: {},
        newReturnByProductId: {'zzz': 1},
      );
      expect(result, ['zzz']);
    });
  });
}
```

- [ ] **Step 2: شغّل وتأكد الفشل**

Run: `flutter test test/helpers/suppliers_stock_policy_test.dart`
Expected: FAIL — الملف غير موجود

- [ ] **Step 3: نفّذ السياسة**

```dart
// lib/helpers/suppliers_stock_policy.dart

import '../models/purchase_model.dart';

/// قواعد نقاء للمخزون: سقوف الإرجاع ومنع الكميات السالبة.
/// دوال ثابتة بدون حالة حتى تُختبر بسهولة.
abstract class SuppliersStockPolicy {
  /// السقف المتاح للإرجاع = المشترى − المرتجع سابقاً، ولا ينزل تحت الصفر.
  static int returnCap(
      {required int purchasedQuantity, required int alreadyReturnedQuantity}) {
    final cap = purchasedQuantity - alreadyReturnedQuantity;
    return cap < 0 ? 0 : cap;
  }

  /// هل تطبيق [change] على الكمية الحالية يجعلها سالبة؟
  static bool wouldGoNegative({required int currentQuantity, required int change}) {
    return currentQuantity + change < 0;
  }

  /// يتحقق من كميات مرتجع جديد ضد الشراء الأصلي.
  /// يعيد معرفات المنتجات التي تجاوزت سقفها أو ليست في الشراء الأصلي.
  static List<String> invalidReturnProducts({
    required List<PurchaseItem> originalItems,
    required Map<String, int> returnedSoFarByProductId,
    required Map<String, int> newReturnByProductId,
  }) {
    final caps = <String, int>{};
    for (final item in originalItems) {
      caps[item.productId] =
          (caps[item.productId] ?? 0) + item.quantity;
    }

    final invalid = <String>[];
    newReturnByProductId.forEach((productId, newQty) {
      if (newQty <= 0) return;
      final purchased = caps[productId];
      if (purchased == null) {
        invalid.add(productId);
        return;
      }
      final already = returnedSoFarByProductId[productId] ?? 0;
      if (newQty > returnCap(purchasedQuantity: purchased, alreadyReturnedQuantity: already)) {
        invalid.add(productId);
      }
    });
    return invalid;
  }
}
```

- [ ] **Step 4: شغّل الاختبار**

Run: `flutter test test/helpers/suppliers_stock_policy_test.dart`
Expected: PASS

- [ ] **Step 5: تحقق وcommit**

Run: `flutter analyze`

```bash
git add lib/helpers/suppliers_stock_policy.dart test/helpers/suppliers_stock_policy_test.dart
git commit -m "feat: add suppliers stock policy helpers"
```

---

### Task 3: تكامل DatabaseService — صناديق Hive وCRUD

**Files:**
- Modify: `lib/services/database_service.dart`

**Interfaces:**
- Consumes: `Supplier`, `Purchase`, `PurchaseItem` (Task 1)
- Produces (يستخدمها Tasks 4-6 والشاشات):

```dart
// Suppliers
List<Supplier> getAllSuppliers();                 // مرتبة بالاسم
Supplier? getSupplierById(String id);
bool supplierExists(String id);
List<Supplier> getUnsyncedSuppliers();
Future<void> addSupplierWithId({required String id, required String name, String? phone, String? address, String? notes, required String userId, bool isSynced = false});
Future<void> updateSupplier({required String id, required String name, String? phone, String? address, String? notes}); // يضبط isSynced=false
Future<void> deleteSupplierLocal(String id);
Future<void> markSupplierAsSynced(String id);

// Purchases
int getPurchaseCount();
List<Purchase> getAllPurchases();                 // تنازلي بالتاريخ
List<Purchase> getPurchasesBySupplier(String supplierId);
List<Purchase> getReturnPurchasesFor(String originalPurchaseId);
Purchase? getPurchaseById(String id);
List<Purchase> getUnsyncedPurchases();
Future<Purchase> addPurchaseWithId({required String id, required List<PurchaseItem> items, required String supplierId, required String supplierName, required double total, String? note, String purchaseType = 'purchase', String? originalPurchaseId, required String userId, bool isSynced = false, DateTime? createdAt});
Future<void> deletePurchaseLocal(String id);
Future<void> markPurchaseAsSynced(String id);
```

ملاحظة: لا اختبار وحدة لهذه الطبقة (نفس نهج المشروع الحالي — لا اختبارات لـ DatabaseService لأن `init()` يستخدم `Hive.initFlutter()`). التحقق عبر `flutter analyze` والاختبارات اللاحقة.

- [ ] **Step 1: استورد النماذج وسجل المهايئات وافتح الصندوقين**

في أعلى الملف أضف:

```dart
import '../models/supplier_model.dart';
import '../models/purchase_model.dart';
```

أضف ثوابت الأسماء بجانب الباقية وأدرجهما في `_allBoxNames`:

```dart
static const String _suppliersBoxName = 'suppliers';
static const String _purchasesBoxName = 'purchases';
```

ضمن `_allBoxNames` أضف `_suppliersBoxName, _purchasesBoxName`.

ضمن الحقول:

```dart
late Box<Supplier> _suppliersBox;
late Box<Purchase> _purchasesBox;
```

ضمن `init()` بعد تسجيل المهايئات القائمة:

```dart
Hive.registerAdapter(SupplierAdapter());
Hive.registerAdapter(PurchaseAdapter());
Hive.registerAdapter(PurchaseItemAdapter());
```

وقبل `_salesCache` افتح:

```dart
_suppliersBox =
    await Hive.openBox<Supplier>(_suppliersBoxName, encryptionCipher: cipher);
_purchasesBox =
    await Hive.openBox<Purchase>(_purchasesBoxName, encryptionCipher: cipher);
```

- [ ] **Step 2: أضف قسم CRUD الموردين**

قبل قسم `// ==================== Chart Data Methods ====================` أضف:

```dart
  // ==================== Supplier Methods ====================

  List<Supplier> getAllSuppliers() {
    return _suppliersBox.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Supplier? getSupplierById(String id) {
    try {
      return _suppliersBox.get(id);
    } catch (e) {
      return null;
    }
  }

  bool supplierExists(String id) => _suppliersBox.containsKey(id);

  List<Supplier> getUnsyncedSuppliers() {
    return _suppliersBox.values.where((s) => !s.isSynced).toList();
  }

  Future<void> addSupplierWithId({
    required String id,
    required String name,
    String? phone,
    String? address,
    String? notes,
    required String userId,
    bool isSynced = false,
  }) async {
    final supplier = Supplier(
      id: id,
      name: name,
      phone: phone,
      address: address,
      notes: notes,
      userId: userId,
      isSynced: isSynced,
    );
    await _suppliersBox.put(supplier.id, supplier);
  }

  Future<void> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? address,
    String? notes,
  }) async {
    final supplier = _suppliersBox.get(id);
    if (supplier != null) {
      supplier.name = name;
      supplier.phone = phone;
      supplier.address = address;
      supplier.notes = notes;
      supplier.updatedAt = DateTime.now();
      supplier.isSynced = false;
      await supplier.save();
    }
  }

  Future<void> deleteSupplierLocal(String id) async {
    await _suppliersBox.delete(id);
  }

  Future<void> markSupplierAsSynced(String id) async {
    final supplier = _suppliersBox.get(id);
    if (supplier != null) {
      supplier.isSynced = true;
      await supplier.save();
    }
  }

  // ==================== Purchase Methods ====================

  int getPurchaseCount() => _purchasesBox.length;

  List<Purchase> getAllPurchases() {
    return _purchasesBox.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<Purchase> getPurchasesBySupplier(String supplierId) {
    return _purchasesBox.values
        .where((p) => p.supplierId == supplierId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  // المرتجعات المرتبطة بعملية شراء أصلية
  List<Purchase> getReturnPurchasesFor(String originalPurchaseId) {
    return _purchasesBox.values
        .where((p) =>
            p.isReturn && p.originalPurchaseId == originalPurchaseId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Purchase? getPurchaseById(String id) {
    try {
      return _purchasesBox.get(id);
    } catch (e) {
      return null;
    }
  }

  List<Purchase> getUnsyncedPurchases() {
    return _purchasesBox.values.where((p) => !p.isSynced).toList();
  }

  Future<Purchase> addPurchaseWithId({
    required String id,
    required List<PurchaseItem> items,
    required String supplierId,
    required String supplierName,
    required double total,
    String? note,
    String purchaseType = 'purchase',
    String? originalPurchaseId,
    required String userId,
    bool isSynced = false,
    DateTime? createdAt,
  }) async {
    final purchase = Purchase(
      id: id,
      items: items,
      supplierId: supplierId,
      supplierName: supplierName,
      total: total,
      note: note,
      purchaseType: purchaseType,
      originalPurchaseId: originalPurchaseId,
      userId: userId,
      isSynced: isSynced,
      createdAt: createdAt,
    );
    await _purchasesBox.put(purchase.id, purchase);
    return purchase;
  }

  Future<void> deletePurchaseLocal(String id) async {
    await _purchasesBox.delete(id);
  }

  Future<void> markPurchaseAsSynced(String id) async {
    final purchase = _purchasesBox.get(id);
    if (purchase != null) {
      purchase.isSynced = true;
      await purchase.save();
    }
  }
```

- [ ] **Step 3: حدّث `clearUserData()` و `closeBoxes()`**

ضمن `clearUserData()` بعد `await deleteAllMovements();`:

```dart
    await _suppliersBox.clear();
    await _purchasesBox.clear();
```

ضمن `closeBoxes()` قبل إغلاق `_syncLogBox`:

```dart
    await _suppliersBox.close();
    await _purchasesBox.close();
```

- [ ] **Step 4: تحقق وcommit**

Run: `flutter analyze`
Expected: No issues

```bash
git add lib/services/database_service.dart
git commit -m "feat: add suppliers and purchases Hive storage to DatabaseService"
```

---

### Task 4: FirebaseService — مجموعتان ودوال المزامنة

**Files:**
- Modify: `lib/config/firebase_config.dart`
- Modify: `lib/services/firebase_service.dart`
- Modify: `firestore.rules`

**Interfaces:**
- Consumes: `Supplier`, `Purchase` (Task 1)، أنماط `FirebaseService` الحالية (استعلام المستخدم الحالي بـ `user_id`)
- Produces:

```dart
Future<void> addSupplier({required String id, required String name, String? phone, String? address, String? notes, required DateTime createdAt});
Future<void> updateSupplier({required String id, required String name, String? phone, String? address, String? notes});
Future<void> deleteSupplier(String id);
Future<void> addSuppliersBatch(List<Map<String, dynamic>> suppliers);
Future<List<Supplier>> getSuppliers({DateTime? lastSync});
Future<void> addPurchase({required Purchase purchase});
Future<void> addPurchasesBatch(List<Map<String, dynamic>> purchases);
Future<List<Purchase>> getPurchases({DateTime? lastSync});
Future<void> deletePurchase(String id);
```

- [ ] **Step 1: أضف أسماء المجموعات**

في `firebase_config.dart` بعد `inventoryMovementsCollection`:

```dart
  static const String suppliersCollection = 'suppliers';
  static const String purchasesCollection = 'purchases';
```

- [ ] **Step 2: أضف دوال FirebaseService**

استورد النموذجين في أعلى `firebase_service.dart`. أضف القسم التالي بنفس نمط دوال المنتجات (فلترة `user_id` بمستخدم الجلسة الحالية كما تفعل `getProducts`)：

```dart
  // ==================== Suppliers ====================

  Future<void> addSupplier({
    required String id,
    required String name,
    String? phone,
    String? address,
    String? notes,
    required DateTime createdAt,
  }) async {
    final uid = currentUser!.uid;
    await _db
        .collection(FirebaseConfig.suppliersCollection)
        .doc(id)
        .set({
      'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'notes': notes,
      'user_id': uid,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? address,
    String? notes,
  }) async {
    await _db
        .collection(FirebaseConfig.suppliersCollection)
        .doc(id)
        .update({
      'name': name,
      'phone': phone,
      'address': address,
      'notes': notes,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteSupplier(String id) async {
    await _db.collection(FirebaseConfig.suppliersCollection).doc(id).delete();
  }

  Future<void> addSuppliersBatch(List<Map<String, dynamic>> suppliers) async {
    final uid = currentUser!.uid;
    WriteBatch batch = _db.batch();
    int ops = 0;
    for (final s in suppliers) {
      final doc = _db.collection(FirebaseConfig.suppliersCollection).doc(s['id'] as String);
      batch.set(doc, {...s, 'user_id': uid});
      ops++;
      if (ops % 450 == 0) {
        await batch.commit();
        batch = _db.batch();
      }
    }
    if (ops % 450 != 0 || ops == 0) await batch.commit();
  }

  Future<List<Supplier>> getSuppliers({DateTime? lastSync}) async {
    final uid = currentUser!.uid;
    Query query = _db
        .collection(FirebaseConfig.suppliersCollection)
        .where('user_id', isEqualTo: uid);
    if (lastSync != null) {
      query = query.where('updated_at', isGreaterThan: Timestamp.fromDate(lastSync));
    }
    final snap = await query.get();
    return snap.docs.map((d) => Supplier.fromFirestore(d)).toList();
  }

  // ==================== Purchases ====================

  // الأصناف تُخزَّن مصفوفة داخل وثيقة الشراء (لا مجموعة فرعية)
  Future<void> addPurchase({required Purchase purchase}) async {
    final uid = currentUser!.uid;
    await _db
        .collection(FirebaseConfig.purchasesCollection)
        .doc(purchase.id)
        .set({
      ...purchase.toJson(),
      'user_id': uid,
      'created_at': Timestamp.fromDate(purchase.createdAt),
    });
  }

  Future<void> addPurchasesBatch(List<Map<String, dynamic>> purchases) async {
    final uid = currentUser!.uid;
    WriteBatch batch = _db.batch();
    int ops = 0;
    for (final p in purchases) {
      final doc = _db.collection(FirebaseConfig.purchasesCollection).doc(p['id'] as String);
      batch.set(doc, {
        ...p,
        'user_id': uid,
        'created_at': Timestamp.fromDate(DateTime.parse(p['created_at'] as String)),
      });
      ops++;
      if (ops % 450 == 0) {
        await batch.commit();
        batch = _db.batch();
      }
    }
    if (ops % 450 != 0 || ops == 0) await batch.commit();
  }

  Future<List<Purchase>> getPurchases({DateTime? lastSync}) async {
    final uid = currentUser!.uid;
    Query query = _db
        .collection(FirebaseConfig.purchasesCollection)
        .where('user_id', isEqualTo: uid);
    if (lastSync != null) {
      query = query.where('created_at', isGreaterThan: Timestamp.fromDate(lastSync));
    }
    final snap = await query.get();
    return snap.docs.map((d) => Purchase.fromFirestore(d)).toList();
  }

  Future<void> deletePurchase(String id) async {
    await _db.collection(FirebaseConfig.purchasesCollection).doc(id).delete();
  }
```

مهم — أضف في النماذج مصنعي Firestore (بجانب fromJson):

في `supplier_model.dart`:

```dart
  factory Supplier.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final s = Supplier.fromJson({...data, 'id': doc.id, 'is_synced': true});
    return s;
  }
```

في `purchase_model.dart` (يحوّل Timestamp إلى ISO قبل fromJson):

```dart
  factory Purchase.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final fixed = data.map((k, v) => MapEntry(k, v is Timestamp ? v.toDate().toIso8601String() : v));
    return Purchase.fromJson({...fixed, 'id': doc.id});
  }
```

- [ ] **Step 3: حدّث firestore.rules**

بعد بلوك `match /inventory_movements/{id}` أضف:

```
    match /suppliers/{id} {
      allow create: if canCreate(request.auth.uid);
      allow read: if canAccessOwned();
      allow update: if canUpdateOwned();
      allow delete: if canAccessOwned();
    }

    match /purchases/{id} {
      allow create: if canCreate(request.auth.uid);
      allow read: if canAccessOwned();
      allow update: if canUpdateOwned();
      allow delete: if canAccessOwned();
    }
```

- [ ] **Step 4: تحقق وcommit**

Run: `flutter analyze`
Expected: No issues

```bash
git add lib/config/firebase_config.dart lib/services/firebase_service.dart lib/models/supplier_model.dart lib/models/purchase_model.dart firestore.rules
git commit -m "feat: add suppliers and purchases Firebase sync endpoints and rules"
```

---

### Task 5: SyncService — خط أنابيب الرفع والسحب

**Files:**
- Modify: `lib/services/sync_service.dart`

**Interfaces:**
- Consumes: دوال DatabaseService (Task 3) و FirebaseService (Task 4)
- Produces: الموردين والمشتريات يدخلان دورة `syncNow()` الكاملة (push ثم pull)

- [ ] **Step 1: عدّل عدادات الحالة**

في `pendingSyncCount` أضف:

```dart
    final unsyncedSuppliers = _db.getUnsyncedSuppliers().length;
    final unsyncedPurchases = _db.getUnsyncedPurchases().length;
    return unsyncedProducts + unsyncedSales + unsyncedMovements + unsyncedSuppliers + unsyncedPurchases;
```

وفي `getUnsyncedCount()` أضف مفاتيح `'suppliers'` و `'purchases'` بنفس الطريقة.

- [ ] **Step 2: الرفع — داخل `_syncUnsyncedData()` قبل السطر الأخير**

أضف بلوكين بنفس نمط بلوك المنتجات (Batch ثم fallback فردي):

```dart
    // ⭐ 4. مزامنة الموردين غير المتزامنين
    final unsyncedSuppliers = _db.getUnsyncedSuppliers();
    AppConfig.log('📤 Found ${unsyncedSuppliers.length} unsynced suppliers');

    if (unsyncedSuppliers.isNotEmpty) {
      try {
        await _firebase.addSuppliersBatch(unsyncedSuppliers
            .map((s) => {
                  'id': s.id,
                  'name': s.name,
                  'phone': s.phone,
                  'address': s.address,
                  'notes': s.notes,
                  'created_at': s.createdAt.toIso8601String(),
                })
            .toList());
        for (final s in unsyncedSuppliers) {
          await _db.markSupplierAsSynced(s.id);
        }
        AppConfig.log('✅ ${unsyncedSuppliers.length} suppliers synced via batch');
      } catch (e) {
        AppConfig.logError('❌ Failed to batch sync suppliers', e);
        for (final s in unsyncedSuppliers) {
          try {
            await _firebase.addSupplier(
                id: s.id,
                name: s.name,
                phone: s.phone,
                address: s.address,
                notes: s.notes,
                createdAt: s.createdAt);
            await _db.markSupplierAsSynced(s.id);
          } catch (e2) {
            AppConfig.logError('❌ Failed to sync supplier ${s.id}', e2);
            _syncErrors.add({
              'type': 'supplier',
              'id': s.id,
              'message': e2.toString(),
              'timestamp': DateTime.now().toIso8601String(),
            });
          }
        }
      }
    }

    // ⭐ 5. مزامنة المشتريات غير المتزامنة
    final unsyncedPurchases = _db.getUnsyncedPurchases();
    AppConfig.log('📤 Found ${unsyncedPurchases.length} unsynced purchases');

    if (unsyncedPurchases.isNotEmpty) {
      try {
        await _firebase.addPurchasesBatch(
            unsyncedPurchases.map((p) => p.toJson()).toList());
        for (final p in unsyncedPurchases) {
          await _db.markPurchaseAsSynced(p.id);
        }
        AppConfig.log('✅ ${unsyncedPurchases.length} purchases synced via batch');
      } catch (e) {
        AppConfig.logError('❌ Failed to batch sync purchases', e);
        for (final p in unsyncedPurchases) {
          try {
            await _firebase.addPurchase(purchase: p);
            await _db.markPurchaseAsSynced(p.id);
          } catch (e2) {
            AppConfig.logError('❌ Failed to sync purchase ${p.id}', e2);
            _syncErrors.add({
              'type': 'purchase',
              'id': p.id,
              'message': e2.toString(),
              'timestamp': DateTime.now().toIso8601String(),
            });
          }
        }
      }
    }
```

ملاحظة: `Purchase.toJson()` يتضمن `purchase_items` — يخزَّن كل شيء في الوثيقة الواحدة.

- [ ] **Step 3: الحذف المعلّق — داخل `_syncPendingDeletes()`**

بعد بلوك حذف المبيعات:

```dart
    // ⭐ حذف الموردين من Firebase
    final pendingSupplierDeletes = _db.getPendingDeletes('supplier');
    for (final id in pendingSupplierDeletes) {
      try {
        await _firebase.deleteSupplier(id);
        await _db.removePendingDelete('supplier', id);
        AppConfig.log('  ✅ Pending supplier delete synced: $id');
      } catch (e) {
        AppConfig.logError('  ❌ Failed to sync supplier delete', e);
        _syncErrors.add({
          'type': 'supplier_delete',
          'id': id,
          'message': e.toString(),
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    }

    // ⭐ حذف المشتريات من Firebase
    final pendingPurchaseDeletes = _db.getPendingDeletes('purchase');
    for (final id in pendingPurchaseDeletes) {
      try {
        await _firebase.deletePurchase(id);
        await _db.removePendingDelete('purchase', id);
        AppConfig.log('  ✅ Pending purchase delete synced: $id');
      } catch (e) {
        AppConfig.logError('  ❌ Failed to sync purchase delete', e);
        _syncErrors.add({
          'type': 'purchase_delete',
          'id': id,
          'message': e.toString(),
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    }
```

- [ ] **Step 4: السحب — داخل `_syncFromFirebase()` قبل حفظ `lastSyncTime`**

```dart
    // ⭐ 7. جلب الموردين من Firebase
    try {
      AppConfig.log('📥📥📥 Fetching suppliers from Firebase...');
      final lastSync = fullPull ? null : _db.getLastSyncTime();
      final serverSuppliers = await _firebase.getSuppliers(lastSync: lastSync);
      AppConfig.log('📥📥📥 Fetched ${serverSuppliers.length} suppliers');

      for (var serverSupplier in serverSuppliers) {
        final local = _db.getSupplierById(serverSupplier.id);
        if (local == null) {
          await _db.addSupplierWithId(
            id: serverSupplier.id,
            name: serverSupplier.name,
            phone: serverSupplier.phone,
            address: serverSupplier.address,
            notes: serverSupplier.notes,
            userId: serverSupplier.userId,
            isSynced: true,
          );
        } else if (local.isSynced &&
            serverSupplier.updatedAt.isAfter(local.updatedAt)) {
          await _db.updateSupplier(
            id: local.id,
            name: serverSupplier.name,
            phone: serverSupplier.phone,
            address: serverSupplier.address,
            notes: serverSupplier.notes,
          );
          await _db.markSupplierAsSynced(local.id);
        }
      }
    } catch (e) {
      AppConfig.logError('❌ Error fetching suppliers from Firebase', e);
    }

    // ⭐ 8. جلب المشتريات من Firebase (إضافة فقط — لا تعديل للموجود)
    try {
      AppConfig.log('📥📥📥 Fetching purchases from Firebase...');
      final lastSync = fullPull ? null : _db.getLastSyncTime();
      final serverPurchases = await _firebase.getPurchases(lastSync: lastSync);
      AppConfig.log('📥📥📥 Fetched ${serverPurchases.length} purchases');

      for (var sp in serverPurchases) {
        if (_db.getPurchaseById(sp.id) == null) {
          await _db.addPurchaseWithId(
            id: sp.id,
            items: sp.items,
            supplierId: sp.supplierId,
            supplierName: sp.supplierName,
            total: sp.total,
            note: sp.note,
            purchaseType: sp.purchaseType,
            originalPurchaseId: sp.originalPurchaseId,
            userId: sp.userId,
            isSynced: true,
            createdAt: sp.createdAt,
          );
        }
      }
    } catch (e) {
      AppConfig.logError('❌ Error fetching purchases from Firebase', e);
    }
```

ملاحظة مهمة عن التحديث: `updateSupplier` في DatabaseService يضبط `isSynced=false`؛ لهذا يُستدعى `markSupplierAsSynced` بعده مباشرة في سياق السحب.

- [ ] **Step 5: قراءة Offline First — أضف في قسم دوال القراءة**

```dart
  Future<List<Supplier>> getSuppliers() async {
    return _db.getAllSuppliers();
  }

  Future<List<Purchase>> getPurchases() async {
    return _db.getAllPurchases();
  }
```

- [ ] **Step 6: تحقق وcommit**

Run: `flutter analyze && flutter test`
Expected: تحليل نظيف وجميع الاختبارات ناجحة (بما فيها Task 1-2)

```bash
git add lib/services/sync_service.dart
git commit -m "feat: integrate suppliers and purchases into sync pipeline"
```

---

### Task 6: SyncService — عمليات الكتابة (شراء/إرجاع/حذف/موردين)

**Files:**
- Modify: `lib/services/sync_service.dart`

**Interfaces:**
- Consumes: `SuppliersStockPolicy` (Task 2)، `InventoryMovement`/`MovementType` الموجودة
- Produces (واجهة الشاشات في Tasks 8-11):

```dart
Future<Supplier> addSupplier({required String name, String? phone, String? address, String? notes});
Future<void> updateSupplier({required String id, required String name, String? phone, String? address, String? notes});
Future<void> deleteSupplier(String id);

Future<Purchase> createPurchase({required String supplierId, required String supplierName, required List<PurchaseItem> items, String? note});   // يزيد المخزون + حركة incoming
Future<Purchase> createSupplierReturn({required String originalPurchaseId, required List<PurchaseItem> returnItems, String? note});             // ينقص المخزون + حركة return_out، يرفض تجاوز السقف
Future<void> deletePurchaseById(String id);   // يعكس أثر العملية (شراء أو مرتجع) + Tombstone
```

- [ ] **Step 1: أضف عمليات الموردين (نمط addProduct/write-through)**

في قسم دوال الكتابة:

```dart
  // ==================== عمليات الموردين ====================

  Future<Supplier> addSupplier({
    required String name,
    String? phone,
    String? address,
    String? notes,
  }) async {
    final userId = _db.getUserId();
    if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);

    final supplierId = _uuid.v4();

    // ⭐ أولاً: حفظ محلي
    await _db.addSupplierWithId(
      id: supplierId,
      name: name,
      phone: phone,
      address: address,
      notes: notes,
      userId: userId,
      isSynced: false,
    );

    _notifyDataChanged();

    // ⭐ ثانياً: رفع مباشر إن أمكن
    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.addSupplier(
            id: supplierId,
            name: name,
            phone: phone,
            address: address,
            notes: notes,
            createdAt: DateTime.now());
        await _db.markSupplierAsSynced(supplierId);
        AppConfig.log('✅ Supplier synced to Firebase: $name');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to sync supplier to Firebase', e);
      }
    }

    return _db.getSupplierById(supplierId)!;
  }

  Future<void> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? address,
    String? notes,
  }) async {
    await _db.updateSupplier(id: id, name: name, phone: phone, address: address, notes: notes);
    _notifyDataChanged();

    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.updateSupplier(id: id, name: name, phone: phone, address: address, notes: notes);
        await _db.markSupplierAsSynced(id);
        AppConfig.log('✅ Supplier updated in Firebase: $id');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to update supplier in Firebase', e);
      }
    }
  }

  Future<void> deleteSupplier(String id) async {
    await _db.deleteSupplierLocal(id);
    _notifyDataChanged();

    await _db.addPendingDelete('supplier', id);

    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.deleteSupplier(id);
        await _db.removePendingDelete('supplier', id);
        AppConfig.log('✅ Supplier deleted from Firebase: $id');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to delete supplier from Firebase', e);
      }
    }
  }
```

- [ ] **Step 2: أضف دوال المشتريات (مع منطق المخزون)**

```dart
  // ==================== عمليات المشتريات ====================

  // ⭐ شراء من مورد: يرفع كميات المخزون ويسجل حركة incoming
  Future<Purchase> createPurchase({
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    String? note,
  }) async {
    final userId = _db.getUserId();
    if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);
    if (items.isEmpty) throw Exception(LocalizationHelper.purchasesEmptyCart);

    final purchaseId = _uuid.v4();
    final total = items.fold<double>(0, (sum, i) => sum + i.subtotal);

    // ⭐ أولاً: حفظ الشراء محلياً
    final purchase = await _db.addPurchaseWithId(
      id: purchaseId,
      items: items,
      supplierId: supplierId,
      supplierName: supplierName,
      total: total,
      note: note,
      userId: userId,
      isSynced: false,
    );

    // ⭐ ثانياً: رفع كميات المخزون + تسجيل حركة لكل صنف
    for (final item in items) {
      final product = _db.getProductById(item.productId);
      if (product == null) continue;
      await _db.updateQuantity(item.productId, product.quantity + item.quantity);
      await _db.addMovement(
        productId: item.productId,
        productName: item.productName,
        type: MovementType.incoming,
        quantity: item.quantity,
        price: item.costPrice,
        total: item.subtotal,
        referenceId: purchaseId,
        note: note,
        userId: userId,
        supplierName: supplierName,
      );
    }

    _notifyDataChanged();

    // ⭐ ثالثاً: رفع مباشر إن أمكن
    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.addPurchase(purchase: purchase);
        await _db.markPurchaseAsSynced(purchaseId);
        AppConfig.log('✅ Purchase synced to Firebase: $purchaseId');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to sync purchase to Firebase', e);
      }
    }

    return purchase;
  }

  // ⭐ إرجاع للمورد: ينقص كميات المخزون ويسجل حركة return_out
  // يرفض أي صنف ليس في الشراء الأصلي أو يتجاوز سقف الإرجاع
  Future<Purchase> createSupplierReturn({
    required String originalPurchaseId,
    required List<PurchaseItem> returnItems,
    String? note,
  }) async {
    final userId = _db.getUserId();
    if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);

    final original = _db.getPurchaseById(originalPurchaseId);
    if (original == null) {
      throw Exception(LocalizationHelper.purchasesOriginalNotFound);
    }
    if (!original.canBeReturned) {
      throw Exception(LocalizationHelper.purchasesAlreadyFullyReturned);
    }
    if (returnItems.isEmpty || returnItems.every((i) => i.quantity <= 0)) {
      throw Exception(LocalizationHelper.purchasesEmptyCart);
    }

    // ⭐ التحقق من السقوف
    final returnedSoFar = <String, int>{};
    for (final r in _db.getReturnPurchasesFor(originalPurchaseId)) {
      for (final item in r.items) {
        returnedSoFar[item.productId] = (returnedSoFar[item.productId] ?? 0) + item.quantity;
      }
    }
    final invalid = SuppliersStockPolicy.invalidReturnProducts(
      originalItems: original.items,
      returnedSoFarByProductId: returnedSoFar,
      newReturnByProductId:
          {for (final i in returnItems) i.productId: i.quantity},
    );
    if (invalid.isNotEmpty) {
      throw Exception('${LocalizationHelper.purchasesReturnExceedsCap}: $invalid');
    }

    // ⭐ منع النقص تحت الصفر
    for (final item in returnItems) {
      final product = _db.getProductById(item.productId);
      if (product == null) {
        throw Exception('${LocalizationHelper.purchasesProductNotFound}: ${item.productName}');
      }
      if (SuppliersStockPolicy.wouldGoNegative(
          currentQuantity: product.quantity, change: -item.quantity)) {
        throw Exception('${LocalizationHelper.purchasesInsufficientStock}: ${item.productName}');
      }
    }

    final returnId = _uuid.v4();
    final total = returnItems.fold<double>(0, (sum, i) => sum + i.subtotal);

    final ret = await _db.addPurchaseWithId(
      id: returnId,
      items: returnItems,
      supplierId: original.supplierId,
      supplierName: original.supplierName,
      total: total,
      note: note,
      purchaseType: 'return',
      originalPurchaseId: originalPurchaseId,
      userId: userId,
      isSynced: false,
    );

    for (final item in returnItems) {
      final product = _db.getProductById(item.productId);
      if (product == null) continue;
      await _db.updateQuantity(item.productId, product.quantity - item.quantity);
      await _db.addMovement(
        productId: item.productId,
        productName: item.productName,
        type: MovementType.return_out,
        quantity: item.quantity,
        price: item.costPrice,
        total: item.subtotal,
        referenceId: returnId,
        note: note,
        userId: userId,
        supplierName: original.supplierName,
      );
    }

    _notifyDataChanged();

    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.addPurchase(purchase: ret);
        await _db.markPurchaseAsSynced(returnId);
      } catch (e) {
        AppConfig.logError('⚠️ Failed to sync return to Firebase', e);
      }
    }

    return ret;
  }

  // ⭐ حذف عملية (شراء أو مرتجع): يعكس أثرها على المخزون ثم يحذف من Hive وFirebase
  Future<void> deletePurchaseById(String id) async {
    final purchase = _db.getPurchaseById(id);
    if (purchase == null) return;

    // ⭐ اتجاه العكس: حذف شراء ينقص، وحذف مرتجع يُرجع الكميات
    final sign = purchase.isReturn ? 1 : -1;

    for (final item in purchase.items) {
      final product = _db.getProductById(item.productId);
      if (product == null) continue;
      final change = sign * item.quantity;
      if (SuppliersStockPolicy.wouldGoNegative(
          currentQuantity: product.quantity, change: change)) {
        // رفض الحذف إن كان سيسبب كمية سالبة (المواصفة §6.1)
        throw Exception('${LocalizationHelper.purchasesDeleteBlockedNegative}: ${item.productName}');
      }
    }

    for (final item in purchase.items) {
      final product = _db.getProductById(item.productId);
      if (product == null) continue;
      await _db.updateQuantity(
          item.productId, product.quantity + (sign * item.quantity));
    }

    await _db.deletePurchaseLocal(id);
    _notifyDataChanged();

    await _db.addPendingDelete('purchase', id);

    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.deletePurchase(id);
        await _db.removePendingDelete('purchase', id);
        AppConfig.log('✅ Purchase deleted from Firebase: $id');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to delete purchase from Firebase', e);
      }
    }
  }
```

- [ ] **Step 3: أضف getter المساعدة على الشراء الأصلي**

في `purchase_model.dart` أضف داخل class `Purchase` (بجانب `isReturn`):

```dart
  // يمكن الإرجاع من هذه العملية؟ (الأصلية فقط وليست مرتجعاً)
  bool get canBeReturned => !isReturn;
```

- [ ] **Step 4: استورد السياسة**

في أعلى `sync_service.dart`:

```dart
import '../helpers/suppliers_stock_policy.dart';
```

- [ ] **Step 5: تحقق وcommit**

Run: `flutter analyze && flutter test`
Expected: نظيف وناجح (رسائل LocalizationHelper ستظهر كأخطاء مؤقتة إن لم تُضف بعد — تُضاف في Task 7؛ إذا ظهرت أضف مفاتيح placeholder في هذا الـ commit ضمن الخطوة التالية)

ملاحظة: إذا أعطى `flutter analyze` أخطاء مفاتيح مفقودة من `LocalizationHelper`، أنشئ الآن حقول `static const` مؤقتة بقيم عربية مؤقتة داخل `lib/helpers/localization_helper.dart` (سيتم استبدال استخدامها بمفاتيح `.tr()` في Task 7):

```dart
  static const String purchasesEmptyCart = 'السلة فارغة';
  static const String purchasesOriginalNotFound = 'عملية الشراء الأصلية غير موجودة';
  static const String purchasesAlreadyFullyReturned = 'لا يمكن الإرجاع من مرتجع';
  static const String purchasesReturnExceedsCap = 'كمية الإرجاع تتجاوز الحد المسموح';
  static const String purchasesProductNotFound = 'المنتج غير موجود';
  static const String purchasesInsufficientStock = 'الكمية المتوفرة غير كافية';
  static const String purchasesDeleteBlockedNegative = 'لا يمكن الحذف: سيجعل الكمية سالبة، احذف المرتجعات المرتبطة أولاً';
```

```bash
git add lib/services/sync_service.dart lib/models/purchase_model.dart lib/helpers/localization_helper.dart
git commit -m "feat: add supplier and purchase write operations with stock logic"
```

---

### Task 7: الترجمات — ar/en/fr

**Files:**
- Modify: `assets/translations/ar.json`, `assets/translations/en.json`, `assets/translations/fr.json`

**Interfaces:**
- Produces: مفاتيح `suppliers.*` و `purchases.*` تستخدمها الشاشات عبر `'suppliers.title'.tr()`

- [ ] **Step 1: أضف القسمين في كل ملف**

في `ar.json` (ضمن الكائن الرئيسي):

```json
"suppliers": {
  "title": "الموردون",
  "subtitle": "إدارة الموردين والمشتريات",
  "add": "إضافة مورد",
  "edit": "تعديل المورد",
  "name": "اسم المورد",
  "phone": "الهاتف",
  "address": "العنوان",
  "notes": "ملاحظات",
  "search": "بحث بالاسم أو الهاتف...",
  "empty": "لا يوجد موردون بعد",
  "emptyHint": "أضف أول مورد لتبدأ التوريد",
  "deleteTitle": "حذف المورد",
  "deleteMessage": "هل أنت متأكد من حذف \"{name}\"؟ لن تُحذف مشترياته المسجلة.",
  "newPurchase": "عملية شراء جديدة",
  "purchasesCount": "{count} عملية مسجلة",
  "savedLocally": "تم الحفظ محلياً، ستتم المزامنة تلقائياً",
  "nameRequired": "اسم المورد مطلوب"
},
"purchases": {
  "title": "سجل المشتريات",
  "purchase": "شراء",
  "return": "مرتجع",
  "newPurchase": "عملية شراء",
  "selectSupplier": "اختر المورد",
  "addSupplierFirst": "أضف مورداً أولاً",
  "scanBarcode": "مسح الباركود",
  "pickProduct": "اختيار منتج",
  "costPrice": "سعر التكلفة",
  "quantity": "الكمية",
  "total": "الإجمالي",
  "note": "ملاحظة (اختياري)",
  "save": "حفظ الشراء",
  "saveReturn": "حفظ الإرجاع",
  "empty": "لا توجد عمليات شراء",
  "emptyHint": "ابدأ بعملية شراء من مورد",
  "details": "تفاصيل العملية",
  "items": "الأصناف",
  "deleteTitle": "حذف العملية",
  "deleteMessagePurchase": "سيُحذف سجل الشراء وتُخصم كمياته من المخزون.",
  "deleteMessageReturn": "سيُحذف سجل المرتجع وتُعاد كمياته إلى المخزون.",
  "returnToSupplier": "إرجاع للمورد",
  "availableForReturn": "المتاح للإرجاع",
  "returnSaved": "تم تسجيل الإرجاع",
  "insufficientStock": "الكمية المتوفرة غير كافية",
  "exceedsCap": "تتجاوز الحد المتاح للإرجاع",
  "selectProduct": "ابحث باسم المنتج أو امسح الباركود",
  "addedToCart": "أُضيف إلى السلة"
}
```

في `en.json`:

```json
"suppliers": {
  "title": "Suppliers",
  "subtitle": "Manage suppliers & purchases",
  "add": "Add supplier",
  "edit": "Edit supplier",
  "name": "Supplier name",
  "phone": "Phone",
  "address": "Address",
  "notes": "Notes",
  "search": "Search by name or phone...",
  "empty": "No suppliers yet",
  "emptyHint": "Add your first supplier to start purchasing",
  "deleteTitle": "Delete supplier",
  "deleteMessage": "Delete \"{name}\"? Their recorded purchases will be kept.",
  "newPurchase": "New purchase",
  "purchasesCount": "{count} records",
  "savedLocally": "Saved locally, will sync automatically",
  "nameRequired": "Supplier name is required"
},
"purchases": {
  "title": "Purchases history",
  "purchase": "Purchase",
  "return": "Return",
  "newPurchase": "Purchase",
  "selectSupplier": "Select supplier",
  "addSupplierFirst": "Add a supplier first",
  "scanBarcode": "Scan barcode",
  "pickProduct": "Pick product",
  "costPrice": "Cost price",
  "quantity": "Quantity",
  "total": "Total",
  "note": "Note (optional)",
  "save": "Save purchase",
  "saveReturn": "Save return",
  "empty": "No purchases yet",
  "emptyHint": "Start with your first supplier purchase",
  "details": "Details",
  "items": "Items",
  "deleteTitle": "Delete record",
  "deleteMessagePurchase": "The purchase record will be deleted and its quantities removed from stock.",
  "deleteMessageReturn": "The return record will be deleted and its quantities added back to stock.",
  "returnToSupplier": "Return to supplier",
  "availableForReturn": "Available for return",
  "returnSaved": "Return saved",
  "insufficientStock": "Insufficient stock",
  "exceedsCap": "Exceeds available return limit",
  "selectProduct": "Search product or scan barcode",
  "addedToCart": "Added to cart"
}
```

في `fr.json` ترجمات مكافئة بنفس المفاتيح (Fournisseurs/Achats).

- [ ] **Step 2: تحقق من صحة JSON**

Run: `flutter analyze` + تشغيل التطبيق أو `flutter test` للتأكد من عدم كسر تحميل الترجمات

- [ ] **Step 3: commit**

```bash
git add assets/translations/ar.json assets/translations/en.json assets/translations/fr.json
git commit -m "feat: add suppliers and purchases translation keys"
```

---

### Task 8: شاشة الموردين

**Files:**
- Create: `lib/screens/suppliers_screen.dart`
- Test: `test/widgets/suppliers_screen_test.dart`

**Interfaces:**
- Consumes: `SyncService.getSuppliers/addSupplier/updateSupplier/deleteSupplier` (Task 6)
- Produces: `SuppliersScreen` (StatefulWidget بلا معاملات) — تُستخدم في Task 12

- [ ] **Step 1: اكتب اختبار واجهة أساسي**

```dart
// test/widgets/suppliers_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:pos_app/screens/suppliers_screen.dart';

void main() {
  testWidgets('SuppliersScreen builds and shows empty state', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SuppliersScreen()));
    await tester.pumpAndSettle();
    // زر الإضافة العائم موجود
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
```

ملاحظة: إن فشل الاختبار بسبب تهيئة easy_localization، غلّف بـ `EasyLocalization` كما في `test/widgets/language_switcher_test.dart` الموجود — اقرأه وقلّد نمطه بالضبط.

- [ ] **Step 2: شغّل الاختبار (فاشل)**

Run: `flutter test test/widgets/suppliers_screen_test.dart`
Expected: FAIL — الملف غير موجود

- [ ] **Step 3: أنشئ الشاشة**

بنية الشاشة (StatefulWidget):

```dart
// lib/screens/suppliers_screen.dart

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/supplier_model.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/empty_state.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final SyncService _sync = SyncService();
  final TextEditingController _searchController = TextEditingController();
  List<Supplier> _suppliers = [];
  List<Supplier> _filtered = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await _sync.getSuppliers();
    if (!mounted) return;
    setState(() {
      _suppliers = list;
      _filtered = _applyFilter(list);
      _loading = false;
    });
  }

  List<Supplier> _applyFilter(List<Supplier> list) {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            (s.phone ?? '').contains(q))
        .toList();
  }

  void _onSearch(String value) {
    setState(() => _filtered = _applyFilter(_suppliers));
  }

  Future<void> _openSupplierForm({Supplier? supplier}) async {
    // Bottom Sheet بحقول: name (إلزامي)، phone، address، notes
    // زر حفظ: إن كان supplier == null استدعِ _sync.addSupplier وإلا updateSupplier
    // بعد النجاح: Navigator.pop، ثم _load()
    // التحقق: اسم فارغ → رسالة 'suppliers.nameRequired'.tr()
  }

  Future<void> _confirmDelete(Supplier supplier) async {
    // showDialog تأكيد برسالة 'suppliers.deleteMessage'.tr(namedArgs: {'name': supplier.name})
    // عند التأكيد: _sync.deleteSupplier(supplier.id) ثم _load()
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold مع AppBar عنوان 'suppliers.title'.tr()
    // حقل بحث فوق القائمة (onChanged: _onSearch)
    // ListView.builder لعرض _filtered: ListTile باسم المورد وهاتفه
    //   onTap: ورقة سفلية بخيارات: شراء جديد / سجل مشترياته / تعديل / حذف
    // FloatingActionButton: _openSupplierForm()
    // حالة الفراغ: EmptyState (الموجود في widgets/empty_state.dart)
  }
}
```

نفّذ الهيكل أعلاه كاملاً بأسلوب الشاشات الموجودة (`AppTextStyles`, `AppColors`, `context.isDark`). نمط نموذج الإضافة: انسخ بنية dialog من `product_form_dialog.dart` (حقول + validation + زر حفظ) مع الحقول الأربعة.

- [ ] **Step 4: شغّل الاختبار**

Run: `flutter test test/widgets/suppliers_screen_test.dart`
Expected: PASS

- [ ] **Step 5: تحقق وcommit**

Run: `flutter analyze`

```bash
git add lib/screens/suppliers_screen.dart test/widgets/suppliers_screen_test.dart
git commit -m "feat: add suppliers screen with search and CRUD"
```

---

### Task 9: شاشة الشراء مع مسح الباركود

**Files:**
- Create: `lib/screens/purchase_screen.dart`

**Interfaces:**
- Consumes:
  - `SyncService.getSuppliers()`, `createPurchase(...)` (Task 6)
  - `DatabaseService.instance.getProductByBarcode(barcode)` و `getAllProducts()` (موجودة)
  - `BarcodeScannerView(onBarcodeDetected: ..., onClose: ..., paused: ...)` (موجود — راجع استخدامه في `login_qr_scan_screen.dart` أو `pos_screen.dart`)
- Produces: `PurchaseScreen` — تُفتح من شاشة الموردين والداشبورد (Task 12)

- [ ] **Step 1: ابنِ هيكل الشاشة**

State: `_supplierId`, `_cartItems` (List\<PurchaseItem\>), `_note`, `_scanning` flag.

```dart
// lib/screens/purchase_screen.dart — الهيكل المنطقي الكامل

// اختيار المورد: DropdownButtonFormField يُغذى من _sync.getSuppliers()
//   مع زر أيقونة person_add يفتح نموذج إضافة مورد سريعاً (نفس نموذج Task 8)

// زر مسح الباركود:
//   setState(() => _scanning = true) ويعرض BarcodeScannerView ملء الشاشة
//   onBarcodeDetected: (code) async {
//     final product = DatabaseService.instance.getProductByBarcode(code);
//     if (product == null) { SnackBar 'غير موجود'; return; }
//     // إن كان المنتج في السلة زيّد كميته وإلا أضف PurchaseItem جديد
//     // costPrice افتراضي 0.0 قابل للتعديل من حقل السلة
//   }
//   onClose: () => setState(() => _scanning = false)

// زر "اختيار منتج": showModalBottomSheet فيه TextField بحث + قائمة
//   DatabaseService.instance.getAllProducts() → onTap يضيف للسلة

// عرض السلة: ListView لكل PurchaseItem صف فيه:
//   - اسم المنتج
//   - TextFormField للكمية (onChanged يحدث quantity وsubtotal = cost*qty)
//   - TextFormField لسعر التكلفة (نفس التحديث)
//   - IconButton delete لإزالة الصنف

// صف الإجمالي: _cartItems.fold<double>(0, (s, i) => s + i.subtotal)

// زر الحفظ (معطّل إن لم يكن هناك مورد أو سلة فارغة):
//   await _sync.createPurchase(supplierId: ..., supplierName: ..., items: _cartItems, note: _note)
//   SnackBar نجاح 'purchases.save' ثم Navigator.pop
//   الاستثناءات من السياسة → SnackBar برسالة e.toString()

// عند إنشاء معرفات PurchaseItem استخدم Uuid().v4()
```

- [ ] **Step 2: تحقق وcommit**

Run: `flutter analyze && flutter test`
Expected: نظيف

```bash
git add lib/screens/purchase_screen.dart
git commit -m "feat: add purchase screen with barcode scanning"
```

---

### Task 10: سجل المشتريات — قائمة/تفاصيل/حذف/مدخل إرجاع

**Files:**
- Create: `lib/screens/purchases_history_screen.dart`

**Interfaces:**
- Consumes: `SyncService.getPurchases()`, `createSupplierReturn(originalPurchaseId:, returnItems:, note:)`, `deletePurchaseById(id)` (Task 6)، `getReturnPurchasesFor(id)` من DatabaseService
- Produces: `PurchasesHistoryScreen` + `SupplierReturnScreen` (Task 11) يُفتح منها

- [ ] **Step 1: ابنِ الشاشة**

```dart
// lib/screens/purchases_history_screen.dart — الهيكل

// ListView من getAllPurchases() عبر _sync.getPurchases()
// كل صف Card فيه:
//   - شارة نوع ملونة: 'purchases.purchase'.tr() أخضر 0xFF10B981 /
//     'purchases.return'.tr() بنفسجي 0xFF8B5CF6 (نفس ألوان MovementType.getTypeColor)
//   - اسم المورد + التاريخ + الإجمالي
// onTap → showModalBottomSheet تفاصيل:
//   - قائمة الأصناف (اسم، كمية × تكلفة = مجموع)
//   - الملاحظة إن وجدت
//   - زر حذف أحمر:
//       showDialog تأكيد برسالة حسب النوع ('purchases.deleteMessagePurchase' أو deleteMessageReturn)
//       عند التأكيد: try { await _sync.deletePurchaseById(id); } catch → SnackBar برسالة الاستثناء
//       ثم إعادة تحميل القائمة
//   - زر 'purchases.returnToSupplier' (يظهر فقط إن !purchase.isReturn):
//       Navigator.push(SupplierReturnScreen(originalPurchase: purchase))
```

- [ ] **Step 2: تحقق وcommit**

Run: `flutter analyze`

```bash
git add lib/screens/purchases_history_screen.dart
git commit -m "feat: add purchases history screen with details and delete"
```

---

### Task 11: شاشة الإرجاع للمورد

**Files:**
- Create: `lib/screens/supplier_return_screen.dart`

**Interfaces:**
- Consumes: `Purchase` الأصلية (Task 1)، `SyncService.createSupplierReturn` (Task 6)، `DatabaseService.getReturnPurchasesFor` (Task 3)
- Produces: `SupplierReturnScreen({required Purchase originalPurchase})`

- [ ] **Step 1: ابنِ الشاشة**

```dart
// lib/screens/supplier_return_screen.dart — الهيكل

// المعامل: final Purchase originalPurchase;
// عند الفتح احسب السقف لكل منتج:
//   final returnedSoFar = <String, int>{};  // من DatabaseService.instance.getReturnPurchasesFor(original.id)
//   لكل صنف أصلي: cap = SuppliersStockPolicy.returnCap(
//       purchasedQuantity: item.quantity,
//       alreadyReturnedQuantity: returnedSoFar[item.productId] ?? 0)
//   الحالة: Map<String, int> _returnQty مهيأة بـ cap لكل صنف (الافتراضي = كامل السقف)

// عرض أصناف الشراء الأصلي فقط (المواصفة §7.4):
//   كل صف: اسم المنتج + نص cap ('purchases.availableForReturn') +
//   Row بأزرار [-] [+] وTextField رقمي بينهما يقيد 0..cap
//   الصفوف ذات cap == 0 تُعرض معطلة

// حقل ملاحظة + زر 'purchases.saveReturn':
//   ابنِ List<PurchaseItem> من الصفوف ذات _returnQty > 0
//   (costPrice من الشراء الأصلي، id جديد بـ Uuid())
//   try { await _sync.createSupplierReturn(originalPurchaseId: original.id, returnItems: ..., note: ...) }
//   catch → SnackBar برسالة الاستثناء (تجاوز السقف / مخزون غير كافٍ)
//   نجاح → SnackBar 'purchases.returnSaved' + pop
```

- [ ] **Step 2: تحقق وcommit**

Run: `flutter analyze && flutter test`

```bash
git add lib/screens/supplier_return_screen.dart
git commit -m "feat: add supplier return screen with capped quantities"
```

---

### Task 12: التنقل — قائمة الداشبورد وربط الشاشات

**Files:**
- Modify: `lib/widgets/dashboard_menu.dart`
- Modify: `lib/screens/suppliers_screen.dart` (ربط أزرار الشراء والسجل)

**Interfaces:**
- Consumes: `SuppliersScreen`, `PurchaseScreen`, `PurchasesHistoryScreen` (Tasks 8-10)

- [ ] **Step 1: أضف بلاطة الموردين في dashboard_menu.dart**

قلّد بلوك `_buildMenuTile` الخاص بالمخزون الموجود (بعد بلاطة inventory):

```dart
                      _buildMenuTile(
                        context: context,
                        icon: Icons.local_shipping_rounded,
                        title: 'suppliers.title'.tr(),
                        subtitle: 'suppliers.subtitle'.tr(),
                        color: context.accent,
                        titleStyle: titleStyle,
                        subtitleStyle: subtitleStyle,
                        onTap: () {
                          onClose();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SuppliersScreen(),
                            ),
                          );
                        },
                      ),
```

مع الاستيرادات:

```dart
import 'package:easy_localization/easy_localization.dart';
import '../screens/suppliers_screen.dart';
import '../screens/purchases_history_screen.dart';
```

وأضف بلاطة ثانية لسجل المشتريات (`Icons.receipt_long_rounded`, `'purchases.title'.tr()`) بنفس النمط يفتح `PurchasesHistoryScreen`.

ملاحظة: إذا كانت `dashboard_menu.dart` تستخدم `LocalizationHelper` بدل `.tr()` مباشرة، أضف الثوابت في `LocalizationHelper` وعبر بها (`static String get suppliersTitle => 'suppliers.title'.tr();`) واستخدمها — اتبع الأسلوب الموجود في الملف.

- [ ] **Step 2: اربط شاشة الموردين**

داخل `suppliers_screen.dart` أضف الاستيرادات (الشاشات موجودة الآن من Tasks 9-10):

```dart
import '../screens/purchase_screen.dart';
import '../screens/purchases_history_screen.dart';
```

- زر "شراء جديد" من قائمة المورد → `Navigator.push(PurchaseScreen(initialSupplierId: supplier.id))` (أضف المعامل الاختياري `initialSupplierId` إلى `PurchaseScreen`)
- زر "سجل مشترياته" → `Navigator.push(PurchasesHistoryScreen(initialSupplierId: supplier.id))` (أضف نفس المعامل الاختياري لتصفية القائمة عبر `getPurchasesBySupplier`)

- [ ] **Step 3: تحقق شامل وcommit**

Run: `flutter analyze && flutter test`
Expected: كل الاختبارات ناجحة

```bash
git add lib/widgets/dashboard_menu.dart lib/screens/suppliers_screen.dart lib/screens/purchase_screen.dart lib/screens/purchases_history_screen.dart
git commit -m "feat: wire suppliers and purchases into dashboard navigation"
```

---

### Task 13: التحقق النهائي

- [ ] **Step 1: التحليل والاختبارات كاملة**

Run: `flutter analyze`
Run: `flutter test`
Expected: صفر أخطاء، صفر اختبارات فاشلة

- [ ] **Step 2: بناء تجريبي**

Run: `flutter build apk --debug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: commit أخير إن وُجد تغيير وادفع**

```bash
git status
# إن وُجد تغييرات:
git add -A
git commit -m "chore: final checks for suppliers feature"
git push origin master
```

## ملاحظات تنفيذية عامة

- اقرأ دائماً الملف المجاور قبل التعديل (أنماط Theme/Styles/Localization)
- لا تعدل سلوك الشاشات الخدمية القائمة
- عند أي شك في نمط الواجهة، ارجع إلى `inventory_screen.dart` و `pos_screen.dart`
