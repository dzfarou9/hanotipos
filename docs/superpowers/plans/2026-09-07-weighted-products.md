# Weighted Products (kg / Litre) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users sell products by kg or litre (no barcode) with decimal stock, decimal purchases, and fractional returns.

**Architecture:** All quantity fields move `int` → `double` across the four quantity-bearing models plus `InventoryMovement`. Products gain a `unit` field (`'piece'` | `'kg'` | `'litre'`). Hive legacy data is made safe by replacing the generated adapters for migrated models with **hand-written, num-tolerant adapters** (read `as num` → `.toDouble()`), so old int records load fine and are rewritten as doubles on next save — no box rewrite needed. Firestore needs no migration; all parses become num-tolerant. UI: weighted products get a decimal quantity sheet at POS, decimal inputs in inventory/purchase/return forms, and a shared formatting helper.

**Tech Stack:** Flutter, Hive (hand-written TypeAdapters), Cloud Firestore, easy_localization, fl_chart, flutter_test.

**Spec:** `docs/superpowers/specs/2026-09-07-weighted-products-design.md`

## Global Constraints

- Quantity precision: **3 decimals** — round at input and at persistence via `QuantityFormat.round(double)` (Task 1).
- Unit values are exactly `'piece'`, `'kg'`, `'litre'` (stored strings; `'piece'` is the default for missing/null).
- Epsilon for double comparisons: `const double _kQtyEpsilon = 0.001;` exposed as `QuantityFormat.epsilon` (mirrors `debt_ledger_helper.dart` pattern).
- Adapters for Product, Sale, SaleItem, Purchase, PurchaseItem, InventoryMovement become **hand-written** in `lib/models/hive_adapters/legacy_tolerant_adapters.dart` and are registered in `DatabaseService.init()` (`lib/services/database_service.dart:92-104`). Their `typeId`s stay identical to today's: Product 0, SaleItem 2, Sale 3, InventoryMovement 4, PurchaseItem 6, Purchase 7.
- `@HiveType`/`part 'x.g.dart'` are removed from migrated models; their `.g.dart` files are deleted so build_runner cannot resurrect the int-casting reads.
- Firestore writes for `quantity` may now be double; every Firestore/Hive/JSON read uses `(x as num?)?.toDouble() ?? 0.0`.
- No scale hardware. No new dependencies.
- App languages: ar, en, fr — every user-facing string goes through all three JSON files (`assets/translations/`).
- Test commands run from repo root: `flutter test <path> --reporter compact`, analyzer via `dart analyze <paths>`.

---

### Task 1: QuantityFormat helper + unit translations

**Files:**
- Create: `lib/helpers/quantity_format.dart`
- Test: `test/helpers/quantity_format_test.dart`
- Modify: `assets/translations/ar.json`, `assets/translations/en.json`, `assets/translations/fr.json` (inside the `dates` sibling scope — add a new top-level `"unit"` object)

**Interfaces:**
- Produces (all later tasks):
  - `double QuantityFormat.round(double v)` — rounds to 3 decimals.
  - `String QuantityFormat.quantity(double v)` — trims trailing zeros: `2.0`→`"2"`, `0.850`→`"0.85"`, `-0.5`→`"-0.5"`.
  - `String QuantityFormat.withUnit(double v, String unit)` — `"0.85 kg"` / `"2 كغ"`.
  - `bool QuantityFormat.greaterThanQty(double a, double b)` / `bool QuantityFormat.isZeroQty(double v)` / `bool QuantityFormat.exceedsQty(double value, double cap)` — epsilon comparisons.
  - `const double QuantityFormat.epsilon = 0.001;`
  - `String unitLabel(String unit)` via LocalizationHelper → key `unit.piece` / `unit.kg` / `unit.liter`.

- [ ] **Step 1: Write the failing test**

```dart
// test/helpers/quantity_format_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/helpers/quantity_format.dart';

void main() {
  group('QuantityFormat.round', () {
    test('rounds to 3 decimals', () {
      expect(QuantityFormat.round(0.8504), 0.85);
      expect(QuantityFormat.round(1.23456), 1.235);
      expect(QuantityFormat.round(2), 2.0);
    });
  });

  group('QuantityFormat.quantity', () {
    test('trims trailing zeros', () {
      expect(QuantityFormat.quantity(2.0), '2');
      expect(QuantityFormat.quantity(0.85), '0.85');
      expect(QuantityFormat.quantity(2.5), '2.5');
      expect(QuantityFormat.quantity(-0.5), '-0.5');
      expect(QuantityFormat.quantity(0), '0');
    });
  });

  group('epsilon comparisons', () {
    test('treats sub-epsilon deltas as equal', () {
      expect(QuantityFormat.isZeroQty(0.0009), isTrue);
      expect(QuantityFormat.isZeroQty(0.01), isFalse);
      expect(QuantityFormat.greaterThanQty(0.85, 0.85), isFalse);
      expect(QuantityFormat.greaterThanQty(0.9, 0.85), isTrue);
      expect(QuantityFormat.exceedsQty(0.85, 0.85), isFalse);
      expect(QuantityFormat.exceedsQty(0.9, 0.85), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/helpers/quantity_format_test.dart --reporter compact`
Expected: FAIL (file `lib/helpers/quantity_format.dart` does not exist).

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/helpers/quantity_format.dart
//
// Decimal-quantity math/format for weighted products (kg/litre).
// Pure helpers — no services, no Flutter.

/// كمية عشرية بثلاث منازل: كل الكميات تمرّ هنا قبل الحفظ أو العرض.
class QuantityFormat {
  /// هامش مقارنة الكميات العشرية (نفس نمط debt_ledger_helper).
  static const double epsilon = 0.001;

  /// يقرب إلى 3 منازل عشرية.
  static double round(double v) => (v * 1000).roundToDouble() / 1000;

