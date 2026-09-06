# Customers & Debt Ledger (العملاء ودفتر الديون) — Design Document

**Date:** 2026-09-04
**Status:** Approved by user (design sections 1–6)
**Type:** Architectural
**Toolchain verified:** Flutter 3.44.9 · Dart 3.12.2

> Written in English to match this session and `AGENTS.md`. The two earlier specs in
> this directory are in Arabic; Arabic here is reserved for literal UI strings.

---

## 1. Goal

Add a customers module and a per-customer debt ledger to the hanoti POS app, plus a
new "الدين" (on-credit) payment method in the POS checkout flow. Offline-first: Hive
is the source of truth for reads and writes, Firestore is a replica reached through
the existing sync engine.

The feature answers one question the app cannot answer today: **who owes me what?**

### Verified starting point

Explored before designing; these facts shaped the design:

- **No customer or debt entity exists.** A `lib/models/customer_model.dart` existed
  at some point and was deleted (`report.txt:318` lists it as orphaned with
  "`CustomerAdapter` never registered"); both the model and its `.g.dart` are gone.
  Hive `typeId: 1` is the only gap in an otherwise contiguous range, consistent with
  that deleted model having occupied it.
- **Hooks are pre-wired but unused.** `Sale.customerName` / `Sale.customerPhone`
  (`sale_model.dart:92-96`) are plumbed through Hive, Firestore, printing, receipts,
  and the sales search index with **zero writers** — `pos_screen.dart` never mentions
  `customer`. `sales_history_screen.dart:873` already renders a customer row when
  non-null (currently a dead branch).
- **`reports.debts` renders a hardcoded zero** — `reports_helper.dart:190`
  (`debtsTotal: 0.0, // Placeholder — no debts/receivables model exists`), displayed
  at `reports_screen.dart:523-529` with a "قريباً" subtitle.
- **Payment method is a bare `String`**, not an enum. Only `'Cash'`
  (`pos_screen.dart:611`) and `'Edahabia/CIB'` (`:633`), translated by a `switch`
  at `localization_helper.dart:567-576` that **falls through to raw English** on
  unknown values.
- **Sync is write-through + `isSynced` dirty flag.** No queue box. Deletes are
  tombstones stored as `pending_delete_${type}_$id` keys in the `metadata` box
  (`database_service.dart:144-164`).
- **Tenancy is a flat `user_id` field**, not a subcollection path. There is no store
  or business entity; the tenant is always the user.
- **RTL is deliberately disabled** — `direction_helper.dart` always returns
  `TextDirection.ltr`, so `left`/`right` are safe and `start`/`end` are not needed.
- **All Hive boxes are AES-encrypted** with a key in `flutter_secure_storage`
  (`database_service.dart:94-115`).
- `purchase_model.g.dart` is **current**, not stale — it writes 16 fields (0–15),
  contradicting `report.txt:22-37`. Running `build_runner` is safe.

---

## 2. Design decisions

Six decisions taken during brainstorming, with the rejected alternatives recorded so
future readers know they were considered.

| # | Decision | Rejected alternative |
|---|---|---|
| D1 | **Payments are separate records.** A debt and each payment against it are distinct rows; balance is derived. | A running `paidAmount` field on the debt (loses payment history; clobbered by last-write-wins). |
| D2 | **Optional "paid now" at checkout.** Remainder becomes the debt; paying the full total creates no debt at all. | Full total always becomes debt (forces a second screen for a counter-common case). |
| D3 | **Payments belong to the customer, applied oldest-debt-first (FIFO).** Payment stores only `(customerId, amount, date, note)`. | Cashier picks the target debt (manual arithmetic); hybrid (doubles display + test surface). |
| D4 | **Debts can be created manually**, not only from sales — required for opening balances when onboarding a shop that already has debtors. | Debt-is-a-Sale (simpler, one source of truth per amount, but no opening balances). |
| D5 | **Accrual revenue.** A credit sale counts as revenue at sale time; outstanding debt is shown separately. Existing reporting code is untouched. | Cash-basis (would rewrite `getTodayRevenue`, `getDashboardStats`, `reports_helper`, chart builders, and make past revenue mutate retroactively). |
| D6 | **v1 excludes** due dates, credit limits, and payment reminders. | All three are additive nullable-field changes later; none is needed to answer "who owes me what?". |

