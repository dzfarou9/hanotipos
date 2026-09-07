# Weighted Products (kg / Litre) — Design

Date: 2026-09-07
Status: Approved (in chat, pending spec review)

## Problem

Users sell products that are not sold by piece — sold by kg or litre — and
have no barcode. Today every quantity in the app is an `int`, so fractional
amounts (0.85 kg) are impossible everywhere: cart, stock, sales, purchases,
returns.

## Decisions (confirmed with product owner)

1. **Quantity entry:** manual decimal input at sale time. No scale hardware.
2. **Stock tracking:** weighted products track stock as decimals (12.5 kg),
   same low-stock alerts as piece products.
3. **Purchases:** decimal quantities for weighted products (bought 25.5 kg),
   cost per kg/litre.
4. **Returns:** fractional returns allowed up to the sold quantity
   (return 0.3 of the 0.85 kg sold).

## Approach

**A. Full decimal migration (chosen)** — all quantity fields move from
`int` to `double`; a `unit` field is added to Product. One-time Hive
migration converts legacy data. One-time cost, permanently clean model.

Rejected alternatives:

- **B. Base-unit ints (grams/ml):** no type migration, but unit logic leaks
  into every quantity call site forever; two semantics in one field.
- **C. Partial doubles (only sale/cart items):** fails decimal stock and
  fractional return requirements.

## Design

### 1. Product model

- New field: `@HiveField(13) String unit` — one of `'piece'` (default),
  `'kg'`, `'litre'`.
- `barcode` stays optional; weighted products simply have none. They are
  sold from the product grid, never via the scanner.
- Firestore product docs gain the same `unit` field; quantities are already
  `num` there, so no Firestore migration is needed for quantities.

### 2. Quantity fields int → double

Fields affected: `Product.quantity`, `SaleItem.quantity`,
`PurchaseItem.quantity`, `CartItem.quantity` (~50 usage sites).

- One-time Hive migration at boot: legacy records read through the old
  adapter are rewritten with double quantities.
- Fallback if in-place migration proves unsafe: wipe local Hive boxes and
  re-pull from Firestore (offline-first sync already exists).
- Helper getters such as `canReturn` and `availableForReturn` on `Sale`
  switch from int folds to double sums.

### 3. POS flow

- Tapping a weighted product opens a quantity sheet: decimal keypad,
  price-per-unit display ("800 DZD / kg"), live total, quick chips
  (0.25 / 0.5 / 1), and a stock guard that blocks amounts above stock.
- Piece products behave exactly as today (default qty 1, +/- controls).

### 4. Returns

- Fractional return amounts allowed up to sold quantity.
- Cap comparisons use an epsilon (pattern already exists in
  `debt_ledger_helper.dart`).
- Returned decimal amounts restore decimal stock.

### 5. Purchases

- Decimal quantity input for weighted products; cost entered per kg/litre;
  stock added as decimal. Supplier return caps become decimal-aware.

### 6. Display & formatting

- Quantities stored as full doubles internally; **rounded to 3 decimals**
  at input and when persisted (0.85 kg, not 0.8504 kg).

- Quantities formatted with unit: "0.85 kg" / "12.5 ل" (localized ar/en),
  trailing zeros trimmed.
- Receipts: `0.850 kg × 800 = 680 DZD` line format.
- Inventory shows decimal stock; low-stock alerts work unchanged.

### 7. Reports

- Revenue/profit unaffected (money already double).
- Top-products quantity sums and report quantities become decimal-aware.

### 8. Testing

- Helper tests: weighted cart math, fractional return caps with epsilon,
  Hive migration function, decimal stock deduction.
- Widget test: POS quantity sheet (entry, chips, over-stock block).

## Operational constraint

All devices running the app must update together. An old client writing
`int` quantities after a decimal sale would corrupt stock math.