  /// يزيل الأصفار الزائدة: 2.0 → "2"، 0.850 → "0.85".
  static String quantity(double v) {
    final s = round(v).toStringAsFixed(3);
    if (!s.contains('.')) return s;
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// كمية مع وحدتها: "0.85 kg" / "12.5 كغ".
  static String withUnit(double v, String unit) {
    // الترجمة تتم عند المستدعي عبر unitLabel؛ هنا نص الوحدة الخام.
    return '${quantity(v)} $unit';
  }

  // ── مقارنات بهامش ──
  static bool isZeroQty(double v) => v.abs() <= epsilon;
  static bool greaterThanQty(double a, double b) => a - b > epsilon;
  static bool exceedsQty(double value, double cap) => value - cap > epsilon;
}
```

Note on `withUnit`: the plan uses raw unit suffixes in the helper to keep it pure; UI tasks call `LocalizationHelper.unitLabel(unit)` and pass its result as `unit`.

Add to `lib/helpers/localization_helper.dart` (place near the date helpers around line 703):

```dart
  // ==================== الوحدات ====================
  static String unitLabel(String unit) => 'unit.${unit == 'kg' ? 'kg' : unit == 'litre' ? 'liter' : 'piece'}'.tr();
```

Translation JSON — add a top-level `"unit"` object to each file:

```json
// assets/translations/ar.json
"unit": { "piece": "قطعة", "kg": "كغ", "liter": "ل" }
```
```json
// assets/translations/en.json
"unit": { "piece": "pc", "kg": "kg", "liter": "L" }
```
```json
// assets/translations/fr.json
"unit": { "piece": "pc", "kg": "kg", "liter": "L" }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/helpers/quantity_format_test.dart --reporter compact`
Expected: PASS (all).

- [ ] **Step 5: Commit**

```bash
git add lib/helpers/quantity_format.dart lib/helpers/localization_helper.dart test/helpers/quantity_format_test.dart assets/translations/ar.json assets/translations/en.json assets/translations/fr.json
git commit -m "feat: add QuantityFormat helper and unit translations"
```

---

### Task 2: Product model — double quantity + unit field + tolerant adapter

**Files:**
- Modify: `lib/models/product_model.dart`
- Create: `lib/models/hive_adapters/legacy_tolerant_adapters.dart` (starts with ProductAdapter only)
- Delete: `lib/models/product_model.g.dart`
- Modify: `lib/services/database_service.dart:92` (adapter registration)
- Test: `test/models/product_model_test.dart`

**Interfaces:**
- Produces:
  - `Product.quantity` is `double`; `Product.unit` is `String` (`'piece'|'kg'|'litre'`).
  - `bool Product.get isWeighted` — true when `unit != 'piece'`.
  - `String? Product.barcode` unchanged (weighted products pass `null`).
  - `ProductAdapter` (typeId 0) reads legacy int quantities and missing field 13.
  - `DatabaseService.init()` registers the new `ProductAdapter` from `hive_adapters/legacy_tolerant_adapters.dart` instead of the generated one.

- [ ] **Step 1: Write the failing test**

```dart
// test/models/product_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pos_app/models/product_model.dart';
import 'package:pos_app/models/hive_adapters/legacy_tolerant_adapters.dart';

void main() {
  setUpAll(() {
    Hive.init('test_hive_tmp');
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductAdapter());
  });

  test('fromFirestore tolerates legacy int quantity and missing unit', () {
    final p = Product.fromFirestore(FakeDoc({
      'name': 'Sugar', 'price': 120, 'quantity': 5, 'user_id': 'u1',
    }));
    expect(p.quantity, 5.0);
    expect(p.unit, 'piece');
    expect(p.isWeighted, isFalse);
  });

  test('fromFirestore parses decimal quantity and unit', () {
    final p = Product.fromFirestore(FakeDoc({
      'name': 'Oil', 'price': 800, 'quantity': 12.5, 'user_id': 'u1',
      'unit': 'kg',
    }));
    expect(p.quantity, 12.5);
    expect(p.unit, 'kg');
    expect(p.isWeighted, isTrue);
  });

  test('Hive roundtrip keeps unit and double quantity', () async {
    final p = Product(
      id: 'p1', name: 'Oil', category: 'G', price: 800, quantity: 12.5,
      userId: 'u1', unit: 'kg',
    );
    final box = await Hive.openBox<Product>('product_roundtrip_test');
    await box.put('p1', p);
    final read = box.get('p1')!;
    expect(read.quantity, 12.5);
    expect(read.unit, 'kg');
    await box.deleteFromDisk();
  });
}

// غلاف بسيط يحاكي DocumentSnapshot للاختبار
class FakeDoc implements dynamic {
  final Map<String, dynamic> data;
  FakeDoc(this.data);
}
```

NOTE: `Product.fromFirestore` takes a real `DocumentSnapshot`. If faking it is awkward, extract the parse body into `factory Product.fromMap(String id, Map<String, dynamic> data)` and have `fromFirestore` delegate — test `fromMap` instead. Prefer this extraction.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/product_model_test.dart --reporter compact`
Expected: FAIL — `unit`/`isWeighted` undefined, adapter file missing.

- [ ] **Step 3: Modify the model**

In `lib/models/product_model.dart`:
- Remove `part 'product_model.g.dart';` and the `@HiveType(typeId: 0)` / `@HiveField(n)` annotations (fields keep their order: id 0 … costPrice 12, new unit 13).
- Change field: `double quantity;`
- Add field + ctor param + getter:

```dart
  /// وحدة البيع: 'piece' | 'kg' | 'litre'
  String unit;

  Product({ ..., this.unit = 'piece', ... })

  /// منتج يُباع بالوزن/الحجم وليس بالقطعة؟
  bool get isWeighted => unit != 'piece';
```

- `fromFirestore` → extract to `fromMap(String id, Map<String, dynamic> data)`; parse quantities num-tolerant:

```dart
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0.0,
      unit: data['unit'] as String? ?? 'piece',
```

- `fromJson`: `quantity: (json['quantity'] as num).toDouble()`, add `unit: json['unit'] as String? ?? 'piece'`.
- `toJson`: add `'unit': unit`.

- [ ] **Step 4: Write the tolerant adapter**

```dart
// lib/models/hive_adapters/legacy_tolerant_adapters.dart
//
// Adapters مكتوبة يدوياً للنماذج التي تحوّلت من int إلى double في quantity.
// القراءة تتقبّل int (بيانات قديمة) أو double، وتكتب double دائماً.
// هذه الملفات لا تُولَّد من build_runner — لا تحذفها.

import 'package:hive/hive.dart';
import '../product_model.dart';

class ProductAdapter extends TypeAdapter<Product> {
  @override
  final int typeId = 0;

  @override
  Product read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Product(
      id: fields[0] as String,
      name: fields[1] as String,
      category: fields[2] as String,
      price: (fields[3] as num).toDouble(),
      // بيانات قديمة: int. بيانات جديدة: double.
      quantity: (fields[4] as num).toDouble(),
      description: fields[5] as String?,
      barcode: fields[8] as String?,
      createdAt: fields[6] as DateTime?,
      updatedAt: fields[7] as DateTime?,
      isSynced: fields[9] as bool,
      userId: fields[10] as String,
      minStockLevel: (fields[11] as num).toInt(),
      costPrice: (fields[12] as num?)?.toDouble(),
      // صناديق قديمة بلا الحقل 13 → piece
      unit: (fields[13] as String?) ?? 'piece',
    );
  }

  @override
  void write(BinaryWriter writer, Product obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.name)
      ..writeByte(2)..write(obj.category)
      ..writeByte(3)..write(obj.price)
      ..writeByte(4)..write(obj.quantity)
      ..writeByte(5)..write(obj.description)
      ..writeByte(6)..write(obj.createdAt)
      ..writeByte(7)..write(obj.updatedAt)
      ..writeByte(8)..write(obj.barcode)
      ..writeByte(9)..write(obj.isSynced)
      ..writeByte(10)..write(obj.userId)
      ..writeByte(11)..write(obj.minStockLevel)
      ..writeByte(12)..write(obj.costPrice)
      ..writeByte(13)..write(obj.unit);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
```