### Consequences worth stating plainly

- FIFO means a customer cannot choose to settle a newer debt while an older one is
  open. Total balance is always exact; only **per-debt attribution** is FIFO.
- D4 means an amount lives in two records (the sale and the debt row), so a sale
  return must adjust the debt — handled explicitly in §7.
- D3 is not a one-way door: adding an optional `debtId` to the payment row later is a
  backward-compatible Hive change that would yield D3's rejected alternative.

---

## 3. Architecture: unified append-only ledger

**Chosen over** two separate `Debt`/`DebtPayment` models, and over caching a
`balance` field on `Customer`.

One model, `DebtTransaction`, with a `type` discriminator (`debt` / `payment` /
`adjustment`) and **signed amounts**. Balance is a fold over a customer's rows.

Rationale: adding a synced entity to this codebase costs ~15 touchpoints
(`_allBoxNames`, `clearUserData()`, `closeBoxes()`, `getUnsynced*`, `mark*AsSynced`,
`FirebaseConfig`, four `FirebaseService` methods, three `sync_service` blocks,
`pendingSyncCount`, rules, index, translations ×3). One model instead of two halves
that. And because of D3 a payment is not a child of a debt — there is no containment
relationship to model, only a timeline.

Append-only also makes every row **insert-only**, matching how `InventoryMovement`
already syncs (`sync_service.dart:901-924`) and sidestepping last-write-wins for
money records entirely.

A cached balance field was rejected because it is exactly the field that rots under
sync: two devices each add a payment offline, LWW picks one `Customer` document, and
the balance is silently wrong while the ledger rows remain correct. Under this design
the balance is a pure function of the rows, so it can be memoized (§5) with no
correctness risk and no schema change.

---

## 4. Data models

Hive typeIds in use: 0, 2, 3, 4, 5, 6, 7 (models) and 20, 21 (enums).
**`typeId: 1` is left permanently unused** — stale binary records from the deleted
`Customer` model could collide on existing installs.

### 4.1 `Customer` — typeId 8

`lib/models/customer_model.dart`. Deliberately field-for-field identical in shape to
`Supplier` (typeId 5) so it rides a proven sync template.

| Field | Type | Name | Notes |
|---|---|---|---|
| 0 | `String` final | `id` | uuid v4, Hive box key |
| 1 | `String` | `name` | required |
| 2 | `String?` | `phone` | |
| 3 | `String?` | `address` | |
| 4 | `String?` | `notes` | |
| 5 | `String` final | `userId` | owner scope |
| 6 | `bool` | `isSynced` | `false` on local mutation |
| 7 | `DateTime` final | `createdAt` | |
| 8 | `DateTime` | `updatedAt` | LWW comparison key |

### 4.2 `DebtTransaction` — typeId 9

`lib/models/debt_transaction_model.dart`.

| Field | Type | Name | Notes |
|---|---|---|---|
| 0 | `String` final | `id` | uuid v4 |
| 1 | `String` final | `customerId` | |
| 2 | `DebtTransactionType` final | `type` | `debt` / `payment` / `adjustment` |
| 3 | `double` final | `amount` | **signed**: debt > 0, payment < 0, adjustment either |
| 4 | `String?` final | `saleId` | set for sale-debts and return adjustments; null for manual |
| 5 | `String?` final | `note` | |
| 6 | `String` final | `userId` | |
| 7 | `bool` | `isSynced` | only mutable field |
| 8 | `DateTime` final | `createdAt` | the ledger date; FIFO orders by this |
| 9 | `DateTime` | `updatedAt` | sync watermark only |

All fields except `isSynced` are `final` — these are immutable money records.

### 4.3 `DebtTransactionType` — typeId 22

Hand-written adapter in `lib/models/debt_transaction_enum_adapter.dart`, byte-encoded
`debt`=0, `payment`=1, `adjustment`=2. Hand-written because `hive_generator` 2.0.1
fails on annotated enums — see the explicit warning at
`inventory_movement_model.dart:8-10` and the precedent at
`inventory_movement_enum_adapters.dart` (typeIds 20, 21). Follows the established
"enums live at 20+" convention.

