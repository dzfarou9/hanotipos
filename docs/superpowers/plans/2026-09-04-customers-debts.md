# Customers & Debt Ledger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a customers module, debt ledger, and "الدين" payment method to the POS system. Customers are stored in a new Hive box, debts and payments in another, with Firestore sync following the existing write-through + `isSynced` dirty-flag pattern.

**Architecture:** Unified append-only `DebtTransaction` model (typeId 9) with a `type` discriminator (`debt`/`payment`/`adjustment`) and signed amounts. `Customer` (typeId 8) mirrors `Supplier`. FIFO-only allocation in a pure `debt_ledger_helper.dart`. Sale gains `customerId` (HiveField 17). Sync is insert-only for ledger rows (like `InventoryMovement`), LWW on `updatedAt` for customers (like `Supplier`).

**Tech Stack:** Flutter 3.44.9 / Dart 3.12.2, Hive 2.2.3, Provider 6.1.5, easy_localization 3.0.8, Firebase Firestore, connectivity_plus 6.1.5.

**Spec:** `docs/superpowers/specs/2026-09-04-customers-debts-design.md`

## Global Constraints

- Hive typeIds used: 0, 2, 3, 4, 5, 6, 7, 20, 21. **1 is permanently unused.** Free: 8, 9, 10–19, 22–223. Enums at 20+.
- `Customer` = typeId 8, `DebtTransaction` = typeId 9, `DebtTransactionType` = typeId 22 (hand-written adapter, same reason as `inventory_movement_enum_adapters.dart`).
- All new Hive boxes **must** be added to `_allBoxNames`, `clearUserData()`, and `closeBoxes()` in `database_service.dart`, or they leak across accounts / break the encryption migration.
- Every Firestore query needs `where('user_id', isEqualTo: uid)` — the rules reject queries without it.
- Arabic text renders correctly, but RTL is **disabled** (`direction_helper.dart` always returns LTR). Use `left`/`right` freely.
- All UI strings go into `ar.json`/`en.json`/`fr.json` under a new `customers` section and a `payment.debt` key. No hardcoded Arabic.
- `flutter analyze` must be clean (0 new errors, 0 new warnings) and `flutter test` must stay at 112+ passing before any "complete" claim.
- **No git commits** — the project isn't a git repo yet (`AGENTS.md`). Validation replaces the commit step: `flutter analyze` + `flutter test` passes.

## File Structure

### New files

| File | Responsibility |
|---|---|
| `lib/models/customer_model.dart` | Customer Hive type (typeId 8), `fromJson`/`toJson`/`fromFirestore` |
| `lib/models/debt_transaction_model.dart` | DebtTransaction Hive type (typeId 9), `DebtTransactionType` enum |
| `lib/models/debt_transaction_enum_adapter.dart` | Hand-written adapter for `DebtTransactionType` (typeId 22) |
| `lib/helpers/debt_ledger_helper.dart` | Pure FIFO math, `CustomerLedger`, `DebtEntry`, `buildCustomerLedger` |
| `lib/screens/customers_screen.dart` | Customer list with search, filter tabs, balance per row |
| `lib/screens/customer_detail_screen.dart` | Debt ledger, two tabs (debts / history), payment + manual debt sheets |
| `lib/widgets/customers/customer_picker_sheet.dart` | POS customer picker — search + "عميل جديد" |
| `test/helpers/debt_ledger_helper_test.dart` | FIFO classifier tests, ~11 cases |
| `test/models/customer_debt_model_test.dart` | Hive round-trip, JSON symmetry |
| `test/widgets/customers_screen_test.dart` | Empty state, list renders, search |

### Modified files

| File | What changes |
|---|---|
| `lib/models/sale_model.dart` | Add `@HiveField(17) String? customerId` |
| `lib/models/inventory_movement_enum_adapters.dart` | Append `DebtTransactionTypeAdapter` registration |
| `lib/services/database_service.dart` | +2 boxes, +2 lifecycle entries, +CRUD methods, +debt index, +ledger cache |
| `lib/config/firebase_config.dart` | +2 collection constants |
| `lib/services/firebase_service.dart` | +9 methods (add/update/delete/batch/get for customers + debt transactions) |
| `lib/services/sync_service.dart` | +3 push/pull/tombstone blocks, +write-through methods, +`addSale` parameters |
| `lib/helpers/localization_helper.dart` | +`paymentDebt` getter, +`case 'Debt'` in `paymentMethod()`, +`dashboardWalkIn` getter |
| `lib/widgets/dashboard_menu.dart` | +1 `_buildNavRow` for customers |
| `lib/screens/pos_screen.dart` | +1 `_buildPaymentOption` for الدين, +customer picker, +`paidNow` |
| `lib/widgets/pos/checkout_confirmation_sheet.dart` | +customer name + credit rows in receipt |
| `lib/helpers/reports_helper.dart` | +`debtsTotal` parameter, real computation |
| `lib/screens/reports_screen.dart` | Drop "قريباً" subtitle on debts tile |
| `firestore.rules` | +4-line blocks for both collections, +type validation on `debt_transactions` |
| `firestore.indexes.json` | +2 composite indexes |
| `assets/translations/ar.json` | +`customers` section, +`payment.debt` |
| `assets/translations/en.json` | +`customers` section, +`payment.debt` |
| `assets/translations/fr.json` | +`customers` section, +`payment.debt` |
| `test/widgets/dashboard_menu_test.dart` | Update 5→6 chevrons, +`Icons.people_rounded` |

---

### Task 1: Customer and DebtTransaction models + enum adapter + build_runner

**Files:**
- Create: `lib/models/customer_model.dart`
- Create: `lib/models/debt_transaction_model.dart`
- Create: `lib/models/debt_transaction_enum_adapter.dart`
- Create: `test/models/customer_debt_model_test.dart`
- Modify: `lib/models/inventory_movement_enum_adapters.dart` (add registration)
- Other: `lib/models/customer_model.g.dart` and `lib/models/debt_transaction_model.g.dart` (generated by build_runner)

**Interfaces:**
- Produces: `Customer` (typeId 8), `DebtTransaction` (typeId 9), `DebtTransactionType` (typeId 22, hand-written adapter)
- `Customer.fromJson(Map)`, `Customer.toJson()`, `Customer.fromFirestore(DocumentSnapshot)`
- `DebtTransaction.fromJson(Map)`, `DebtTransaction.toJson()`, `DebtTransaction.fromFirestore(DocumentSnapshot)`
- `DebtTransactionType` enum: `debt, payment, adjustment`

- [ ] **Step 1: Write `lib/models/customer_model.dart` — mirroring `supplier_model.dart`**

```dart
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'customer_model.g.dart';

@HiveType(typeId: 8)
class Customer extends HiveObject {
  @HiveField(0) final String id;
  @HiveField(1) String name;
  @HiveField(2) String? phone;
  @HiveField(3) String? address;
  @HiveField(4) String? notes;
  @HiveField(5) final String userId;
  @HiveField(6) bool isSynced;
  @HiveField(7) final DateTime createdAt;
  @HiveField(8) DateTime updatedAt;

  Customer({
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
    if (value is String) { try { return DateTime.parse(value); } catch (_) { return null; } }
    if (value is DateTime) return value;
    return null;
  }

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
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

  factory Customer.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Customer.fromJson({...data, 'id': doc.id, 'is_synced': true});
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id, 'name': name, 'phone': phone, 'address': address, 'notes': notes,
      'user_id': userId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
```