- [ ] **Step 5: Swap registration + delete generated file**

In `lib/services/database_service.dart` line 92 area: remove `Hive.registerAdapter(ProductAdapter());` generated import usage and import `../models/hive_adapters/legacy_tolerant_adapters.dart` (registration line stays `Hive.registerAdapter(ProductAdapter());` — different class, same name, same typeId 0). Delete `lib/models/product_model.g.dart`.

- [ ] **Step 6: Run tests**

Run: `flutter test test/models/product_model_test.dart --reporter compact`
Expected: PASS. Then `dart analyze lib/models lib/services` — expect unrelated quantity-type errors in other files are NOT yet fixed; scope analyzer check to `lib/models lib/models/hive_adapters`. (`dart analyze lib/models` must be clean.)

- [ ] **Step 7: Commit**

```bash
git add lib/models/product_model.dart lib/models/hive_adapters/legacy_tolerant_adapters.dart lib/services/database_service.dart test/models/product_model_test.dart
git rm lib/models/product_model.g.dart
git commit -m "feat: Product model decimal quantity + unit field with tolerant Hive adapter"
```

---

### Task 3: Sale/SaleItem model — double quantity + tolerant adapters

**Files:**
- Modify: `lib/models/sale_model.dart`
- Modify: `lib/models/hive_adapters/legacy_tolerant_adapters.dart` (add `SaleAdapter` typeId 3, `SaleItemAdapter` typeId 2)
- Delete: `lib/models/sale_model.g.dart`
- Modify: `lib/services/database_service.dart` (registration swap)
- Test: `test/models/sale_model_test.dart`

**Interfaces:**
- Produces:
  - `SaleItem.quantity` is `double`.
  - `Sale.canReturn` uses `QuantityFormat.exceedsQty(totalReturned, totalOriginal)`.
  - `Sale.availableForReturn` returns items with double `quantity`; internal maps become `Map<String, double>`.
  - Both adapters read legacy int quantities.

- [ ] **Step 1: Write the failing test**

```dart
// test/models/sale_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/sale_model.dart';

SaleItem item(String pid, double price, double qty) => SaleItem(
      id: 'i-$pid-$qty', productId: pid, productName: 'P$pid',
      price: price, quantity: qty, subtotal: price * qty,
    );

Sale sale({required List<SaleItem> items, List<SaleItem>? returned}) => Sale(
      id: 's1', items: items, subtotal: 0, discount: 0, tax: 0, total: 0,
      paymentMethod: 'Cash', userId: 'u1',
      returnedItems: returned,
    );

void main() {
  test('SaleItem parses fractional quantity from Firestore map', () {
    final si = SaleItem.fromJson({
      'id': 'i1', 'product_id': 'p1', 'product_name': 'P',
      'price': 800, 'quantity': 0.85, 'subtotal': 680,
    });
    expect(si.quantity, 0.85);
  });

  test('canReturn honors fractional partial returns with epsilon', () {
    final s = sale(items: [item('p1', 800, 0.85)], returned: [item('p1', 800, 0.3)]);
    expect(s.canReturn, isTrue);
  });

  test('canReturn false when returned equals sold (within epsilon)', () {
    final s = sale(items: [item('p1', 800, 0.85)], returned: [item('p1', 800, 0.85)]);
    expect(s.canReturn, isFalse);
  });

  test('availableForReturn returns fractional remainder', () {
    final s = sale(items: [item('p1', 800, 0.85)], returned: [item('p1', 800, 0.3)]);
    final avail = s.availableForReturn;
    expect(avail.single.quantity, closeTo(0.55, 0.0001));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/sale_model_test.dart --reporter compact`
Expected: FAIL (compile errors — double/int).

- [ ] **Step 3: Modify the model**

In `lib/models/sale_model.dart`:
- Remove `part` + Hive annotations (SaleItem typeId 2, Sale typeId 3 — keep field order; Sale has fields 0-17).
- `SaleItem.quantity` → `double`. `fromJson`: `quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0`.
- `canReturn` (lines ~234-244):

```dart
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
```

- `availableForReturn` (lines ~247-273): map `<String, double>`; `returnedQty` accumulation `(returnedQuantities[item.productId] ?? 0.0) + item.quantity`; guard `if (QuantityFormat.greaterThanQty(item.quantity, returnedQty))`; remainder `item.quantity - returnedQty`.
- Import `../helpers/quantity_format.dart`.

- [ ] **Step 4: Add tolerant adapters**

Append to `lib/models/hive_adapters/legacy_tolerant_adapters.dart` — copy the current generated read/write structure from `lib/models/sale_model.g.dart` (SaleItem typeId 2, Sale typeId 3), with these rules: every numeric field read as `(fields[n] as num).toDouble()` for quantity / `(fields[n] as num?)?.toDouble()` for money fields (`price`, `subtotal`, `total`, `discount`, `tax`, `returnTotal`); `write` unchanged field counts. Keep all nullable/non-nullable casts exactly as the generated file has them otherwise.

- [ ] **Step 5: Swap registration, delete generated file, run tests**

In `lib/services/database_service.dart`: replace the two generated registrations (`SaleAdapter`, `SaleItemAdapter`) — the import now covers them. Delete `lib/models/sale_model.g.dart`.

Run: `flutter test test/models/sale_model_test.dart --reporter compact` → PASS. `dart analyze lib/models lib/models/hive_adapters` → clean.

- [ ] **Step 6: Commit**

```bash
git add lib/models/sale_model.dart lib/models/hive_adapters/legacy_tolerant_adapters.dart lib/services/database_service.dart test/models/sale_model_test.dart
git rm lib/models/sale_model.g.dart
git commit -m "feat: Sale models decimal quantities with tolerant Hive adapters"
```

---

### Task 4: Purchase/PurchaseItem + InventoryMovement — double quantity

**Files:**
- Modify: `lib/models/purchase_model.dart`, `lib/models/inventory_movement_model.dart`
- Modify: `lib/models/hive_adapters/legacy_tolerant_adapters.dart` (add `PurchaseAdapter` typeId 7, `PurchaseItemAdapter` typeId 6, `InventoryMovementAdapter` typeId 4)
- Delete: `lib/models/purchase_model.g.dart`, `lib/models/inventory_movement_model.g.dart`
- Modify: `lib/services/database_service.dart` (registration swap)
- Test: `test/models/purchase_model_test.dart` (extend existing `test/models/supplier_purchase_model_test.dart` instead where it already covers `availableForReturn` — update its int literals to doubles)