The enum crosses the Firestore wire as its **`name` string**, never its Hive byte, so
reordering cases cannot corrupt remote data.

### 4.4 Change to `Sale`

Add `@HiveField(17) final String? customerId` to `sale_model.dart`, plus
`'customer_id'` in the Firestore map and `fromJson`/`toJson`. The generated adapter
moves from `writeByte(17)` to `writeByte(18)`.

Required because `customerName` is not a stable identifier: two customers named
"محمد" collide, and renaming a customer would orphan the link. Without it the return
adjustment (§7) cannot reliably find the customer, and the sale↔debt link is only
traversable in one direction. Additive and nullable, so existing records read back
fine.

### 4.5 Sign convention

Enforced by the service layer, which is the only writer: `addDebt` and `addPayment`
take **positive** amounts and apply the sign internally; `addAdjustment` takes a
signed delta. Nothing outside `SyncService` constructs a `DebtTransaction`.

---

## 5. Ledger math

A pure function in `lib/helpers/debt_ledger_helper.dart` — no Hive, no Firebase, no
widget imports. Matches the existing pure-helper convention (`reports_helper.dart`,
`sale_search_helper.dart`, `low_stock_helper.dart`) and is therefore fully unit
testable. **This is where the FIFO rule lives, and nowhere else.**

```dart
enum DebtState { unpaid, partiallyPaid, paid }

class DebtEntry {
  final DebtTransaction debt;
  final double paidAmount;
  final double remainingAmount;
  final DebtState state;
}

class CustomerLedger {
  final double totalDebt;      // sum of debt rows
  final double totalPaid;      // credit actually applied to debts
  final double balance;        // > 0 customer owes; < 0 shop owes customer
  final double creditBalance;  // unapplied credit; 0 when balance > 0
  final List<DebtEntry> debts; // newest-first for display
  final int unpaidCount;
  final int partiallyPaidCount;
  final int paidCount;
}

CustomerLedger buildCustomerLedger(List<DebtTransaction> rows);
```

**Algorithm**

1. Partition rows into debts (`type == debt`) and credits (`payment`, `adjustment`).
2. Sort debts ascending by `createdAt`.
3. Pool all credit as a single positive amount (`-sum` of the negative rows).
   The credit pool is order-independent, so a payment dated before any debt still
   applies.
4. Walk debts oldest-first, consuming greedily from the pool: each debt takes
   `min(remaining_debt, remaining_pool)`.
5. Classify: `paidAmount <= epsilon` → `unpaid`; `remainingAmount <= epsilon` →
   `paid`; otherwise `partiallyPaid`.
6. `balance = totalDebt - totalCredit`. If negative, `creditBalance = -balance`.
7. Reverse the debt list for display (newest-first).

**Epsilon = 0.001.** Prices are `double` throughout this codebase, so 4999.9999 must
classify as `paid`. Every comparison in the classifier uses it.

A positive-amount `adjustment` is permitted by the model (increase a debt) but v1's UI
only creates negative ones; the helper handles either sign because it treats
adjustments as signed credit.

---

## 6. Storage layer (Hive)

Two new AES-encrypted boxes: **`customers`** and **`debt_transactions`**.

### 6.1 Lifecycle wiring — `database_service.dart`

| What | Where |
|---|---|
| Two box-name constants | after `:26` |
| Both appended to `_allBoxNames` | `:30-38` |
| Two `late Box<T>` fields | after `:48` |
| `CustomerAdapter`, `DebtTransactionAdapter`, `DebtTransactionTypeAdapter` | after `:88` |
| Two `openBox` calls with the cipher | after `:110` |
| Two `tryStep` lines in `clearUserData()` | alongside `:329-330` |
| Two leftover checks in the verification block | `:339-350` |
| Two entries in `closeBoxes()` | `:1480` |

`_allBoxNames` is not optional: it drives the plaintext→encrypted migration at
`:130-142`, and a box omitted there is invisible to it.