- [ ] **Step 2: Write `lib/models/debt_transaction_model.dart`**

```dart
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'debt_transaction_model.g.dart';

enum DebtTransactionType { debt, payment, adjustment }

@HiveType(typeId: 9)
class DebtTransaction extends HiveObject {
  @HiveField(0) final String id;
  @HiveField(1) final String customerId;
  @HiveField(2) final DebtTransactionType type;
  @HiveField(3) final double amount;
  @HiveField(4) final String? saleId;
  @HiveField(5) final String? note;
  @HiveField(6) final String userId;
  @HiveField(7) bool isSynced;
  @HiveField(8) final DateTime createdAt;
  @HiveField(9) DateTime updatedAt;

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
    if (value is String) { try { return DateTime.parse(value); } catch (_) { return null; } }
    if (value is DateTime) return value;
    return null;
  }

  factory DebtTransaction.fromJson(Map<String, dynamic> json) {
    return DebtTransaction(
      id: json['id'] as String,
      customerId: json['customer_id'] as String? ?? '',
      type: _parseType(json['type'] as String? ?? 'debt'),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      saleId: json['sale_id'] as String?,
      note: json['note'] as String?,
      userId: json['user_id'] as String? ?? '',
      isSynced: true,
      createdAt: _parseTimestamp(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseTimestamp(json['updated_at']) ?? DateTime.now(),
    );
  }

  static DebtTransactionType _parseType(String value) {
    switch (value) {
      case 'payment': return DebtTransactionType.payment;
      case 'adjustment': return DebtTransactionType.adjustment;
      default: return DebtTransactionType.debt;
    }
  }

  factory DebtTransaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DebtTransaction.fromJson({...data, 'id': doc.id, 'is_synced': true});
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id, 'customer_id': customerId, 'type': type.name, 'amount': amount,
      'sale_id': saleId, 'note': note, 'user_id': userId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
```

- [ ] **Step 3: Write `lib/models/debt_transaction_enum_adapter.dart`**

```dart
import 'package:hive/hive.dart';
import 'debt_transaction_model.dart';

class DebtTransactionTypeAdapter extends TypeAdapter<DebtTransactionType> {
  @override
  final int typeId = 22;

  @override
  DebtTransactionType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0: return DebtTransactionType.debt;
      case 1: return DebtTransactionType.payment;
      case 2: return DebtTransactionType.adjustment;
      default: return DebtTransactionType.debt;
    }
  }

  @override
  void write(BinaryWriter writer, DebtTransactionType obj) {
    switch (obj) {
      case DebtTransactionType.debt: writer.writeByte(0);
      case DebtTransactionType.payment: writer.writeByte(1);
      case DebtTransactionType.adjustment: writer.writeByte(2);
    }
  }
}
```

- [ ] **Step 4: Add `import` and register to `lib/models/inventory_movement_enum_adapters.dart`**

Add `import 'debt_transaction_model.dart';` and `import 'debt_transaction_enum_adapter.dart';` at the top. This file is where all hand-written enum adapters live.

- [ ] **Step 5: Add `@HiveField(17) final String? customerId;` to `lib/models/sale_model.dart`**

Insert after field 16 (`isFullyReturned`). Update constructor parameter list to include `this.customerId`. Add to `fromJson`/`toJson`/`fromFirestore`.

- [ ] **Step 6: Run build_runner**

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

Verify `lib/models/customer_model.g.dart`, `lib/models/debt_transaction_model.g.dart`, and `lib/models/sale_model.g.dart` are generated/updated.

- [ ] **Step 7: Write `test/models/customer_debt_model_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/debt_transaction_model.dart';
import 'package:pos_app/models/customer_model.dart';

void main() {
  group('Customer JSON roundtrip', () {
    test('toJson then fromJson preserves fields', () {
      final now = DateTime(2026, 9, 4, 10);
      final c = Customer(
        id: 'c1', name: 'محمد', phone: '0555000111',
        address: 'الجزائر', notes: 'زبون مهم',
        userId: 'u1', isSynced: false, createdAt: now, updatedAt: now,
      );
      final restored = Customer.fromJson(c.toJson());
      expect(restored.id, 'c1');
      expect(restored.name, 'محمد');
      expect(restored.phone, '0555000111');
      expect(restored.userId, 'u1');
      expect(restored.createdAt, now);
    });

    test('fromJson tolerates null optionals', () {
      final map = {
        'id': 'c2', 'name': 'x', 'user_id': 'u1',
        'created_at': '2026-01-01T00:00:00.000',
        'updated_at': '2026-01-01T00:00:00.000',
      };
      final c = Customer.fromJson(map);
      expect(c.phone, isNull);
      expect(c.address, isNull);
      expect(c.notes, isNull);
    });
  });

  group('DebtTransaction JSON roundtrip', () {
    test('debt roundtrips', () {
      final now = DateTime(2026, 9, 4, 10);
      final t = DebtTransaction(
        id: 't1', customerId: 'c1', type: DebtTransactionType.debt,
        amount: 5000, saleId: 's1', note: null,
        userId: 'u1', createdAt: now, updatedAt: now,
      );
      final restored = DebtTransaction.fromJson(t.toJson());
      expect(restored.id, 't1');
      expect(restored.type, DebtTransactionType.debt);
      expect(restored.amount, 5000);
      expect(restored.saleId, 's1');
    });

    test('payment roundtrips', () {
      final t = DebtTransaction(
        id: 't2', customerId: 'c1', type: DebtTransactionType.payment,
        amount: -2000, saleId: null, note: 'دفعة',
        userId: 'u1',
      );
      final restored = DebtTransaction.fromJson(t.toJson());
      expect(restored.type, DebtTransactionType.payment);
      expect(restored.amount, -2000);
      expect(restored.note, 'دفعة');
    });
  });
}
```

- [ ] **Step 8: Validate**

```bash
flutter test test/models/customer_debt_model_test.dart -v
flutter analyze
```

Expected: **all tests pass**, **0 new errors/warnings**.

---

### Task 2: Debt ledger helper (pure FIFO math)

**Files:**
- Create: `lib/helpers/debt_ledger_helper.dart`
- Create: `test/helpers/debt_ledger_helper_test.dart`

**Interfaces:**
- Produces: `DebtState` enum, `DebtEntry` class, `CustomerLedger` class, `buildCustomerLedger(List<DebtTransaction>) → CustomerLedger`, `computeTotalDebt(List<DebtTransaction>) → double`
- `DebtState { unpaid, partiallyPaid, paid }`
- `CustomerLedger { totalDebt, totalPaid, balance, creditBalance, debts, unpaidCount, partiallyPaidCount, paidCount }`

- [ ] **Step 1: Write `lib/helpers/debt_ledger_helper.dart`**