**Interfaces:**
- Produces:
  - `PurchaseItem.quantity` and `InventoryMovement.quantity` are `double`.
  - `Purchase.availableForReturn({Map<String, double> extraReturned = const {}})` returns fractional remainders.
  - Adapters tolerant to legacy ints; `InventoryMovement` typeId stays 4, `getStockEffect()` returns `double`.

- [ ] **Step 1: Write the failing test**

```dart
// test/models/purchase_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/purchase_model.dart';

PurchaseItem pitem(String pid, double cost, double qty) => PurchaseItem(
      id: 'i-$pid-$qty', productId: pid, productName: 'P$pid',
      costPrice: cost, quantity: qty, subtotal: cost * qty,
    );

void main() {
  test('PurchaseItem parses fractional from Firestore map', () {
    final pi = PurchaseItem.fromJson({
      'id': 'i1', 'product_id': 'p1', 'product_name': 'P',
      'cost_price': 600, 'quantity': 25.5, 'subtotal': 15300,
    });
    expect(pi.quantity, 25.5);
  });

  test('availableForReturn returns fractional remainder', () {
    final p = Purchase(
      id: 'pu1', items: [pitem('p1', 600, 25.5)],
      supplierId: 's1', supplierName: 'S', total: 15300, userId: 'u1',
      returnedItems: [pitem('p1', 600, 0.5)],
    );
    final avail = p.availableForReturn();
    expect(avail.single.quantity, closeTo(25.0, 0.0001));
  });

  test('availableForReturn accepts fractional extraReturned', () {
    final p = Purchase(
      id: 'pu1', items: [pitem('p1', 600, 10)],
      supplierId: 's1', supplierName: 'S', total: 6000, userId: 'u1',
    );
    final avail = p.availableForReturn(extraReturned: {'p1': 2.5});
    expect(avail.single.quantity, closeTo(7.5, 0.0001));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/purchase_model_test.dart test/models/supplier_purchase_model_test.dart --reporter compact`
Expected: FAIL.

- [ ] **Step 3: Modify purchase model**

`lib/models/purchase_model.dart`:
- Remove `part` + annotations (PurchaseItem typeId 6 fields 0-5; Purchase typeId 7 fields 0-15).
- `PurchaseItem.quantity` → `double`; `fromJson`: `(json['quantity'] as num?)?.toDouble() ?? 0.0`.
- `availableForReturn({Map<String, double> extraReturned = const {}})` (lines 145-171): `final returned = <String, double>{};` accumulations `?? 0.0`; remaining guard `if (QuantityFormat.greaterThanQty(remaining, 0))`.
- Import `../helpers/quantity_format.dart`.

- [ ] **Step 4: Modify inventory movement model**

`lib/models/inventory_movement_model.dart`: remove `part` + annotations (typeId 4, fields per current file); `@HiveField(4) final double quantity`; `getStockEffect()` returns `double` (`-quantity` / `quantity`); `fromJson`: `(json['quantity'] as num?)?.toDouble() ?? 0.0`.

- [ ] **Step 5: Add the three tolerant adapters**

Append `PurchaseItemAdapter` (6), `PurchaseAdapter` (7), `InventoryMovementAdapter` (4) to `legacy_tolerant_adapters.dart` following the Task 3 rules — copy structure from the current `.g.dart` files, numeric-quantity reads become num-tolerant, money fields `(num?)?.toDouble()`.

- [ ] **Step 6: Swap registrations, delete generated files, run tests**

`database_service.dart`: swap the three registrations. `git rm lib/models/purchase_model.g.dart lib/models/inventory_movement_model.g.dart`.

Run: `flutter test test/models/purchase_model_test.dart test/models/supplier_purchase_model_test.dart test/models/inventory_movement_hive_test.dart --reporter compact`
Expected: PASS (supplier_purchase/inventory tests may need int literals → doubles: `quantity: 5` → `5.0`, expects `3` → `3.0`).

`dart analyze lib/models` → clean.

- [ ] **Step 7: Commit**

```bash
git add lib/models lib/services/database_service.dart test/models
git rm lib/models/purchase_model.g.dart lib/models/inventory_movement_model.g.dart
git commit -m "feat: Purchase and InventoryMovement decimal quantities"
```

---

### Task 5: CartItem + CartService — decimal cart

**Files:**
- Modify: `lib/models/cart_item_model.dart`, `lib/services/cart_service.dart`
- Test: `test/services/cart_service_test.dart` (extend existing cart tests if present; create if missing)

**Interfaces:**
- Produces:
  - `CartItem.quantity` is `double`, default `1.0`.
  - `CartService.addProduct(Product product, {double quantity = 1.0})`.
  - `CartService.updateQuantity(int index, double quantity)`.
  - `double get totalItems`.
  - `decrementQuantity`: subtract 1; remove when result `<= 0` (epsilon).

- [ ] **Step 1: Write the failing test**

```dart
// test/services/cart_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/product_model.dart';
import 'package:pos_app/services/cart_service.dart';

Product p(String id, {double price = 100, String unit = 'piece'}) => Product(
      id: id, name: 'P$id', category: 'G', price: price, quantity: 50,
      userId: 'u1', unit: unit,
    );

void main() {
  test('addProduct accepts fractional quantity', () {
    final cart = CartService();
    cart.addProduct(p('p1'), quantity: 0.85);
    expect(cart.items.single.quantity, 0.85);
    expect(cart.items.single.subtotal, 85.0);
  });

  test('adding same weighted product twice accumulates fractions', () {
    final cart = CartService();
    cart.addProduct(p('p1'), quantity: 0.85);
    cart.addProduct(p('p1'), quantity: 0.4);
    expect(cart.items.single.quantity, closeTo(1.25, 0.0001));
  });

  test('totalItems is double sum', () {
    final cart = CartService();
    cart.addProduct(p('p1'), quantity: 0.5);
    cart.addProduct(p('p2'));
    expect(cart.totalItems, closeTo(1.5, 0.0001));
  });

  test('decrement removes when quantity reaches zero (epsilon)', () {
    final cart = CartService();
    cart.addProduct(p('p1'), quantity: 0.5);
    cart.decrementQuantity(0);
    expect(cart.isEmpty, isTrue);
  });

  test('updateQuantity accepts fractional', () {
    final cart = CartService();
    cart.addProduct(p('p1'));
    cart.updateQuantity(0, 2.75);
    expect(cart.items.single.quantity, 2.75);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/cart_service_test.dart --reporter compact`
Expected: FAIL (compile).

- [ ] **Step 3: Implement**