The `clearUserData()` entries are not optional either: omitting them leaks one shop's
debt ledger into the next account on a shared device — the exact bug class the H5 fix
at `:314-322` was written for.

### 6.2 Methods

Naming follows the existing conventions verbatim.

**Customers:** `getCustomerById`, `getAllCustomers`, `getUnsyncedCustomers`,
`customerExists`, `getCustomerCount`, `addCustomerWithId`, `updateCustomer`,
`markCustomerAsSynced`, `deleteCustomerLocal`, `deleteAllCustomers`,
`searchCustomers`.

`getAllCustomers` sorts by **name** ascending — unlike the date-sorted collections,
because this list is browsed alphabetically. `searchCustomers` mirrors
`searchSuppliers` (`:1331`), matching name and phone case-insensitively.

**Debt transactions:** `getDebtTransactionById`, `getAllDebtTransactions`,
`getDebtTransactionsByCustomer`, `getDebtTransactionsBySale`,
`getUnsyncedDebtTransactions`, `addDebtTransactionWithId`,
`markDebtTransactionAsSynced`, `deleteDebtTransactionLocal`,
`deleteAllDebtTransactions`.

### 6.3 Index and cache

`getDebtTransactionsByCustomer` is the hottest read — it runs once per row of the
customers list to show each balance. A full scan per customer is
O(customers × transactions), which degrades visibly at a few thousand rows.

**Index:** in-memory `Map<String, List<String>>` from `customerId` to transaction ids,
built at init and maintained on every write. Same three-helper shape as the existing
`_barcodeIndex` (field `:64`, built `:466`, maintained `:476`/`:483`):
`_buildCustomerDebtIndex`, `_addDebtToIndex`, `_removeDebtFromIndex`.

**Cache:** `Map<String, CustomerLedger>` invalidated on any ledger write, modeled on
`_cachedStats` (`:54-56`) but keyed per customer. Derived, never persisted — cannot
drift from the rows.

No `SalesCache`-style wrapper classes. Those exist to keep a sorted list warm for
pagination; the index plus ledger cache covers the access patterns here.

### 6.4 Deletion rules

- **Ledger rows are deletable** (mistyped payments happen), using the existing
  tombstone infrastructure with types `'customer'` and `'debt_transaction'`. Chosen
  over strict append-only-with-reversing-entries, which is accounting-correct but
  confusing for a shop owner who fat-fingered an amount.
- **A customer can only be deleted when their balance is zero.** Otherwise the app
  explains why, naming the balance, rather than orphaning ledger rows.

---

## 7. Firestore and sync

Two root collections, flat, tenancy by `user_id` field — matching all eight existing
collections. No subcollections.

`firebase_config.dart` gains `customersCollection = 'customers'` and
`debtTransactionsCollection = 'debt_transactions'`.

| Path | Doc ID | Fields |
|---|---|---|
| `customers/{customerId}` | uuid v4 | `id`, `user_id`, `name`, `phone`, `address`, `notes`, `created_at` (ISO string), `updated_at` (`serverTimestamp()`) |
| `debt_transactions/{txId}` | uuid v4 | `id`, `user_id`, `customer_id`, `type` (name string), `amount`, `sale_id`, `note`, `created_at` (ISO string), `updated_at` (`serverTimestamp()`) |

`created_at` as an ISO string with `updated_at` as `serverTimestamp()` is the
products/sales/movements convention (`firebase_service.dart:875`) and the one that
supports incremental pull. `_parseTimestamp` is copied per model accepting
`Timestamp | String | DateTime`, as the other five models do.

### 7.1 `FirebaseService` methods

`addCustomer`, `updateCustomer`, `deleteCustomer`, `addCustomersBatch`,
`getCustomers({lastSync})`, `addDebtTransaction`, `deleteDebtTransaction`,
`addDebtTransactionsBatch`, `getDebtTransactions({lastSync})`.

Every query includes `where('user_id', isEqualTo: uid)` — **non-negotiable**, because
`canAccessOwned()` in the rules rejects the entire query rather than filtering it
(see the "H-5" comments at `firebase_service.dart:764-765` and `:1576-1577`).