```dart
const double _debtEpsilon = 0.001;

enum DebtState { unpaid, partiallyPaid, paid }

class DebtEntry {
  final DebtTransaction debt;
  final double paidAmount;
  final double remainingAmount;
  final DebtState state;

  const DebtEntry({
    required this.debt,
    required this.paidAmount,
    required this.remainingAmount,
    required this.state,
  });
}

class CustomerLedger {
  final double totalDebt;
  final double totalPaid;
  final double balance;
  final double creditBalance;
  final List<DebtEntry> debts;
  final int unpaidCount;
  final int partiallyPaidCount;
  final int paidCount;

  const CustomerLedger({
    required this.totalDebt,
    required this.totalPaid,
    required this.balance,
    required this.creditBalance,
    required this.debts,
    required this.unpaidCount,
    required this.partiallyPaidCount,
    required this.paidCount,
  });
}

CustomerLedger buildCustomerLedger(List<DebtTransaction> rows) {
  final debts = <DebtTransaction>[];
  double creditPool = 0.0;

  for (final r in rows) {
    switch (r.type) {
      case DebtTransactionType.debt:
        debts.add(r);
        break;
      case DebtTransactionType.payment:
        creditPool += -r.amount; // payment is negative, flip to positive
        break;
      case DebtTransactionType.adjustment:
        // negative adjustment = credit, positive = extra debt
        if (r.amount < 0) {
          creditPool += -r.amount;
        } else {
          debts.add(r);
        }
    }
  }

  // Sort debts oldest-first
  debts.sort((a, b) => a.createdAt.compareTo(b.createdAt));

  double totalDebt = 0.0;
  double totalPaid = 0.0;
  double remainingPool = creditPool;
  final debtEntries = <DebtEntry>[];
  int unpaid = 0, partial = 0, paid = 0;

  for (final d in debts) {
    final debtAmount = d.amount.abs();
    totalDebt += debtAmount;
    final taken = remainingPool >= debtAmount
        ? debtAmount
        : (remainingPool > _debtEpsilon ? remainingPool : 0.0);
    remainingPool -= taken;
    totalPaid += taken;
    final remaining = debtAmount - taken;
    final state = remaining <= _debtEpsilon
        ? DebtState.paid
        : (taken > _debtEpsilon ? DebtState.partiallyPaid : DebtState.unpaid);
    if (state == DebtState.paid) paid++;
    else if (state == DebtState.partiallyPaid) partial++;
    else unpaid++;
    debtEntries.add(DebtEntry(
      debt: d,
      paidAmount: taken,
      remainingAmount: remaining,
      state: state,
    ));
  }

  // Reverse for display (newest first)
  debtEntries.sort((a, b) => b.debt.createdAt.compareTo(a.debt.createdAt));

  return CustomerLedger(
    totalDebt: totalDebt,
    totalPaid: totalPaid,
    balance: totalDebt - totalPaid,
    creditBalance: remainingPool > _debtEpsilon ? remainingPool : 0.0,
    debts: debtEntries,
    unpaidCount: unpaid,
    partiallyPaidCount: partial,
    paidCount: paid,
  );
}

double computeTotalDebt(List<DebtTransaction> allRows) {
  final byCustomer = <String, List<DebtTransaction>>{};
  for (final r in allRows) {
    byCustomer.putIfAbsent(r.customerId, () => []).add(r);
  }
  double total = 0.0;
  for (final group in byCustomer.values) {
    final ledger = buildCustomerLedger(group);
    if (ledger.balance > _debtEpsilon) {
      total += ledger.balance;
    }
  }
  return total;
}
```

- [ ] **Step 2: Write `test/helpers/debt_ledger_helper_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/helpers/debt_ledger_helper.dart';
import 'package:pos_app/models/debt_transaction_model.dart';

DebtTransaction _debt({required String id, required double amount, DateTime? createdAt}) {
  return DebtTransaction(
    id: id, customerId: 'c1', type: DebtTransactionType.debt,
    amount: amount, userId: 'u1', createdAt: createdAt,
  );
}

DebtTransaction _payment({required String id, required double amount, DateTime? createdAt}) {
  return DebtTransaction(
    id: id, customerId: 'c1', type: DebtTransactionType.payment,
    amount: -amount, userId: 'u1', createdAt: createdAt,
  );
}

DebtTransaction _adjustment({required String id, required double amount, DateTime? createdAt}) {
  return DebtTransaction(
    id: id, customerId: 'c1', type: DebtTransactionType.adjustment,
    amount: amount, userId: 'u1', createdAt: createdAt,
  );
}

void main() {
  group('buildCustomerLedger', () {
    test('empty ledger', () {
      final l = buildCustomerLedger([]);
      expect(l.totalDebt, 0.0);
      expect(l.balance, 0.0);
      expect(l.unpaidCount, 0);
      expect(l.debts, isEmpty);
    });

    test('single unpaid debt', () {
      final l = buildCustomerLedger([_debt(id: 'd1', amount: 5000)]);
      expect(l.totalDebt, 5000);
      expect(l.balance, 5000);
      expect(l.unpaidCount, 1);
      expect(l.debts.first.state, DebtState.unpaid);
    });

    test('partial payment', () {
      final l = buildCustomerLedger([
        _debt(id: 'd1', amount: 5000),
        _payment(id: 'p1', amount: 2000),
      ]);
      expect(l.totalDebt, 5000);
      expect(l.totalPaid, 2000);
      expect(l.balance, 3000);
      expect(l.partiallyPaidCount, 1);
      expect(l.debts.first.state, DebtState.partiallyPaid);
    });

    test('exact payment', () {
      final l = buildCustomerLedger([
        _debt(id: 'd1', amount: 5000),
        _payment(id: 'p1', amount: 5000),
      ]);
      expect(l.balance, 0.0);
      expect(l.paidCount, 1);
      expect(l.debts.first.state, DebtState.paid);
    });

    test('epsilon handles floating point', () {
      final l = buildCustomerLedger([
        _debt(id: 'd1', amount: 5000),
        _payment(id: 'p1', amount: 4999.9999),
      ]);
      expect(l.debts.first.state, DebtState.paid);
    });

    test('one payment spans two debts', () {
      final now = DateTime(2026, 9, 4);
      final l = buildCustomerLedger([
        _debt(id: 'd1', amount: 3000, createdAt: now.subtract(const Duration(days: 2))),
        _debt(id: 'd2', amount: 4000, createdAt: now.subtract(const Duration(days: 1))),
        _payment(id: 'p1', amount: 5000, createdAt: now),
      ]);
      expect(l.debts.length, 2);
      // FIFO: first debt (3000) gets 3000 = paid, second debt (4000) gets 2000 = partially paid
      expect(l.debts[1].state, DebtState.paid);   // oldest debt, newest-first display
      expect(l.debts[0].state, DebtState.partiallyPaid);
      expect(l.balance, 2000);
    });

    test('payment exceeding all debts creates credit balance', () {
      final l = buildCustomerLedger([
        _debt(id: 'd1', amount: 3000),
        _payment(id: 'p1', amount: 5000),
      ]);
      expect(l.balance, -2000);
      expect(l.creditBalance, 2000);
      expect(l.debts.first.state, DebtState.paid);
    });

    test('adjustment reduces debt', () {
      final l = buildCustomerLedger([
        _debt(id: 'd1', amount: 5000),
        _adjustment(id: 'a1', amount: -2000),
      ]);
      expect(l.balance, 3000);
      expect(l.debts.first.state, DebtState.partiallyPaid);
    });

    test('adjustment pushes balance negative', () {
      final l = buildCustomerLedger([
        _debt(id: 'd1', amount: 3000),
        _adjustment(id: 'a1', amount: -5000),
      ]);
      expect(l.balance, -2000);
      expect(l.creditBalance, 2000);
    });

    test('multiple payments with no debts', () {
      final l = buildCustomerLedger([
        _payment(id: 'p1', amount: 1000),
        _payment(id: 'p2', amount: 500),
      ]);
      expect(l.totalDebt, 0.0);
      expect(l.creditBalance, 1500);
      expect(l.balance, -1500);
      expect(l.debts, isEmpty);
    });
  });

  group('computeTotalDebt', () {
    test('aggregates across customers', () {
      final rows = [
        DebtTransaction(id: 'd1', customerId: 'c1', type: DebtTransactionType.debt, amount: 5000, userId: 'u1'),
        DebtTransaction(id: 'p1', customerId: 'c1', type: DebtTransactionType.payment, amount: -2000, userId: 'u1'),
        DebtTransaction(id: 'd2', customerId: 'c2', type: DebtTransactionType.debt, amount: 8000, userId: 'u1'),
        DebtTransaction(id: 'd3', customerId: 'c3', type: DebtTransactionType.debt, amount: 3000, userId: 'u1'),
        DebtTransaction(id: 'p3', customerId: 'c3', type: DebtTransactionType.payment, amount: -3000, userId: 'u1'),
      ];
      // c1: 3000, c2: 8000, c3: 0 → total 11000
      expect(computeTotalDebt(rows), 11000);
    });
  });
}
```