`lib/models/cart_item_model.dart`: `double quantity;` default `1.0`.
`lib/services/cart_service.dart`:
- L28/L231: `double get totalItems => _items.fold(0.0, (sum, item) => sum + item.quantity);`
- L66: `void addProduct(Product product, {double quantity = 1.0})` — accumulate `_items[existingIndex].quantity = QuantityFormat.round(_items[existingIndex].quantity + quantity);`
- L93: `void updateQuantity(int index, double quantity)` (body unchanged, round on set).
- L104-120 `incrementQuantity` adds `1.0`; `decrementQuantity`:

```dart
  void decrementQuantity(int index) {
    if (index >= 0 && index < _items.length) {
      final next = _items[index].quantity - 1;
      if (QuantityFormat.isZeroQty(next) || next < 0) {
        _items.removeAt(index);
      } else {
        _items[index].quantity = QuantityFormat.round(next);
      }
      notifyListeners();
    }
  }
```

- Held-order copies unchanged (type flows). Import `../helpers/quantity_format.dart`.

- [ ] **Step 4: Run tests**

Run: `flutter test test/services/cart_service_test.dart test/widgets/payment_method_sheet_test.dart --reporter compact`
Expected: PASS (payment sheet test may need `int quantity = 2` → `double quantity = 2` param fix).

- [ ] **Step 5: Commit**

```bash
git add lib/models/cart_item_model.dart lib/services/cart_service.dart test/services/cart_service_test.dart test/widgets/payment_method_sheet_test.dart
git commit -m "feat: decimal cart quantities"
```

---

### Task 6: Services + policy — double pass-through and num-tolerant Firestore reads

**Files:**
- Modify: `lib/services/database_service.dart` (L587/622/658/706 params → double; L782 `fold<double>(0.0, ...)`; L786-788 zero checks via `QuantityFormat.isZeroQty`; L1013-1016/L1410-1413 folds → 0.0)
- Modify: `lib/services/firebase_service.dart` (L875 sale item parse → num-tolerant; L936/1036 params → double; L1648 movement parse → num-tolerant)
- Modify: `lib/services/sync_service.dart` (L1310/1466 params → double; L1870/L1961 maps → `Map<String, double>` with 0.0 seeds; L1865 `returnItems.every((i) => i.quantity <= QuantityFormat.epsilon)`; L1978/L1991 zero checks via `QuantityFormat.isZeroQty`; L1884 `invalidReturnProducts` map type)
- Modify: `lib/helpers/suppliers_stock_policy.dart` (all signatures `int` → `double`, zero checks epsilon)
- Modify: `lib/services/receipt_data.dart` (L28 `ReceiptLine.quantity` → double), `lib/services/receipt_renderer.dart` (L248/L267 render via `QuantityFormat.quantity`)
- Modify: `lib/services/printing_service.dart` (L470-486 — types flow, verify compile)
- Test: `test/helpers/suppliers_stock_policy_test.dart` (update to double), existing suite must compile.

**Interfaces:**
- Consumes: `QuantityFormat` (Task 1), double models (Tasks 2-4).
- Produces:
  - `SuppliersStockPolicy.returnCap({required double purchasedQuantity, required double alreadyReturnedQuantity}) → double`; `wouldGoNegative({required double currentQuantity, required double change}) → bool`; `invalidReturnProducts({required Map<String, double> returnedSoFarByProductId, required Map<String, double> newReturnByProductId}) → Map<String, double>` (same name, double types).
  - `DatabaseService.updateQuantity(String id, double newQuantity)`; `addProduct/addProductWithId/updateProduct(quantity: double)`; `addMovement/addMovementWithId(quantity: double)`.
  - `FirebaseService.addProduct/updateProduct(quantity: double)`, `addMovement(quantity: double)`.
  - `SyncService.addProduct/updateProduct(quantity: double)`.

- [ ] **Step 1: Update the policy test first (failing)**

In `test/helpers/suppliers_stock_policy_test.dart`: change helper `int qty` → `double qty`, int literals → doubles, and add fractional cases:

```dart
  test('returnCap honors fractional returns', () {
    expect(SuppliersStockPolicy.returnCap(
        purchasedQuantity: 25.5, alreadyReturnedQuantity: 0.5), 25.0);
    expect(SuppliersStockPolicy.returnCap(
        purchasedQuantity: 25.5, alreadyReturnedQuantity: 30), 0.0);
  });

  test('wouldGoNegative tolerates epsilon', () {
    expect(SuppliersStockPolicy.wouldGoNegative(currentQuantity: 0.0009, change: 0), isFalse);
    expect(SuppliersStockPolicy.wouldGoNegative(currentQuantity: 0.5, change: -0.6), isTrue);
  });
```

Run: `flutter test test/helpers/suppliers_stock_policy_test.dart --reporter compact` → FAIL (compile).

- [ ] **Step 2: Update policy**

`lib/helpers/suppliers_stock_policy.dart`: signatures per Produces; `returnCap` body: `final cap = purchasedQuantity - alreadyReturnedQuantity; return QuantityFormat.exceedsQty(0.0, cap) ? 0.0 : cap;` — i.e. `cap < -epsilon ? 0 : cap` (use `cap <= QuantityFormat.epsilon ? 0.0 : QuantityFormat.round(cap)` — see existing behavior `cap < 0 ? 0 : cap`); `wouldGoNegative`: `currentQuantity + change < -QuantityFormat.epsilon` (allows epsilon residue); maps `<String, double>`, `newQty <= 0` → `QuantityFormat.isZeroQty(newQty) || newQty < 0`, cap check `QuantityFormat.exceedsQty(newQty, cap)`.

- [ ] **Step 3: Run policy test**

Run: `flutter test test/helpers/suppliers_stock_policy_test.dart --reporter compact` → PASS.

- [ ] **Step 4: Sweep services (compile-driven)**

Apply exactly the changes listed under Files. Firestore parses become:
```dart
quantity: (data['quantity'] as num?)?.toDouble() ?? 0.0,
```
Params `required int quantity` → `required double quantity` (database_service L587/622/658/706/1113/1152; firebase_service L936/1036/1496; sync_service L1310/1466). Int folds → `fold(0.0, ...)`. Zero equality → `QuantityFormat.isZeroQty(...)` or `<= 0` per site. `receipt_renderer` lines format: `'${QuantityFormat.quantity(item.quantity)} x ...'`.

- [ ] **Step 5: Full test pass**

Run: `flutter test --reporter compact > test_full.log; Get-Content test_full.log | Select-Object -Last 5`
Expected: All helper/model tests pass; widget tests may still fail on UI int parsing — those are fixed in Tasks 8-12. If a *non-UI* test fails on int literals, fix the literal (`5` → `5.0`).

- [ ] **Step 6: Commit**

```bash
git add lib/services lib/helpers/suppliers_stock_policy.dart test/helpers/suppliers_stock_policy_test.dart
git commit -m "feat: services and stock policy decimal quantities, num-tolerant Firestore reads"
```

---

### Task 7: Helpers — top products + report test literals