**Deliberate deviation from the supplier implementation:** add `.limit(500)`, the
incremental-query `try/catch` fallback that products/sales use
(`firebase_service.dart:625-651`), and `NetworkService.readWithRetry`. `getSuppliers`
(`:1687-1700`) has none of these, which is a known open defect. Without the fallback,
a missing composite index becomes a hard sync failure instead of a full pull.

Reads use `FirebaseAuth`-derived uid inside `FirebaseService`; `SyncService` uses
`_db.getUserId()`. The two are never passed across — the identity guard at
`sync_service.dart:247-261` requires them to agree.

### 7.2 `SyncService` blocks

- **Push** in `_syncUnsyncedData`: sections 6 and 7 after `:719`, batch-with-per-item
  fallback, `_syncErrors.add({'type': 'customer' | 'debt_transaction', ...})`.
- **Tombstones** in `_syncPendingDeletes` after `:442` for both types.
- **Pull** in `_syncFromFirebase`: sections 9 and 10 after `:1019`, each with the
  `pendingDeleteIds` skip and `allPullsSucceeded = false` in its catch. Both types
  added to the `pendingDeleteIds` set at `:735-742`.
- `pendingSyncCount` (`:126-133`) and `getUnsyncedCount` grow by two terms. That
  getter already scans five boxes per UI rebuild and will scan seven — pre-existing
  inefficiency, noted, not fixed here.

### 7.3 Conflict resolution

| Type | Rule |
|---|---|
| `customers` | LWW on `updatedAt`, local-dirty-wins — the supplier rule at `:949-960` verbatim, including re-marking synced after `updateCustomer` flips the flag. |
| `debt_transactions` | **Insert-only**, like `InventoryMovement` (`:901-924`): if the id exists locally, skip. |

Insert-only is the payoff of append-only records: a payment can never be clobbered by
a concurrent edit because nothing ever edits one. Corrections are deletes plus new
rows, which tombstones already handle.

### 7.4 Rules and indexes

Both collections get the standard four-line block (`canCreate` / `canAccessOwned` /
`canUpdateOwned` / `canAccessOwned`) in `firestore.rules`. `debt_transactions`
additionally validates on create — `amount is number`, `customer_id is string`,
`type in ['debt','payment','adjustment']` — following the stricter precedent already
set for `sale_items`.

Two composite indexes in `firestore.indexes.json`, matching what the incremental pull
queries need:

```
{ collectionGroup: "customers",          fields: [user_id ASC, updated_at ASC] }
{ collectionGroup: "debt_transactions",  fields: [user_id ASC, updated_at ASC] }
```

**Deployment is a live shared-system change.**
`firebase deploy --only firestore:rules,firestore:indexes` against project
`hanoti-farou9` (`.firebaserc`); a bad rules file locks out the running app. The diff
is shown and confirmed before running, and the step can be deferred until the Dart
side is proven.

### 7.5 Write-through service API

New `SyncService` methods following the canonical pattern at `:1133-1184` (Hive
first with `isSynced: false`, `_notifyDataChanged()`, then a best-effort immediate
push):

`addCustomer`, `updateCustomer`, `deleteCustomer`, `addPayment`, `addManualDebt`,
`addDebtAdjustment`, `deleteDebtTransaction`.

---

## 8. POS integration

### 8.1 Why the ledger write lives inside `addSale`

`_confirmSale` (`pos_screen.dart:733`) snapshots cart state and calls
`_sync.addSale(...)` (`:775`), which generates the sale id internally at
`sync_service.dart:1201`. To link a debt to its sale, the caller would need that id.
So `SyncService.addSale` gains optional `customerId`, `customerName`, `customerPhone`,
and `paidNow` parameters and creates the ledger rows itself — inside the method that
already owns the id, keeping the debt write adjacent to the sale write. All new
parameters are optional, so no existing caller breaks.

### 8.2 New payment method `'Debt'`

A third bare-string value, set the same way as the other two. Because the translation
`switch` at `localization_helper.dart:567-576` falls through to raw English,
`case 'Debt': return paymentDebt;` must land in the same commit as the button.

**Not** refactoring `paymentMethod` into an enum: a real improvement, but it touches
`CartService`, `HeldOrder`, `Sale`, `firebase_service`, `printing_service`, and their
tests. Separate change.