- [ ] **Step 3: Validate**

```bash
flutter test test/helpers/debt_ledger_helper_test.dart -v
```

Expected: **all 11+ tests pass**.

---

### Task 3: DatabaseService — boxes, lifecycle, CRUD

**Files:**
- Modify: `lib/services/database_service.dart`

**Interfaces:**
- Consumes: `Customer` (typeId 8), `DebtTransaction` (typeId 9)
- Produces: All customer + debt transaction CRUD methods, plus `_customerDebtIndex`, `_ledgerCache`, `getCustomerLedger(String customerId)`

- [ ] **Step 1: Add box name constants after `_purchasesBoxName` (`:26`)**

```dart
static const String _customersBoxName = 'customers';
static const String _debtTransactionsBoxName = 'debt_transactions';
```

Add to `_allBoxNames` (`:30-38`): `_customersBoxName, _debtTransactionsBoxName,`

- [ ] **Step 2: Add late fields after `_purchasesBox` (`:48`)**

```dart
late Box<Customer> _customersBox;
late Box<DebtTransaction> _debtTransactionsBox;
```

- [ ] **Step 3: Add `_customerDebtIndex` and `_ledgerCache` fields after `_barcodeIndex` (`:64`)**

```dart
Map<String, List<String>> _customerDebtIndex = <String, List<String>>{};
Map<String, CustomerLedger> _ledgerCache = <String, CustomerLedger>{};
```

- [ ] **Step 4: Register adapters after `:88`**

```dart
Hive.registerAdapter(CustomerAdapter());
Hive.registerAdapter(DebtTransactionAdapter());
Hive.registerAdapter(DebtTransactionTypeAdapter());
```

- [ ] **Step 5: Open boxes after `:110`**

```dart
_customersBox = await Hive.openBox<Customer>(_customersBoxName, encryptionCipher: cipher);
_debtTransactionsBox = await Hive.openBox<DebtTransaction>(_debtTransactionsBoxName, encryptionCipher: cipher);
```

- [ ] **Step 6: Build index after `_buildBarcodeIndex()` call (`:114`)**

```dart
_buildCustomerDebtIndex();
```

- [ ] **Step 7: Add `clearUserData` entries after `:329-330`**

```dart
await tryStep('customers', () => _customersBox.clear());
await tryStep('debt_transactions', () => _debtTransactionsBox.clear());
```

Add leftover checks after `:348`:
```dart
if (_customersBox.isNotEmpty) leftovers.add('customers=${_customersBox.length}');
if (_debtTransactionsBox.isNotEmpty) leftovers.add('debt_transactions=${_debtTransactionsBox.length}');
```

- [ ] **Step 8: Add `closeBoxes` entries after `:1480`**

```dart
await _customersBox.close();
await _debtTransactionsBox.close();
```

- [ ] **Step 9: Write customer CRUD methods (insert after the Supplier section, after `:1170`)**

```dart
// ==================== Customer Methods ====================

List<Customer> getAllCustomers() {
  return _customersBox.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

Customer? getCustomerById(String id) {
  try { return _customersBox.get(id); } catch (e) { return null; }
}

bool customerExists(String id) => _customersBox.containsKey(id);

List<Customer> getUnsyncedCustomers() {
  return _customersBox.values.where((c) => !c.isSynced).toList();
}

Future<void> addCustomerWithId({
  required String id, required String name, String? phone,
  String? address, String? notes, required String userId, bool isSynced = false,
}) async {
  final customer = Customer(
    id: id, name: name, phone: phone, address: address, notes: notes,
    userId: userId, isSynced: isSynced,
  );
  await _customersBox.put(customer.id, customer);
}

Future<void> updateCustomer({
  required String id, required String name, String? phone,
  String? address, String? notes,
}) async {
  final customer = _customersBox.get(id);
  if (customer != null) {
    customer.name = name;
    customer.phone = phone;
    customer.address = address;
    customer.notes = notes;
    customer.updatedAt = DateTime.now();
    customer.isSynced = false;
    await customer.save();
  }
}

Future<void> markCustomerAsSynced(String id) async {
  final customer = _customersBox.get(id);
  if (customer != null) {
    customer.isSynced = true;
    await customer.save();
  }
}

Future<void> deleteCustomerLocal(String id) async {
  await _customersBox.delete(id);
}

Future<void> deleteAllCustomers() async {
  await _customersBox.clear();
  _customerDebtIndex.clear();
  _ledgerCache.clear();
}

List<Customer> searchCustomers(String query) {
  final q = query.toLowerCase();
  return _customersBox.values.where((c) {
    return c.name.toLowerCase().contains(q) ||
        (c.phone?.toLowerCase().contains(q) ?? false);
  }).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}
```

- [ ] **Step 10: Write debt transaction CRUD + index + cache (after customer methods)**

```dart
// ==================== Debt Transaction Methods ====================

List<DebtTransaction> getAllDebtTransactions() {
  return _debtTransactionsBox.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

DebtTransaction? getDebtTransactionById(String id) {
  try { return _debtTransactionsBox.get(id); } catch (e) { return null; }
}

List<DebtTransaction> getDebtTransactionsByCustomer(String customerId) {
  final ids = _customerDebtIndex[customerId];
  if (ids == null || ids.isEmpty) return [];
  return ids.map((id) => _debtTransactionsBox.get(id))
      .whereType<DebtTransaction>()
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
}

List<DebtTransaction> getDebtTransactionsBySale(String saleId) {
  return _debtTransactionsBox.values
      .where((t) => t.saleId == saleId)
      .toList();
}

List<DebtTransaction> getUnsyncedDebtTransactions() {
  return _debtTransactionsBox.values.where((t) => !t.isSynced).toList();
}

Future<void> addDebtTransactionWithId({
  required String id, required String customerId,
  required DebtTransactionType type, required double amount,
  String? saleId, String? note, required String userId,
  bool isSynced = false,
}) async {
  final tx = DebtTransaction(
    id: id, customerId: customerId, type: type, amount: amount,
    saleId: saleId, note: note, userId: userId, isSynced: isSynced,
  );
  await _debtTransactionsBox.put(tx.id, tx);
  _addDebtToIndex(customerId, id);
  _ledgerCache.remove(customerId);
}

Future<void> markDebtTransactionAsSynced(String id) async {
  final tx = _debtTransactionsBox.get(id);
  if (tx != null) {
    tx.isSynced = true;
    await tx.save();
  }
}

Future<void> deleteDebtTransactionLocal(String id) async {
  final tx = _debtTransactionsBox.get(id);
  if (tx != null) {
    _removeDebtFromIndex(tx.customerId, id);
    await _debtTransactionsBox.delete(id);
    _ledgerCache.remove(tx.customerId);
  }
}

Future<void> deleteAllDebtTransactions() async {
  await _debtTransactionsBox.clear();
  _customerDebtIndex.clear();
  _ledgerCache.clear();
}

// ⭐ Index helpers
void _buildCustomerDebtIndex() {
  _customerDebtIndex.clear();
  for (final tx in _debtTransactionsBox.values) {
    _customerDebtIndex.putIfAbsent(tx.customerId, () => []).add(tx.id);
  }
}

void _addDebtToIndex(String customerId, String txId) {
  _customerDebtIndex.putIfAbsent(customerId, () => []).add(txId);
}

void _removeDebtFromIndex(String customerId, String txId) {
  final list = _customerDebtIndex[customerId];
  if (list != null) {
    list.remove(txId);
    if (list.isEmpty) _customerDebtIndex.remove(customerId);
  }
}

// ⭐ Ledger cache
CustomerLedger getCustomerLedger(String customerId) {
  if (_ledgerCache.containsKey(customerId)) {
    return _ledgerCache[customerId]!;
  }
  final rows = getDebtTransactionsByCustomer(customerId);
  final ledger = buildCustomerLedger(rows);
  _ledgerCache[customerId] = ledger;
  return ledger;
}
```