**Files:**
- Modify: `lib/helpers/top_products_helper.dart` (`TopProduct.quantity` → double; maps `<String, double>`; netQty double)
- Modify: `test/helpers/top_products_helper_test.dart`, `test/helpers/reports_helper_test.dart` (helper sigs `int qty` → `double qty`; literals)
- Modify: `test/helpers/low_stock_helper_test.dart`, `test/widgets/low_stock_sheet_test.dart` (Product ctor literals → doubles)
- Test: updated files above

**Interfaces:**
- Produces: `TopProduct.quantity` is `double`.

- [ ] **Step 1: Update tests (failing)** — change `int qty`/`int quantity` params and literals to double (`5` → `5.0`; expectations `expect(result[0].quantity, 5)` → `5.0`).

Run: `flutter test test/helpers/top_products_helper_test.dart test/helpers/reports_helper_test.dart test/helpers/low_stock_helper_test.dart --reporter compact` → FAIL (compile).

- [ ] **Step 2: Implement** — apply type changes listed in Files (`low_stock_helper.dart` L28 `== 0` → `QuantityFormat.isZeroQty(product.quantity)`; L30 unchanged).

- [ ] **Step 3: Run tests** → PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/helpers/top_products_helper.dart lib/helpers/low_stock_helper.dart test/helpers test/widgets/low_stock_sheet_test.dart
git commit -m "feat: helpers decimal quantities"
```

---

### Task 8: Product form dialog — unit selector + decimal stock input

**Files:**
- Modify: `lib/widgets/inventory/product_form_dialog.dart`
- Modify: `assets/translations/ar.json`, `en.json`, `fr.json` (add `product.unit_label`, `product.unit_piece`, `product.unit_kg`, `product.unit_liter`)
- Test: `test/widgets/product_form_dialog_test.dart` (create)

**Interfaces:**
- Consumes: `Product.isWeighted`, `Product.unit`, `ProductFormData` (below), `QuantityFormat`.
- Produces: `class ProductFormData { ..., double quantity; String unit; }` consumed by `inventory_screen.dart` L335-356 and `_sync.addProduct/updateProduct` calls (quantity: double now).

Translations:
```json
// ar.json (inside "product" object)
"unit_label": "وحدة البيع", "unit_piece": "قطعة", "unit_kg": "كيلوغرام", "unit_liter": "لتر"
// en.json
"unit_label": "Selling unit", "unit_piece": "Piece", "unit_kg": "Kilogram", "unit_liter": "Liter"
// fr.json
"unit_label": "Unité de vente", "unit_piece": "Pièce", "unit_kg": "Kilogramme", "unit_liter": "Litre"
```

- [ ] **Step 1: Write the failing widget test**

```dart
// test/widgets/product_form_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/widgets/inventory/product_form_dialog.dart';

void main() {
  testWidgets('form parses decimal quantity and unit', (tester) async {
    ProductFormData? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () async {
              captured = await showDialog<ProductFormData>(
                context: ctx, builder: (_) => const ProductFormDialog(),
              );
            },
            child: const Text('open'),
          ),
        )),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('product_quantity_field')), '12.5');
    await tester.tap(find.byKey(const Key('product_unit_kg')));
    await tester.tap(find.byKey(const Key('product_form_save')));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.quantity, 12.5);
    expect(captured!.unit, 'kg');
  });
}
```

(Adapt finder keys to the dialog's actual save button; add `Key('product_quantity_field')`, `Key('product_unit_kg')`, `Key('product_form_save')` keys in implementation.)

- [ ] **Step 2: Run to verify FAIL** — `flutter test test/widgets/product_form_dialog_test.dart --reporter compact`.

- [ ] **Step 3: Implement dialog changes**
  - `ProductFormData.quantity` → `double`; add `String unit` field (default `'piece'`).
  - Quantity TextFormField (L286-307): `keyboardType: const TextInputType.numberWithOptions(decimal: true)`, replace `FilteringTextInputFormatter.digitsOnly` with a decimal formatter allowing digits + one `.`:
    ```dart
    TextInputFormatter decimalFormatter() => TextInputFormatter.withFunction(
          (oldValue, newValue) {
            final t = newValue.text;
            final dotCount = '.'.allMatches(t).length;
            final ok = dotCount <= 1 && RegExp(r'^\d*\.?\d{0,3}$').hasMatch(t);
            return ok ? newValue : oldValue;
          },
        );
    ```
  - Validator: `final v = double.tryParse(t); if (v == null || v < 0) ...` else round `QuantityFormat.round(v)`.
  - Add a unit `SegmentedButton<String>` (or 3 choice chips) with keys `product_unit_piece|kg|liter`, labels from the new translation keys; bind to dialog state; default from `product?.unit ?? 'piece'`.
  - Parse on save: `quantity: QuantityFormat.round(double.parse(_quantityController.text))`, `unit: selectedUnit`.

- [ ] **Step 4: Run test → PASS.** Also run `flutter test test/widgets --reporter compact` to catch regressions.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/inventory/product_form_dialog.dart assets/translations test/widgets/product_form_dialog_test.dart
git commit -m "feat: product form supports units and decimal stock"
```

---

### Task 9: POS weighted quantity sheet + cart line formatting

**Files:**
- Create: `lib/widgets/pos/weighted_quantity_sheet.dart`
- Modify: `lib/screens/pos_screen.dart` (grid onTap L1643-1660 branch; new-product dialog L371-431 double parsing + decimal keyboard; barcode add path L178 unchanged)
- Modify: `assets/translations/` ×3 (add `pos.weighted_qty_title`, `pos.weighted_price_per`, `pos.weighted_add`)
- Test: `test/widgets/weighted_quantity_sheet_test.dart`

**Interfaces:**
- Consumes: `Product.isWeighted`, `QuantityFormat`, `CartService.addProduct(product, quantity: double)`.
- Produces:

```dart
/// يعرض ورقة إدخال الكمية للمنتج الموزون.
/// يعيد الكمية المقبولة أو null عند الإلغاء/الخروج بالمخزون.
Future<double?> showWeightedQuantitySheet(
  BuildContext context, {
  required Product product,
  required String currency,
});
```

Translations:
```json
// ar.json (inside "pos")
"weighted_qty_title": "أدخل الكمية", "weighted_price_per": "{price} دج / {unit}", "weighted_add": "إضافة للسلة"
// en.json
"weighted_qty_title": "Enter quantity", "weighted_price_per": "{price} DZD / {unit}", "weighted_add": "Add to cart"
// fr.json
"weighted_qty_title": "Saisir la quantité", "weighted_price_per": "{price} DA / {unit}", "weighted_add": "Ajouter au panier"
```
(`{unit}` filled with `LocalizationHelper.unitLabel(product.unit)`.)

- [ ] **Step 1: Write the failing widget test**