### 8.3 Flow when الدين is tapped

A new `_buildPaymentOption` block inserted after the Edahabia block ends
(`pos_screen.dart:644`), before the children list closes at `:645`:

1. **Customer picker sheet** — required, cannot be dismissed to proceed. Search over
   saved customers, plus "عميل جديد" which opens the customer form inline and returns
   the created customer. Walk-in is **not** offered here.
2. **Optional "دفع الآن" amount**, default empty (= 0), validated
   `0 <= paidNow <= total`, using the same `RegExp(r'^\d*\.?\d{0,2}$')` formatter as
   `product_form_dialog.dart:240-249`.
3. `showCheckoutConfirmationSheet` as usual, with two extra receipt rows (customer
   name, amount on credit) slotted beside the existing rows at
   `checkout_confirmation_sheet.dart:121-137`.
4. On confirm → `_confirmSale` → `_sync.addSale(..., customerId:, paidNow:)`.

Inside `addSale`, after the sale is persisted and before `_notifyDataChanged()`:

- `paidNow >= total` → **no ledger rows at all**; recorded as a debt-method sale
  settled immediately.
- otherwise → one `debt` row for `total`, plus (if `paidNow > 0`) one `payment` row
  for `paidNow`. Both stamped with the sale's `createdAt` and `saleId`.

### 8.4 Existing payment methods

Customer assignment stays **optional**. The payment sheet gets a compact tappable
customer row showing "زبون عابر" by default.

**Walk-in is the absence of a customer, not a record.** Selecting nothing writes
`customerName: null` and nothing is written to the `customers` box — satisfying the
requirement and guaranteeing no synthetic row can accumulate debt. "زبون عابر" exists
only as a UI label; the `dashboard.walk_in` key already exists in all three JSON
files (`ar.json:115`) with no getter, so it gets wired up.

Cash/card sales **with** a customer attached create **no ledger rows** — they are paid
in full at the counter. Only the name is recorded, finally populating the two `Sale`
fields that have been plumbed-but-unwritten all along, which lights up the existing
receipt row at `sales_history_screen.dart:873`.

### 8.5 Returns

`_processReturn` in `sales_history_screen.dart` calls `updateSaleWithReturn`. Add: if
the sale's `paymentMethod == 'Debt'` and it has a `customerId`, insert an
`adjustment` row for `-returnAmount`, linked by `saleId`, with a note referencing the
return.

Nothing leaves the till, which is correct — the customer never paid. If the
adjustment pushes the balance negative (customer had already overpaid relative to
remaining goods), it surfaces as a **credit balance (رصيد لصالح العميل)** rather than
being clamped to zero and silently absorbing the money.

Because all credit pools under FIFO, a return on a newer sale reduces the oldest open
debt. The total balance is exact; `saleId` on the adjustment keeps it auditable.

---

## 9. UI

Three screens/files plus one drawer row. All strings go into `ar.json` / `en.json` /
`fr.json` under a new `customers` section — no hardcoded Arabic, per convention.
Layout uses `left`/`right` freely since RTL is pinned off.

Reused as-is: `EmptyState`, `StatTile`, `AppSnackBar`, `AppTextStyles`,
`DesignTokens`, and the `context.accent` / `context.titleColor` / `context.bodyColor`
palette extensions.

### 9.1 `CustomersScreen`

`suppliers_screen.dart:267-388` is the template, plus a balance per row.
`StatefulWidget`, `_load()` in `initState`, `setState`, and a `dataChangeNotifier`
subscription so a POS credit sale refreshes the list.

```
AppBar  العملاء                    [transparent, back arrow in accent]
┌─────────────────────────────────────────┐
│ إجمالي الديون   45,300 DZD   [StatTile] │
│ عملاء مدينون    12                      │
├─────────────────────────────────────────┤
│ 🔍 بحث بالاسم أو الهاتف                 │
│ [ الكل ][ مدينون ][ مسدّدون ]           │  ← FilterChip, as POS categories
├─────────────────────────────────────────┤
│ (م)  محمد بن علي                        │
│      0555xxxxxx          3,500 DZD  ›   │  ← red when owing
│ (ف)  فاطمة                              │
│      —                   مسدّد       ›   │  ← green when clear
└─────────────────────────────────────────┘
                                    [ + ]    heroTag: 'customers_add_fab'
```