- [ ] **Step 11: Validate**

```bash
flutter analyze lib/services/database_service.dart
```

Expected: **0 new errors**.

---

### Task 4: FirebaseConfig + FirebaseService

**Files:**
- Modify: `lib/config/firebase_config.dart`
- Modify: `lib/services/firebase_service.dart`

**Interfaces:**
- Consumes: `Customer`, `DebtTransaction`, `FirebaseConfig`
- Produces: `addCustomer`, `updateCustomer`, `deleteCustomer`, `addCustomersBatch`, `getCustomers({lastSync})`, `addDebtTransaction`, `addDebtTransactionsBatch`, `getDebtTransactions({lastSync})`

- [ ] **Step 1: Add to `lib/config/firebase_config.dart`**

```dart
static const String customersCollection = 'customers';
static const String debtTransactionsCollection = 'debt_transactions';
```

- [ ] **Step 2: Add customer Firebase methods to `lib/services/firebase_service.dart`**

Insert after the suppliers section (after `:1700`). Follow the exact pattern of `addSupplier`/`updateSupplier`/`deleteSupplier`/`addSuppliersBatch`/`getSuppliers`.

```dart
// ⭐ Customer methods
Future<void> addCustomer({
  required String id, required String name, String? phone,
  String? address, String? notes, required DateTime createdAt,
}) async {
  final uid = currentUser?.uid;
  if (uid == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);
  await _db.collection(FirebaseConfig.customersCollection).doc(id).set({
    'id': id, 'name': name, 'phone': phone, 'address': address, 'notes': notes,
    'user_id': uid,
    'created_at': Timestamp.fromDate(createdAt),
    'updated_at': FieldValue.serverTimestamp(),
  });
}

Future<void> updateCustomer({
  required String id, required String name, String? phone,
  String? address, String? notes,
}) async {
  await _db.collection(FirebaseConfig.customersCollection).doc(id).update({
    'name': name, 'phone': phone, 'address': address, 'notes': notes,
    'updated_at': FieldValue.serverTimestamp(),
  });
}

Future<void> deleteCustomer(String id) async {
  await _db.collection(FirebaseConfig.customersCollection).doc(id).delete();
}

Future<void> addCustomersBatch(List<Map<String, dynamic>> customers) async {
  final uid = currentUser?.uid;
  if (uid == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);
  WriteBatch batch = _db.batch();
  int ops = 0;
  for (final c in customers) {
    final doc = _db.collection(FirebaseConfig.customersCollection).doc(c['id'] as String);
    batch.set(doc, {
      ...c, 'user_id': uid,
      'created_at': Timestamp.fromDate(DateTime.parse(c['created_at'] as String)),
      'updated_at': Timestamp.fromDate(DateTime.parse(c['updated_at'] as String)),
    });
    ops++;
    if (ops % 450 == 0) { await batch.commit(); batch = _db.batch(); }
  }
  if (ops % 450 != 0 || ops == 0) await batch.commit();
}

Future<List<Customer>> getCustomers({DateTime? lastSync}) async {
  final uid = currentUser?.uid;
  if (uid == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);
  final collection = _db.collection(FirebaseConfig.customersCollection)
      .where('user_id', isEqualTo: uid);
  QuerySnapshot<Map<String, dynamic>> snapshot;
  if (lastSync != null) {
    try {
      snapshot = await NetworkService.readWithRetry(() => collection
          .where('updated_at', isGreaterThan: lastSync)
          .limit(500)
          .get());
    } catch (e) {
      snapshot = await NetworkService.readWithRetry(() => collection.limit(500).get());
    }
  } else {
    snapshot = await NetworkService.readWithRetry(() => collection.limit(500).get());
  }
  return snapshot.docs
      .map((doc) => Customer.fromFirestore(doc))
      .toList();
}
```

- [ ] **Step 3: Add debt transaction Firebase methods**

```dart
// ⭐ Debt Transaction methods
Future<void> addDebtTransaction({
  required String id, required String customerId,
  required String type, required double amount,
  String? saleId, String? note, required DateTime createdAt,
}) async {
  final uid = currentUser?.uid;
  if (uid == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);
  await _db.collection(FirebaseConfig.debtTransactionsCollection).doc(id).set({
    'id': id, 'customer_id': customerId, 'type': type, 'amount': amount,
    'sale_id': saleId, 'note': note, 'user_id': uid,
    'created_at': createdAt.toIso8601String(),
    'updated_at': FieldValue.serverTimestamp(),
  });
}

Future<void> deleteDebtTransaction(String id) async {
  await _db.collection(FirebaseConfig.debtTransactionsCollection).doc(id).delete();
}

Future<void> addDebtTransactionsBatch(List<Map<String, dynamic>> txns) async {
  final uid = currentUser?.uid;
  if (uid == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);
  WriteBatch batch = _db.batch();
  int ops = 0;
  for (final t in txns) {
    final doc = _db.collection(FirebaseConfig.debtTransactionsCollection).doc(t['id'] as String);
    batch.set(doc, {...t, 'user_id': uid});
    ops++;
    if (ops % 450 == 0) { await batch.commit(); batch = _db.batch(); }
  }
  if (ops % 450 != 0 || ops == 0) await batch.commit();
}

Future<List<DebtTransaction>> getDebtTransactions({DateTime? lastSync}) async {
  final uid = currentUser?.uid;
  if (uid == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);
  final collection = _db.collection(FirebaseConfig.debtTransactionsCollection)
      .where('user_id', isEqualTo: uid);
  QuerySnapshot<Map<String, dynamic>> snapshot;
  if (lastSync != null) {
    try {
      snapshot = await NetworkService.readWithRetry(() => collection
          .where('updated_at', isGreaterThan: lastSync)
          .limit(500)
          .get());
    } catch (e) {
      snapshot = await NetworkService.readWithRetry(() => collection.limit(500).get());
    }
  } else {
    snapshot = await NetworkService.readWithRetry(() => collection.limit(500).get());
  }
  return snapshot.docs
      .map((doc) => DebtTransaction.fromFirestore(doc))
      .toList();
}
```