```dart
// test/widgets/weighted_quantity_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/product_model.dart';
import 'package:pos_app/widgets/pos/weighted_quantity_sheet.dart';

Product weighted() => Product(
      id: 'p1', name: 'Oil', category: 'G', price: 800,
      quantity: 10.0, userId: 'u1', unit: 'kg',
    );

void main() {
  testWidgets('accepts decimal quantity and returns it', (tester) async {
    double? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await showWeightedQuantitySheet(
                ctx, product: weighted(), currency: 'DZD',
              );
            },
            child: const Text('open'),
          ),
        )),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('weighted_qty_field')), '0.85');
    await tester.tap(find.byKey(const Key('weighted_add_btn')));
    await tester.pumpAndSettle();

    expect(result, 0.85);
  });

  testWidgets('blocks quantity above stock', (tester) async {
    double? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await showWeightedQuantitySheet(
                ctx, product: weighted(), currency: 'DZD',
              );
            },
            child: const Text('open'),
          ),
        )),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('weighted_qty_field')), '99');
    await tester.tap(find.byKey(const Key('weighted_add_btn')));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.byKey(const Key('weighted_add_btn')), findsOneWidget); // sheet still open
  });

  testWidgets('quick chips insert values', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () async {
              await showWeightedQuantitySheet(
                ctx, product: weighted(), currency: 'DZD',
              );
            },
            child: const Text('open'),
          ),
        )),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('weighted_chip_0.5')));
    await tester.pumpAndSettle();
    expect(find.text('0.5'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify FAIL.**

- [ ] **Step 3: Implement the sheet**

```dart
// lib/widgets/pos/weighted_quantity_sheet.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../helpers/localization_helper.dart';
import '../../helpers/quantity_format.dart';
import '../../models/product_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/design_tokens.dart';

/// ورقة إدخال الكمية للمنتجات الموزونة (kg/litre): لوحة عشرية،
/// سعر الوحدة، الإجمالي الحي، وأزرار سريعة (0.25/0.5/1).
Future<double?> showWeightedQuantitySheet(
  BuildContext context, {
  required Product product,
  required String currency,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _WeightedQuantitySheet(product: product, currency: currency),
  );
}

class _WeightedQuantitySheet extends StatefulWidget {
  final Product product;
  final String currency;
  const _WeightedQuantitySheet({required this.product, required this.currency});

  @override
  State<_WeightedQuantitySheet> createState() => _WeightedQuantitySheetState();
}

class _WeightedQuantitySheetState extends State<_WeightedQuantitySheet> {
  final _controller = TextEditingController(text: '');
  double get _qty => double.tryParse(_controller.text) ?? 0.0;
  bool get _overStock => QuantityFormat.exceedsQty(_qty, widget.product.quantity);
  bool get _valid => QuantityFormat.greaterThanQty(_qty, 0) && !_overStock;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setQty(double v) {
    setState(() => _controller.text = QuantityFormat.quantity(v));
  }

  @override
  Widget build(BuildContext context) {
    final unitLabel = LocalizationHelper.unitLabel(widget.product.unit);
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.product.name, style: AppTextStyles.headline4()),
          const SizedBox(height: 4),
          Text(
            'pos.weighted_price_per'
                .tr(namedArgs: {
                  'price': widget.product.price.toStringAsFixed(0),
                  'unit': unitLabel,
                }),
            style: AppTextStyles.bodyMedium(color: AppColors.grey500),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('weighted_qty_field'),
            controller: _controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
            ],
            decoration: InputDecoration(
              suffixText: unitLabel,
              errorText: _overStock
                  ? '${LocalizationHelper.posOutOfStockFeedback} (${QuantityFormat.quantity(widget.product.quantity)} $unitLabel)'
                  : null,
            ),
            style: AppTextStyles.headline3(),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final v in const [0.25, 0.5, 1.0])
                OutlinedButton(
                  key: Key('weighted_chip_$v'),
                  onPressed: () => _setQty(v),
                  child: Text(QuantityFormat.quantity(v)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(LocalizationHelper.posTotal,
                  style: AppTextStyles.bodyMedium(color: AppColors.grey500)),
              Text(
                '${(_qty * widget.product.price).toStringAsFixed(2)} ${widget.currency}',
                style: AppTextStyles.headline3(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('weighted_add_btn'),
            onPressed: _valid
                ? () => Navigator.pop(
                    context, QuantityFormat.round(_qty))
                : null,
            child: Text('pos.weighted_add'.tr()),
          ),
        ],
      ),
    );
  }
}
```

Note: verify exact style/color names against `lib/theme/` (`AppTextStyles.headline3`, `AppColors.grey500`, `DesignTokens`) and `LocalizationHelper.posTotal` — if `posTotal` doesn't exist, use the existing total label key used by the cart (`grep "total" lib/helpers/localization_helper.dart` and pick the POS total label).

- [ ] **Step 4: Wire the grid tap branch (pos_screen.dart L1643-1660)**

Replace the onTap body:

```dart
onTap: () async {
  if (product.quantity <= 0) {
    ScannerFeedbackService.outOfStock();
    _showSnackBar(LocalizationHelper.posOutOfStockFeedback, AppColors.error);
    return;
  }
  if (!product.isWeighted) {
    context.read<CartService>().addProduct(product);
    _showSnackBar('${product.name} ${LocalizationHelper.posAdded}', AppColors.success);
    return;
  }
  final qty = await showWeightedQuantitySheet(
    context, product: product, currency: _currency,
  );
  if (qty == null || !mounted) return;
  context.read<CartService>().addProduct(product, quantity: qty);
  _showSnackBar('${product.name} ${LocalizationHelper.posAdded}', AppColors.success);
},
```

Also update the new-product dialog (L371-390 + L431): decimal keyboard + `double.tryParse` validation + `quantity: QuantityFormat.round(double.parse(...))`, and `_addNewProductFromPOS` param → `double quantity` (L467). Cart line displays (L878, L1104): `'x${QuantityFormat.quantity(item.quantity)}'` / `QuantityFormat.quantity(item.quantity)`.

- [ ] **Step 5: Run tests → PASS**, plus `flutter test test/widgets --reporter compact`.

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/pos/weighted_quantity_sheet.dart lib/screens/pos_screen.dart assets/translations test/widgets/weighted_quantity_sheet_test.dart
git commit -m "feat: weighted product quantity sheet at POS"
```

---

### Task 10: Purchase screen — decimal quantities

**Files:**
- Modify: `lib/screens/purchase_screen.dart` (L69-70 fold seed `0.0`; L108-109/162-163 stepper `+1` text via `QuantityFormat.quantity`; L127 `double.tryParse`; L132 clamp `0.0`; L268 `quantity: 0.0`; L611 `decimal: true` + decimal formatter; L703-717 defaults `1.0` / `0.0`; L731 field double)
- Test: existing purchase-related tests keep passing.