Tapping a row opens the detail screen **directly**, not an options sheet — the ledger
is the point of the screen. Edit and delete live in the detail screen's overflow menu.

The FAB needs its own `heroTag` or it collides with the suppliers FAB.

### 9.2 `CustomerDetailScreen`

```
AppBar  محمد بن علي                        [⋮ تعديل / حذف]
┌─────────────────────────────────────────┐
│         الرصيد المستحق                  │
│          3,500 DZD                      │  ← green + "رصيد لصالح العميل" if < 0
│   إجمالي الديون 12,000 · المدفوع 8,500  │
├─────────────────────────────────────────┤
│  غير مدفوعة 2  ·  جزئياً 1  ·  مدفوعة 5 │
├─────────────────────────────────────────┤
│ [ الديون ]  [ الحركات ]                 │  ← TabBar
├─────────────────────────────────────────┤
│ debts tab — per-debt cards:              │
│   3 سبتمبر · فاتورة #a1b2   5,000       │
│   ▓▓▓▓▓░░░░░  دفع 2,000 · باقي 3,000    │
│   [جزئياً]                               │
│                                         │
│ history tab — chronological rows:        │
│   ▲ دين      +5,000   3 سبتمبر          │
│   ▼ دفعة     -2,000   5 سبتمبر          │
│   ◆ تسوية    -500     مرتجع  6 سبتمبر   │
└─────────────────────────────────────────┘
        [ تسجيل دفعة ]  ← primary; hidden when balance <= 0
```

The debts tab answers "which debts are outstanding"; the history tab answers "what
happened when". Both render from a single `buildCustomerLedger` call. Tapping a debt
row that has a `saleId` navigates to that sale.

### 9.3 Dialogs

All bottom sheets, cloned from `_SupplierFormSheet` (`suppliers_screen.dart:391-618`):
`GlobalKey<FormState>`, one controller per field created in `initState` and disposed,
`_saving` guard, keyboard-aware padding, icon-chip header with close-X, full-width
submit with the spinner swapped into the icon slot.

| Sheet | Contents |
|---|---|
| `_CustomerFormSheet` | name (required), phone, address, notes |
| `showPaymentSheet` | amount (required, `> 0`), optional note, "المبلغ كامل" quick-fill |
| `showCustomerPickerSheet` | search + list + "عميل جديد"; returns `Customer?` |
| `showManualDebtSheet` | amount, note — the opening-balance path (D4) |

`showCustomerPickerSheet` follows the typed-result pattern of
`showProductFormDialog` (`product_form_dialog.dart:46-56`) so the caller owns what
happens next.

### 9.4 Wiring

- One import plus one `_buildNavRow` in `dashboard_menu.dart`'s "Manage" section after
  the suppliers row (`:72-77`), `Icons.people_rounded`. Not a bottom-nav tab — the
  bottom bar is three fixed tabs and this is a management screen like suppliers and
  inventory.
- `dashboard_menu_test.dart:58-77` asserts exactly 5 destinations and
  `findsNWidgets(5)` chevrons. Both assertions become 6 in the same commit.
- `reports_helper.dart:190` `debtsTotal` becomes the real outstanding total, so
  `computeReport` (`reports_helper.dart:121`) grows one parameter for debt
  transactions, and `reports_screen.dart:528` drops the `'reports.placeholder'`
  subtitle.

---

## 10. Testing

Verification gate: `flutter analyze` clean and `flutter test` green before any
completion claim. The pre-existing baseline is confirmed **first**, so pre-existing
failures are distinguishable from new ones.

### 10.1 `test/helpers/debt_ledger_helper_test.dart` — the bulk

Pure, no Hive, following `reports_helper_test.dart`'s style of constructing models
inline. The FIFO classifier is the part most likely to be subtly wrong.