- [ ] **Step 4: Validate**

```bash
flutter analyze lib/config/firebase_config.dart lib/services/firebase_service.dart
```

Expected: **0 new errors**.

---

### Task 5: SyncService — push, pull, tombstones, write-through

**Files:**
- Modify: `lib/services/sync_service.dart`

**Interfaces:**
- Consumes: `DatabaseService`, `FirebaseService`
- Produces: `addCustomer`, `updateCustomer`, `deleteCustomer`, `addPayment`, `addManualDebt`, `addDebtAdjustment`, `deleteDebtTransaction`, `addSale` (updated signature)

- [ ] **Step 1: Add `customerId`, `customerName`, `customerPhone`, `paidNow` to `addSale` signature (`:1186`)**

Change to:
```dart
Future<Sale> addSale({
  required List<SaleItem> items, required double subtotal,
  required double discount, required double tax, required double total,
  required String paymentMethod,
  String? customerName, String? customerPhone, String? customerId,
  double paidNow = 0.0,
  String saleType = 'sale', String? originalSaleId,
}) async {
```

After the sale is persisted (`:1229`), before `_notifyDataChanged()` (`:1231`), insert:
```dart
// ⭐ If this is a debt sale, create ledger rows
if (paymentMethod == 'Debt' && customerId != null && total > paidNow) {
  final debtTxId = _uuid.v4();
  await _db.addDebtTransactionWithId(
    id: debtTxId, customerId: customerId,
    type: DebtTransactionType.debt, amount: total,
    saleId: saleId, userId: userId,
  );
  if (paidNow > 0) {
    await _db.addDebtTransactionWithId(
      id: _uuid.v4(), customerId: customerId,
      type: DebtTransactionType.payment, amount: -paidNow,
      saleId: saleId, note: 'دفع عند الشراء',
      userId: userId,
    );
  }
}
```

- [ ] **Step 2: Write write-through customer methods (insert after supplier section, after `:1404`)**

```dart
// ⭐ Customer write-through methods
Future<Customer> addCustomer({
  required String name, String? phone,
  String? address, String? notes,
}) async {
  final userId = _db.getUserId();
  if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);
  final customerId = _uuid.v4();
  await _db.addCustomerWithId(
    id: customerId, name: name, phone: phone,
    address: address, notes: notes, userId: userId, isSynced: false,
  );
  _notifyDataChanged();
  if (_isOnline && _firebase.currentUser != null) {
    try {
      await _firebase.addCustomer(id: customerId, name: name, phone: phone, address: address, notes: notes, createdAt: DateTime.now());
      await _db.markCustomerAsSynced(customerId);
    } catch (e) {
      AppConfig.logError('⚠️ Failed to sync customer to Firebase', e);
    }
  }
  return _db.getCustomerById(customerId)!;
}

Future<void> updateCustomer({
  required String id, required String name,
  String? phone, String? address, String? notes,
}) async {
  await _db.updateCustomer(id: id, name: name, phone: phone, address: address, notes: notes);
  _notifyDataChanged();
  if (_isOnline && _firebase.currentUser != null) {
    try {
      await _firebase.updateCustomer(id: id, name: name, phone: phone, address: address, notes: notes);
      await _db.markCustomerAsSynced(id);
    } catch (e) {
      AppConfig.logError('⚠️ Failed to update customer in Firebase', e);
    }
  }
}

Future<void> deleteCustomer(String id) async {
  await _db.deleteCustomerLocal(id);
  _notifyDataChanged();
  if (_isOnline && _firebase.currentUser != null) {
    try {
      await _firebase.deleteCustomer(id);
    } catch (e) {
      await _db.addPendingDelete('customer', id);
      AppConfig.logError('⚠️ Customer delete queued for sync', e);
    }
  }
}
```

- [ ] **Step 3: Write ledger write-through methods**

```dart
// ⭐ Debt ledger write-through methods
Future<void> addPayment({
  required String customerId, required double amount,
  String? note,
}) async {
  final userId = _db.getUserId();
  if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);
  final txId = _uuid.v4();
  await _db.addDebtTransactionWithId(
    id: txId, customerId: customerId,
    type: DebtTransactionType.payment, amount: -amount,
    note: note, userId: userId, isSynced: false,
  );
  _notifyDataChanged();
  if (_isOnline && _firebase.currentUser != null) {
    try {
      await _firebase.addDebtTransaction(
        id: txId, customerId: customerId, type: 'payment',
        amount: -amount, note: note, createdAt: DateTime.now(),
      );
      await _db.markDebtTransactionAsSynced(txId);
    } catch (e) {
      AppConfig.logError('⚠️ Failed to sync payment to Firebase', e);
    }
  }
}

Future<void> addManualDebt({
  required String customerId, required double amount,
  String? note,
}) async {
  final userId = _db.getUserId();
  if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);
  final txId = _uuid.v4();
  await _db.addDebtTransactionWithId(
    id: txId, customerId: customerId,
    type: DebtTransactionType.debt, amount: amount,
    note: note, userId: userId, isSynced: false,
  );
  _notifyDataChanged();
  if (_isOnline && _firebase.currentUser != null) {
    try {
      await _firebase.addDebtTransaction(
        id: txId, customerId: customerId, type: 'debt',
        amount: amount, note: note, createdAt: DateTime.now(),
      );
      await _db.markDebtTransactionAsSynced(txId);
    } catch (e) {
      AppConfig.logError('⚠️ Failed to sync manual debt to Firebase', e);
    }
  }
}

Future<void> addDebtAdjustment({
  required String customerId, required double amount,
  String? saleId, String? note,
}) async {
  final userId = _db.getUserId();
  if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);
  final txId = _uuid.v4();
  await _db.addDebtTransactionWithId(
    id: txId, customerId: customerId,
    type: DebtTransactionType.adjustment, amount: amount,
    saleId: saleId, note: note, userId: userId, isSynced: false,
  );
  _notifyDataChanged();
  if (_isOnline && _firebase.currentUser != null) {
    try {
      await _firebase.addDebtTransaction(
        id: txId, customerId: customerId, type: 'adjustment',
        amount: amount, saleId: saleId, note: note, createdAt: DateTime.now(),
      );
      await _db.markDebtTransactionAsSynced(txId);
    } catch (e) {
      AppConfig.logError('⚠️ Failed to sync debt adjustment to Firebase', e);
    }
  }
}

Future<void> deleteDebtTransaction(String id) async {
  await _db.deleteDebtTransactionLocal(id);
  _notifyDataChanged();
  if (_isOnline && _firebase.currentUser != null) {
    try {
      await _firebase.deleteDebtTransaction(id);
    } catch (e) {
      await _db.addPendingDelete('debt_transaction', id);
      AppConfig.logError('⚠️ Debt transaction delete queued for sync', e);
    }
  }
}
```

- [ ] **Step 4: Add customer push block to `_syncUnsyncedData` (after `:719`, before the closing `}`)**

Copy the suppliers push block pattern (`:645-688`), replacing with customer unsynced data and `_firebase.addCustomersBatch`.

- [ ] **Step 5: Add debt transaction push block to `_syncUnsyncedData`**

Same pattern — batch with per-item fallback, `_syncErrors.add({'type': 'debt_transaction', ...})`.

- [ ] **Step 6: Add customer tombstone block to `_syncPendingDeletes` (after `:441`)**