**Interfaces:**
- Consumes: `QuantityFormat`, `PurchaseItem(quantity: double)`.

- [ ] **Step 1: Apply changes** exactly as listed (stepper `+1` still adds 1.0 — for weighted lines the text field is the primary entry).
- [ ] **Step 2: Run** `flutter test test/screens 2>/dev/null; flutter test --reporter compact test/models test/helpers --reporter compact` and `dart analyze lib/screens/purchase_screen.dart` → clean.
- [ ] **Step 3: Commit**

```bash
git add lib/screens/purchase_screen.dart
git commit -m "feat: decimal quantities in purchase screen"
```

---

### Task 11: Supplier return screen — fractional returns

**Files:**
- Modify: `lib/screens/supplier_return_screen.dart` (L31 `double cap`; L49 `Map<String, double>`; L58-64 accumulation 0.0; L111-118 `_setQty(_Row row, double value)`; L134-142 PurchaseItem double; L219-221 formatter → decimal-allowing (same `TextInputFormatter.withFunction` as Task 8 with `{0,3}` decimals); L225 `double.tryParse`; L226-229 clamp via `QuantityFormat`; steppers L210/L248 `qty - 1` / `qty + 1` doubles)
- Test: `test/helpers/suppliers_stock_policy_test.dart` already covers caps; manual verification via analyzer + full suite.

- [ ] **Step 1: Apply changes.**
- [ ] **Step 2: Run** `dart analyze lib/screens/supplier_return_screen.dart` → clean; `flutter test test/helpers/suppliers_stock_policy_test.dart --reporter compact` → PASS.
- [ ] **Step 3: Commit**

```bash
git add lib/screens/supplier_return_screen.dart
git commit -m "feat: fractional supplier returns"
```

---

### Task 12: Sales history — fractional customer returns for weighted items

**Files:**
- Modify: `lib/screens/sales_history_screen.dart` (return dialog L490-584: for `availableItems[i]` belonging to a weighted product, replace the checkbox-only row with checkbox **plus** an editable qty TextField prefilled with `item.quantity`, keyed per item id; decimal formatter; validate `0 < qty ≤ item.quantity` with epsilon; selectedItems built from entered qty — L320-328 SaleItem construction uses the entered value)
- Modify: `assets/translations/` ×3 (add `sales_history.return_qty_hint`: "الكمية المرتجعة" / "Return quantity" / "Quantité retournée")
- Test: `test/helpers/reports_helper_test.dart` covers negative buckets; add helper test for return-cap math already done (Task 3). Widget-level manual verification.

**Interfaces:**
- Consumes: `Sale.availableForReturn` (double), `QuantityFormat`, `Product.isWeighted` (fetch product by `item.productId` via `DatabaseService.instance.getProductById` — fall back to `'piece'` when product deleted, checkbox-only behavior).

- [ ] **Step 1: Implement.** Row layout for weighted items: keep checkbox (toggles between full qty and 0), add 90px TextField prefilled with full available qty; on confirm, use `QuantityFormat.round(entered)` per selected item; guard `QuantityFormat.exceedsQty(qty, item.quantity)` → show error, do not close.
- [ ] **Step 2: Verify** — `dart analyze lib/screens/sales_history_screen.dart` → clean; run return-flow tests: `flutter test test/helpers test/models --reporter compact` → PASS.
- [ ] **Step 3: Commit**

```bash
git add lib/screens/sales_history_screen.dart assets/translations
git commit -m "feat: fractional customer returns for weighted items"
```

---

### Task 13: Display formatting sweep

**Files (quantity display sites → `QuantityFormat.quantity(...)`; badge counts keep raw double):**
- `lib/screens/inventory_screen.dart` L932 → `QuantityFormat.quantity(product.quantity)` + suffix ` LocalizationHelper.unitLabel(product.unit)`
- `lib/screens/purchases_history_screen.dart` L332 → wrap `item.quantity`
- `lib/screens/dashboard_screen.dart` L488 → wrap `item.quantity`
- `lib/screens/main_screen.dart` L470 → wrap `cartService.totalItems` (badge shows "3" or "3.5")
- `lib/widgets/pos/checkout_confirmation_sheet.dart` L183, L292 → wrap
- `lib/widgets/low_stock_sheet.dart` L295 → wrap + unit suffix
- `lib/widgets/pos/payment_method_sheet.dart` L176, `lib/widgets/pos/held_orders.dart` L54/L204 → wrap totalItems
- `lib/widgets/pos/product_grid_item.dart` L26 `== 0` → `QuantityFormat.isZeroQty(product.quantity)`

- [ ] **Step 1: Apply wraps.** Cart/checkout lines for weighted items read `0.85 kg × 800 = 680 DZD` via `QuantityFormat.withUnit(item.quantity, LocalizationHelper.unitLabel(item.product.unit))` where a unit suffix fits (checkout sheet + cart line L878 already done in Task 9).
- [ ] **Step 2: Run** `dart analyze lib` → clean (whole-lib gate for the first time).
- [ ] **Step 3: Full suite** — `flutter test --reporter compact > full.log; Get-Content full.log | Select-Object -Last 5` → All tests pass.
- [ ] **Step 4: Commit**

```bash
git add lib/screens lib/widgets
git commit -m "feat: decimal quantity display formatting across screens"
```

---

### Task 14: End-to-end verification + final analyzer gate

- [ ] **Step 1: Full analyzer** — `dart analyze lib test` → No issues.
- [ ] **Step 2: Full suite** — `flutter test --reporter compact > full.log; Get-Content full.log | Select-Object -Last 5` → All tests pass.
- [ ] **Step 3: Manual smoke (optional, on device/emulator):** create kg product → sell 0.85 kg → check cart total 680, stock 9.15 → partial return 0.3 → stock 9.45 → purchase +25.5 kg → stock 34.95 → receipt shows `0.850 kg × 800.00`.
- [ ] **Step 4: Final commit if any stragglers, push:**

```bash
git add -A
git commit -m "feat: weighted products complete (kg/litre sales, decimal stock, fractional returns)"
git push origin master
```

---

## Self-Review Notes

- **Spec coverage:** unit field + no-barcode (Task 2), decimal stock (2,6), POS sheet (9), fractional returns (3,11,12), decimal purchases (10), 3-decimal rounding + display (1,13), reports/top-products (7), migration tolerance (2-4 adapters), tests throughout. Operational constraint (all devices update together) is deployment-side, noted in spec.
- **Type consistency:** `Map<String, double>` return accumulators and `SuppliersStockPolicy` double signatures defined in Task 6, consumed in Task 11/12; `showWeightedQuantitySheet` signature defined in Task 9 only; `QuantityFormat` API from Task 1 used everywhere.
- **Placeholders:** none — every code step carries its content.