- empty ledger → zero balance, no debts
- single unpaid debt → `unpaid`, `remaining == amount`
- partial payment → `partiallyPaid`, correct split
- exact payment → `paid`
- floating-point-adjacent (4999.9999 vs 5000) → `paid` via epsilon
- one payment spanning two debts → first `paid`, second `partiallyPaid`
- payment exceeding all debts → `creditBalance > 0`, `balance < 0`
- adjustment reducing a debt → state recomputes
- adjustment pushing balance negative → credit balance, not clamped
- FIFO ordering verified by inserting rows with out-of-order `createdAt`
- payment dated before any debt → still applied

### 10.2 Other tests

- `test/models/customer_debt_model_test.dart` — Hive round-trip and
  `toJson`/`fromJson`/`fromFirestore` symmetry, mirroring
  `supplier_purchase_model_test.dart`.
- `test/widgets/customers_screen_test.dart` — empty state, list renders balances,
  search filters; following `suppliers_screen_test.dart`.
- `dashboard_menu_test.dart` — two updated assertions.

---

## 11. Error handling

Convention: `AppConfig.logError` for diagnostics, `AppSnackBar.error` for the user,
never a raw exception string in the UI.

| Case | Behavior |
|---|---|
| No customer on a debt sale | Confirm stays disabled; no path exists to a debt sale without a customer. |
| `paidNow > total` | Blocked by the validator before submit. |
| Payment exceeding balance | **Allowed**, becomes a credit balance — refusing it would make legitimate overpayment impossible. The sheet states this, so it is not silent. |
| Deleting a customer with non-zero balance | Blocked, with an explanation naming the balance. |
| Offline | Everything works; rows sit at `isSynced: false` and upload on the next `syncNow()`. No special-casing — this is the architecture's purpose. |
| Ledger write fails after the sale is saved | The sale stands; the error is logged and surfaced. |

**Accepted asymmetry:** Hive has no cross-box transaction, so sale + ledger row is not
atomic. A sale with a missing debt row is visible and fixable by hand; a lost sale is
neither. The failure mode is chosen deliberately.

---

## 12. Build order

Nine steps, each independently verifiable. Steps 1–5 are pure Dart with no UI.

1. Models + enum adapter + `build_runner`, with model tests
2. `debt_ledger_helper.dart` + full test suite — riskiest logic, proven before
   anything depends on it
3. `DatabaseService`: boxes, lifecycle, CRUD, index, ledger cache
4. `FirebaseConfig` + `FirebaseService` methods
5. `SyncService`: push, pull, tombstones, write-through methods
6. `firestore.rules` + indexes — **diff shown and confirmed before deploying**
7. `CustomersScreen`, `CustomerDetailScreen`, dialogs, translations, drawer row
8. POS: `'Debt'` method, customer picker, `paidNow`, `Sale.customerId`, receipt rows
9. Returns adjustment + `reports_helper` real `debtsTotal`

---

## 13. Out of scope for v1

Due dates (تاريخ الاستحقاق) and an overdue state · credit limits (حد الدين) · payment
reminders and notifications · debt receipt printing · per-customer statement export ·
walk-in customers as stored records · cash-basis revenue and a "collected today"
figure · refactoring `paymentMethod` from `String` into an enum.

Due dates and credit limits are each a nullable Hive field away and can be added
without migration pain.

---

## 14. Known landmines

Carried forward from exploration; each is a checklist item, not a design decision.

1. **`_allBoxNames` omission** breaks the encryption migration silently.
2. **`clearUserData()` omission** leaks a shop's ledger into the next account on a
   shared device.
3. **Translation `switch` fall-through** renders `'Debt'` as raw English if the `case`
   is forgotten.
4. **FAB `heroTag`** collision crashes if omitted.
5. **`dashboard_menu_test.dart`** hard-codes 5 destinations — will fail until updated.
6. **Every Firestore query needs `user_id`** or the rules reject the whole query.
7. **`typeId: 1`** must stay unused.
8. **Rules deploy** is the only step touching a live shared system.

---

## 15. Note on version control

This project is not yet a git repository (`AGENTS.md`). Per the user's instruction,
git init and the first push to `dzfarou9/hanotiapp` are deferred until they ask, so
this document is **not** committed at authoring time — a deviation from the
brainstorming skill's default, made on explicit user instruction.