```dart
final pendingCustomerDeletes = _db.getPendingDeletes('customer');
for (final id in pendingCustomerDeletes) {
  try {
    await _firebase.deleteCustomer(id);
    await _db.removePendingDelete('customer', id);
  } catch (e) {
    _syncErrors.add({'type': 'customer_delete', 'id': id, ...});
  }
}
```

- [ ] **Step 7: Add debt transaction tombstone block**

Same pattern, type `'debt_transaction'`.

- [ ] **Step 8: Add customer pull block to `_syncFromFirebase` (after `:1019`)**

Following the supplier pull pattern (`:940-960`): fetch, `pendingDeleteIds` skip, null → add, local.isSynced && server.updatedAt.isAfter → update + re-mark synced.

- [ ] **Step 9: Add debt transaction pull block**

Insert-only, like `InventoryMovement` (`:901-924`): if id exists locally, skip.

- [ ] **Step 10: Add both types to `pendingDeleteIds` set at `:735-742`**

```dart
..._db.getPendingDeletes('customer'),
..._db.getPendingDeletes('debt_transaction'),
```

- [ ] **Step 11: Add to `pendingSyncCount` getter (`:126-133`)**

```dart
+ _db.getUnsyncedCustomers().length +
+ _db.getUnsyncedDebtTransactions().length
```

- [ ] **Step 12: Validate**

```bash
flutter analyze lib/services/sync_service.dart
```

Expected: **0 new errors**.

---

### Task 6: Firestore rules and indexes

**Files:**
- Modify: `firestore.rules`
- Modify: `firestore.indexes.json`

- [ ] **Step 1: Add to `firestore.rules` after the purchases block**

```javascript
match /customers/{id} {
  allow create: if canCreate(request.auth.uid);
  allow read: if canAccessOwned();
  allow update: if canUpdateOwned();
  allow delete: if canAccessOwned();
}

match /debt_transactions/{id} {
  allow create: if signedIn()
    && request.resource.data.customer_id is string
    && request.resource.data.amount is number
    && request.resource.data.type in ['debt', 'payment', 'adjustment']
    && request.resource.data.user_id == request.auth.uid;
  allow read: if signedIn()
    && resource.data.user_id == request.auth.uid;
  allow update: if false;
  allow delete: if signedIn()
    && resource.data.user_id == request.auth.uid;
}
```

Note: `debt_transactions` is **update: false** — append-only enforced at the rules level.

- [ ] **Step 2: Add to `firestore.indexes.json`**

```json
{"collectionGroup": "customers", "queryScope": "COLLECTION", "fields": [{"fieldPath": "user_id", "order": "ASCENDING"}, {"fieldPath": "updated_at", "order": "ASCENDING"}]},
{"collectionGroup": "debt_transactions", "queryScope": "COLLECTION", "fields": [{"fieldPath": "user_id", "order": "ASCENDING"}, {"fieldPath": "updated_at", "order": "ASCENDING"}]}
```

- [ ] **Step 3: Validate rules file is valid JSON**

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

⚠️ **Defer this step until the Dart side is proven** — it's the only step touching a live shared system.

---

### Task 7: Translations

**Files:**
- Modify: `assets/translations/ar.json`
- Modify: `assets/translations/en.json`
- Modify: `assets/translations/fr.json`
- Modify: `lib/helpers/localization_helper.dart`

- [ ] **Step 1: Add `customers` section to all three JSON files**

Based on the `suppliers` section structure:

```json
"customers": {
  "title": "العملاء",
  "subtitle": "إدارة العملاء والديون",
  "add": "إضافة عميل",
  "edit": "تعديل عميل",
  "name": "اسم العميل",
  "phone": "رقم الهاتف",
  "address": "العنوان",
  "notes": "ملاحظات",
  "search": "بحث بالاسم أو الهاتف...",
  "empty": "لا يوجد عملاء بعد",
  "emptyHint": "أضف أول عميل لبدء تتبع الديون",
  "deleteTitle": "حذف العميل",
  "deleteMessage": "حذف \"{name}\"؟ سجل الديون سيُحذف أيضاً.",
  "savedLocally": "تم الحفظ محلياً، سيتم المزامنة تلقائياً",
  "nameRequired": "اسم العميل مطلوب",
  "balance": "الرصيد المستحق",
  "totalDebt": "إجمالي الديون",
  "totalPaid": "المدفوع",
  "unpaid": "غير مدفوعة",
  "partiallyPaid": "جزئياً",
  "paid": "مدفوعة",
  "recordPayment": "تسجيل دفعة",
  "addDebt": "إضافة دين",
  "paymentAmount": "المبلغ المدفوع",
  "debtAmount": "مبلغ الدين",
  "debtNote": "ملاحظة (اختياري)",
  "fullAmount": "المبلغ كامل",
  "overpaid": "رصيد لصالح العميل",
  "cannotDeleteWithBalance": "لا يمكن حذف عميل عليه ديون مستحقة",
  "debts": "الديون",
  "history": "الحركات",
  "debt": "دين",
  "payment": "دفعة",
  "adjustment": "تسوية",
  "selectCustomer": "اختر عميلاً",
  "newCustomer": "عميل جديد",
  "walkIn": "عميل عابر",
  "paidNow": "ادفع الآن",
  "credit": "على الدين"
}
```

English and French translations follow the same keys with appropriate values.

- [ ] **Step 2: Add `payment.debt` key**

`ar.json`: `"debt": "الدين"` under the `"payment"` section.
`en.json`: `"debt": "Debt / Credit"`
`fr.json`: `"debt": "Dette / Crédit"`

- [ ] **Step 3: Add getters to `lib/helpers/localization_helper.dart`**

```dart
static String get posDebt => 'pos.debt'.tr();
static String get paymentDebt => 'payment.debt'.tr();
static String get dashboardWalkIn => 'dashboard.walk_in'.tr();
```

- [ ] **Step 4: Add `case 'Debt':` to `paymentMethod()` switch at `:567-576`**

```dart
case 'Debt':
  return paymentDebt;
```

- [ ] **Step 5: Validate JSON files are valid**

```bash
flutter analyze lib/helpers/localization_helper.dart
```

Expected: **0 errors**.

---

### Task 8: CustomersScreen

**Files:**
- Create: `lib/screens/customers_screen.dart`
- Create: `test/widgets/customers_screen_test.dart`
- Modify: `lib/widgets/dashboard_menu.dart`
- Modify: `test/widgets/dashboard_menu_test.dart`

- [ ] **Step 1: Write `lib/screens/customers_screen.dart`**

Copy `suppliers_screen.dart:267-388` as the template. Changes:
- Title: `'customers.title'.tr()`
- FAB `heroTag: 'customers_add_fab'`
- `CircleAvatar` shows customer name initial
- Subtitle shows phone or "—"
- Trailing shows balance in red/green or "مدفوع" (from `_db.getCustomerLedger(customer.id).balance`)
- `EmptyState` icon: `Icons.people_rounded`
- Add `FilterChip` row: الكل / مدينون / مسدّدون (balance > 0, balance <= 0)
- Tap opens `CustomerDetailScreen`, not an options sheet
- Subscribe to `SyncService().dataChangeNotifier` in `initState` to reload when POS creates a sale

