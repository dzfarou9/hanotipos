// lib/helpers/debt_ledger_helper.dart
//
// حسابات دفتر ديون الزبون — دالة نقية بالكامل.
//
// لا Hive ولا Firestore ولا Flutter هنا: المدخل قائمة صفوف والمخرج أرقام
// وحالات، تماماً كباقي مساعدي `lib/helpers/` (انظر reports_helper.dart).
//
// المبادئ الثابتة
// ---------------
//   - التصنيف بإشارة `amount` لا بـ `type`: `DebtTransaction.parseType` تُرجع
//     `debt` لأي نص مجهول، فقد يصل صف دفعة تالف بـ type=debt و amount سالب.
//     الاعتماد على `type` مع `amount.abs()` يعطي رصيداً خاطئاً في تلك الحالة.
//   - المال `double`، فكل مقارنة تمرّ بهامش [_epsilon]: لا `==` ولا `<=`
//     مباشرة على باقٍ محسوب (دفعة 4999.9999 على دين 5000 = مسدّد).
//   - FIFO: الرصيد الدائن يستهلك الديون من الأقدم إلى الأحدث حسب `createdAt`.
//   - لا تُعدَّل القائمة الواردة أبداً — المتصل يمرّر قيم صندوق Hive مباشرة.

import '../models/debt_transaction_model.dart';

/// هامش المقارنة النقدية: أي فرق أصغر منه يُعدّ صفراً.
const double _epsilon = 0.001;

// ═══════════════════════════════════════════════════════════════════════════════
// Data model for a customer ledger
// ═══════════════════════════════════════════════════════════════════════════════

/// حالة سداد دين واحد.
enum DebtState {
  /// لم يُسدَّد منه شيء.
  unpaid,

  /// سُدِّد جزء منه وبقي باقٍ.
  partiallyPaid,

  /// سُدِّد كاملاً (الباقي داخل الهامش).
  paid,
}

/// دين واحد مع نصيبه من المدفوعات بعد توزيع FIFO.
class DebtEntry {
  /// الصف الأصلي كما هو في الدفتر.
  final DebtTransaction debt;

  /// ما طُبِّق فعلاً على هذا الدين من الرصيد الدائن.
  final double paidAmount;

  /// الباقي على هذا الدين (صفر عند السداد الكامل).
  final double remainingAmount;

  /// حالة السداد المشتقة من [paidAmount] و [remainingAmount].
  final DebtState state;

  const DebtEntry({
    required this.debt,
    required this.paidAmount,
    required this.remainingAmount,
    required this.state,
  });
}

/// صورة كاملة لدفتر زبون واحد: مجاميع + تفاصيل كل دين + عدّادات الحالات.
class CustomerLedger {
  /// مجموع كل الديون (الصفوف ذات المبلغ الموجب).
  final double totalDebt;

  /// ما طُبِّق فعلاً من الرصيد الدائن على الديون — لا حجم الرصيد الدائن.
  final double totalPaid;

  /// الوضع الصافي الموقّع: موجب = الزبون مدين للمحل، سالب = المحل مدين له.
  final double balance;

  /// فائض الدفعات بعد سداد كل الديون. لا يكون سالباً أبداً.
  final double creditBalance;

  /// الديون مرتّبة من الأحدث إلى الأقدم (ترتيب العرض).
  final List<DebtEntry> debts;

  /// عدد الديون التي لم يُسدَّد منها شيء.
  final int unpaidCount;

  /// عدد الديون المسدَّدة جزئياً.
  final int partiallyPaidCount;

  /// عدد الديون المسدَّدة كاملاً.
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

// ═══════════════════════════════════════════════════════════════════════════════
// FIFO allocation
// ═══════════════════════════════════════════════════════════════════════════════

/// يبني دفتر زبون من صفوفه الخام: يقسمها بالإشارة، يجمع الدائن في بركة
/// واحدة، ثم يوزّعها على الديون من الأقدم إلى الأحدث (FIFO).
///
/// قائمة فارغة تعيد دفتراً أصفاراً ولا ترمي استثناءً.
CustomerLedger buildCustomerLedger(List<DebtTransaction> rows) {
  // ── تقسيم بالإشارة: صف داخل الهامش لا يؤثر على أي رصيد فيُهمل ────────────
  final debtRows = <DebtTransaction>[];
  double pool = 0.0;
  for (final row in rows) {
    if (row.amount > _epsilon) {
      debtRows.add(row);
    } else if (row.amount < -_epsilon) {
      // البركة غير مرتّبة بقصد: دفعة سابقة لكل الديون تُطبَّق أيضاً.
      pool += -row.amount;
    }
  }

  // ── توزيع البركة على الديون من الأقدم إلى الأحدث ─────────────────────────
  // الترتيب على [debtRows] وهي نسخة داخلية بُنيت في الحلقة أعلاه، فالقائمة
  // الواردة (قيم صندوق Hive) لا تُلمس أبداً.
  debtRows.sort((a, b) => a.createdAt.compareTo(b.createdAt));

  double totalDebt = 0.0;
  double totalPaid = 0.0;
  double remainingPool = pool;
  int unpaidCount = 0;
  int partiallyPaidCount = 0;
  int paidCount = 0;
  final entries = <DebtEntry>[];

  for (final debt in debtRows) {
    totalDebt += debt.amount;

    final applied = remainingPool < debt.amount ? remainingPool : debt.amount;
    remainingPool -= applied;
    totalPaid += applied;

    final rawRemaining = debt.amount - applied;
    final DebtState state;
    if (rawRemaining <= _epsilon) {
      state = DebtState.paid;
      paidCount++;
    } else if (applied > _epsilon) {
      state = DebtState.partiallyPaid;
      partiallyPaidCount++;
    } else {
      state = DebtState.unpaid;
      unpaidCount++;
    }

    entries.add(DebtEntry(
      debt: debt,
      paidAmount: applied,
      remainingAmount: state == DebtState.paid ? 0.0 : rawRemaining,
      state: state,
    ));
  }

  final creditBalance = remainingPool > _epsilon ? remainingPool : 0.0;
  final rawBalance = totalDebt - totalPaid - creditBalance;

  return CustomerLedger(
    totalDebt: totalDebt,
    totalPaid: totalPaid,
    balance: rawBalance.abs() <= _epsilon ? 0.0 : rawBalance,
    creditBalance: creditBalance,
    // التوزيع تصاعدي (FIFO) والعرض تنازلي — ترتيبان مختلفان لا يُخلطان.
    debts: entries.reversed.toList(),
    unpaidCount: unpaidCount,
    partiallyPaidCount: partiallyPaidCount,
    paidCount: paidCount,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Shop-wide receivables
// ═══════════════════════════════════════════════════════════════════════════════

/// إجمالي ما للمحل على الزبائن: يجمّع الصفوف حسب `customerId`، يبني دفتر كل
/// زبون، ثم يجمع الأرصدة الموجبة فقط.
///
/// الأرصدة السالبة تُستبعد بقصد: زبون له رصيد دائن لا يخفّض دين زبون آخر.
double computeTotalDebt(List<DebtTransaction> allRows) {
  final byCustomer = <String, List<DebtTransaction>>{};
  for (final row in allRows) {
    byCustomer.putIfAbsent(row.customerId, () => <DebtTransaction>[]).add(row);
  }

  double total = 0.0;
  for (final rows in byCustomer.values) {
    final balance = buildCustomerLedger(rows).balance;
    if (balance > _epsilon) total += balance;
  }
  return total;
}