- [ ] **Step 2: Write `test/widgets/customers_screen_test.dart`**

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_app/screens/customers_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          useOnlyLangCode: true,
          saveLocale: false,
          child: const MaterialApp(home: CustomersScreen()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('CustomersScreen builds and shows FAB + empty state', (tester) async {
    await pumpScreen(tester);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('No customers yet'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Add drawer row to `lib/widgets/dashboard_menu.dart`**

After the suppliers row (`:77`), insert:
```dart
const SizedBox(height: 8),
_buildNavRow(
  context,
  icon: Icons.people_rounded,
  label: 'customers.title'.tr(),
  onTap: () => _open(context, const CustomersScreen()),
),
```

- [ ] **Step 4: Update `test/widgets/dashboard_menu_test.dart`**

Change `findsNWidgets(5)` to `findsNWidgets(6)` at `:76`. Add `expect(find.byIcon(Icons.people_rounded), findsOneWidget);` after `:66`.

- [ ] **Step 5: Validate**

```bash
flutter test test/widgets/customers_screen_test.dart test/widgets/dashboard_menu_test.dart -v
flutter analyze lib/screens/customers_screen.dart lib/widgets/dashboard_menu.dart
```

---

### Task 9: CustomerDetailScreen + dialogs

**Files:**
- Create: `lib/screens/customer_detail_screen.dart`
- Create: `lib/widgets/customers/customer_picker_sheet.dart`

- [ ] **Step 1: Write `lib/screens/customer_detail_screen.dart`**

StatefulWidget taking `Customer`. Layout:
- Transparent AppBar with customer name, overflow menu (تعديل, حذف)
- Large balance display (green when negative = "رصيد لصالح العميل", red when > 0)
- Summary row: total debt · total paid
- Three state chips: unpaid / partiallyPaid / paid counts
- TabBar: `customers.debts` / `customers.history`
- Debts tab: per-debt cards showing date, amount, progress bar (paid/remaining), state badge
- History tab: chronological list of all transactions with type icon/color, amount, note
- Primary button: "تسجيل دفعة" (hidden when balance <= 0)
- FAB or secondary button: "إضافة دين" (manual debt)

- [ ] **Step 2: Write `lib/widgets/customers/customer_picker_sheet.dart`**

Bottom sheet with:
- Search field filtering by name/phone
- Customer list (tappable, returns `Customer`)
- "عميل جديد" row at top that opens the form and returns the created customer
- Follows the typed-result pattern of `showProductFormDialog` (`product_form_dialog.dart:46-56`)

- [ ] **Step 3: Validate**

```bash
flutter analyze lib/screens/customer_detail_screen.dart
```

---

### Task 10: POS integration — debt payment method

**Files:**
- Modify: `lib/screens/pos_screen.dart`
- Modify: `lib/widgets/pos/checkout_confirmation_sheet.dart`
- Modify: `lib/services/cart_service.dart`

- [ ] **Step 1: Add payment fields to `CartService`**

```dart
String? customerId;
String? customerName;
String? customerPhone;
double paidNow = 0.0;
```

Add setters. Reset in `clearCart()`: `customerId = null; customerName = null; customerPhone = null; paidNow = 0.0;`

- [ ] **Step 2: Add `_buildPaymentOption` for الدين at `pos_screen.dart:644`**

```dart
_buildPaymentOption(
  icon: Icons.account_balance_rounded,
  title: LocalizationHelper.posDebt,
  subtitle: 'customers.credit'.tr(),
  isSelected: cart.paymentMethod == 'Debt',
  isDark: isDark,
  accentColor: accentColor,
  onTap: () async {
    // Show customer picker
    final customer = await showCustomerPickerSheet(context, db: _db);
    if (customer == null) return;
    cart.customerId = customer.id;
    cart.customerName = customer.name;
    cart.customerPhone = customer.phone;
    // Show paidNow dialog
    final paidNow = await showPaidNowDialog(context, total: cart.total);
    cart.paidNow = paidNow ?? 0.0;
    cart.setPaymentMethod('Debt');
    Navigator.pop(ctx);
    showCheckoutConfirmationSheet(context,
      cart: cart, db: _db,
      onError: (msg) => _showSnackBar(msg, AppColors.error),
      onConfirm: () => _confirmSale(cart),
    );
  },
),
```

- [ ] **Step 3: Pass `customerId` and `paidNow` in `_confirmSale` (`:775`)**

```dart
final sale = await _sync.addSale(
  items: saleItems,
  subtotal: subtotalCopy,
  discount: discountCopy,
  tax: taxCopy,
  total: totalCopy,
  paymentMethod: paymentMethodCopy,
  customerName: cart.customerName,
  customerPhone: cart.customerPhone,
  customerId: cart.customerId,
  paidNow: cart.paidNow,
);
```

- [ ] **Step 4: Add customer row to `checkout_confirmation_sheet.dart`**

After the payment method row (`:131`), insert:
```dart
if (cart.customerName != null && cart.customerName!.isNotEmpty) ...[
  const SizedBox(height: 4),
  buildPosReceiptRow(
    'customers.walkIn'.tr(),
    cart.customerName!,
    bodyColor,
  ),
],
```

- [ ] **Step 5: Validate**

```bash
flutter analyze lib/screens/pos_screen.dart lib/widgets/pos/checkout_confirmation_sheet.dart lib/services/cart_service.dart
```

---

### Task 11: Returns adjustment + reports helper

**Files:**
- Modify: `lib/screens/sales_history_screen.dart` (or wherever `_processReturn` lives)
- Modify: `lib/helpers/reports_helper.dart`
- Modify: `lib/screens/reports_screen.dart`

- [ ] **Step 1: Add debt adjustment on return**

In `_processReturn`, after `updateSaleWithReturn` succeeds, add:
```dart
if (sale.paymentMethod == 'Debt' && sale.customerId != null) {
  await _sync.addDebtAdjustment(
    customerId: sale.customerId!,
    amount: -returnAmount,
    saleId: sale.id,
    note: 'مرتجع فاتورة #${sale.id.substring(0, 8)}',
  );
}
```

- [ ] **Step 2: Add `debtTransactions` parameter to `computeReport` (`reports_helper.dart:121`)**

```dart
ReportData computeReport({
  required List<Sale> allSales,
  required List<Purchase> allPurchases,
  required List<Product> allProducts,
  required ReportTimeFilter filter,
  DateTime? now,
  DateTime? customStart,
  DateTime? customEnd,
  List<DebtTransaction> allDebtTransactions = const [],
}) async {
```

Change `:190` from `debtsTotal: 0.0` to:
```dart
debtsTotal: computeTotalDebt(allDebtTransactions),
```

- [ ] **Step 3: Update `reports_screen.dart` to pass debt transactions**

The `_loadReportData` function needs to call `_db.getAllDebtTransactions()` and pass it.

- [ ] **Step 4: Drop "قريباً" subtitle on debts tile**

Change `reports_screen.dart:528` — remove the `subtitle: 'reports.placeholder'.tr()` line.

- [ ] **Step 5: Validate**

```bash
flutter analyze lib/helpers/reports_helper.dart lib/screens/reports_screen.dart
```

---

### Task 12: Full validation

- [ ] **Step 1: Run all tests**

```bash
flutter test -v 2>&1 | tail -20
```

Expected: **112+ tests passing** (baseline 112 + new tests: 2 model, 11 helper, 2 widget = 127+).

- [ ] **Step 2: Run static analysis**

```bash
flutter analyze 2>&1 | tail -15
```

Expected: **0 new errors**, pre-existing 10 infos/warnings unchanged.

- [ ] **Step 3: Confirm no regression**

Any failure is a new failure — the baseline was 112/0. If found, address before proceeding.