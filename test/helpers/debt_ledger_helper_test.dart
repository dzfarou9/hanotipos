// test/helpers/debt_ledger_helper_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/helpers/debt_ledger_helper.dart';
import 'package:pos_app/models/debt_transaction_model.dart';

// تواريخ ثابتة: ترتيب FIFO يعتمد على createdAt، فلا نترك أي صف على
// DateTime.now() في اختبار متعدد الصفوف وإلا صار الترتيب غير حتمي.
final _day1 = DateTime(2026, 9, 1, 9);
final _day2 = DateTime(2026, 9, 2, 9);
final _day3 = DateTime(2026, 9, 3, 9);

DebtTransaction _debt({
  required String id,
  required double amount,
  DateTime? createdAt,
  String customerId = 'c1',
}) =>
    DebtTransaction(
      id: id,
      customerId: customerId,
      type: DebtTransactionType.debt,
      amount: amount,
      userId: 'u1',
      createdAt: createdAt,
    );

DebtTransaction _payment({
  required String id,
  required double amount,
  DateTime? createdAt,
  String customerId = 'c1',
}) =>
    DebtTransaction(
      id: id,
      customerId: customerId,
      type: DebtTransactionType.payment,
      amount: -amount,
      userId: 'u1',
      createdAt: createdAt,
    );

DebtTransaction _adjustment({
  required String id,
  required double amount,
  DateTime? createdAt,
  String customerId = 'c1',
}) =>
    DebtTransaction(
      id: id,
      customerId: customerId,
      type: DebtTransactionType.adjustment,
      amount: amount,
      userId: 'u1',
      createdAt: createdAt,
    );

// البحث بالمعرّف لا بالموضع: ترتيب العرض عكس ترتيب التوزيع، والاختبار
// لا يجوز أن يعتمد عليه صامتاً.
DebtEntry _entryById(CustomerLedger ledger, String id) =>
    ledger.debts.firstWhere((e) => e.debt.id == id);

void main() {
  group('buildCustomerLedger — basics', () {
    test('an empty ledger is all zeros and does not throw', () {
      final ledger = buildCustomerLedger([]);

      expect(ledger.totalDebt, 0);
      expect(ledger.totalPaid, 0);
      expect(ledger.balance, 0);
      expect(ledger.creditBalance, 0);
      expect(ledger.debts, isEmpty);
      expect(ledger.unpaidCount, 0);
      expect(ledger.partiallyPaidCount, 0);
      expect(ledger.paidCount, 0);
    });

    test('a single debt with no payment is fully unpaid', () {
      final ledger = buildCustomerLedger([
        _debt(id: 'd1', amount: 5000, createdAt: _day1),
      ]);

      expect(ledger.totalDebt, 5000);
      expect(ledger.balance, 5000);
      expect(ledger.unpaidCount, 1);
      expect(ledger.debts.first.state, DebtState.unpaid);
      expect(ledger.debts.first.remainingAmount, 5000);
      expect(ledger.debts.first.paidAmount, 0);
    });

    test('a payment smaller than the debt leaves it partially paid', () {
      final ledger = buildCustomerLedger([
        _debt(id: 'd1', amount: 5000, createdAt: _day1),
        _payment(id: 'p1', amount: 2000, createdAt: _day2),
      ]);

      expect(ledger.totalPaid, 2000);
      expect(ledger.balance, 3000);
      expect(ledger.partiallyPaidCount, 1);
      expect(ledger.debts.first.paidAmount, 2000);
      expect(ledger.debts.first.remainingAmount, 3000);
      expect(ledger.debts.first.state, DebtState.partiallyPaid);
    });

    test('a payment equal to the debt settles it with no credit left', () {
      final ledger = buildCustomerLedger([
        _debt(id: 'd1', amount: 5000, createdAt: _day1),
        _payment(id: 'p1', amount: 5000, createdAt: _day2),
      ]);

      expect(ledger.balance, 0);
      expect(ledger.paidCount, 1);
      expect(ledger.creditBalance, 0);
      expect(ledger.debts.first.state, DebtState.paid);
    });
  });

  group('buildCustomerLedger — epsilon', () {
    test('a remainder under epsilon counts as fully paid', () {
      final ledger = buildCustomerLedger([
        _debt(id: 'd1', amount: 5000, createdAt: _day1),
        _payment(id: 'p1', amount: 4999.9999, createdAt: _day2),
      ]);

      expect(ledger.debts.first.state, DebtState.paid);
      expect(ledger.paidCount, 1);
      // الباقي 0.0001 داخل الهامش، فلا يظهر لا كباقٍ ولا كرصيد مستحق.
      expect(ledger.debts.first.remainingAmount, 0);
      expect(ledger.balance, 0);
    });

    test('a payment under epsilon does not make a debt partially paid', () {
      final ledger = buildCustomerLedger([
        _debt(id: 'd1', amount: 5000, createdAt: _day1),
        _payment(id: 'p1', amount: 0.0005, createdAt: _day2),
      ]);

      expect(ledger.debts.first.state, DebtState.unpaid);
      expect(ledger.unpaidCount, 1);
      expect(ledger.totalPaid, 0);
      expect(ledger.balance, 5000);
    });

    test('a zero-amount row is ignored entirely', () {
      final ledger = buildCustomerLedger([
        _debt(id: 'z1', amount: 0.0, createdAt: _day1),
        _debt(id: 'd1', amount: 5000, createdAt: _day2),
      ]);

      expect(ledger.debts.length, 1);
      expect(ledger.debts.first.debt.id, 'd1');
      expect(ledger.totalDebt, 5000);
      expect(ledger.balance, 5000);
    });

    // الحالتان التاليتان تحرسان الهامش عند بقايا التوزيع نفسها، لا عند
    // تصنيف الصفوف: بركة تتجاوز الهامش وتترك فُتاتاً أصغر منه.
    test('a sub-epsilon leftover is not reported as credit', () {
      final ledger = buildCustomerLedger([
        _debt(id: 'd1', amount: 3000, createdAt: _day1),
        _payment(id: 'p1', amount: 3000.0005, createdAt: _day2),
      ]);

      expect(ledger.creditBalance, 0);
      expect(ledger.balance, 0);
      expect(ledger.debts.first.state, DebtState.paid);
    });

    test('a sub-epsilon allocation leaves the next debt unpaid', () {
      final ledger = buildCustomerLedger([
        _debt(id: 'old', amount: 3000, createdAt: _day1),
        _debt(id: 'new', amount: 5000, createdAt: _day2),
        _payment(id: 'p1', amount: 3000.0005, createdAt: _day3),
      ]);

      expect(_entryById(ledger, 'old').state, DebtState.paid);
      expect(_entryById(ledger, 'new').state, DebtState.unpaid);
      expect(ledger.unpaidCount, 1);
      expect(ledger.partiallyPaidCount, 0);
    });

    test('a remainder above epsilon is still owed, not rounded away', () {
      final ledger = buildCustomerLedger([
        _debt(id: 'd1', amount: 5000, createdAt: _day1),
        _payment(id: 'p1', amount: 4999.5, createdAt: _day2),
      ]);

      expect(ledger.balance, 0.5);
      expect(ledger.debts.first.remainingAmount, 0.5);
      expect(ledger.debts.first.state, DebtState.partiallyPaid);
    });
  });

  group('buildCustomerLedger — FIFO', () {
    test('credit settles the oldest debt first', () {
      final ledger = buildCustomerLedger([
        _debt(id: 'old', amount: 3000, createdAt: _day1),
        _debt(id: 'new', amount: 4000, createdAt: _day2),
        _payment(id: 'p1', amount: 5000, createdAt: _day3),
      ]);

      expect(_entryById(ledger, 'old').state, DebtState.paid);
      expect(_entryById(ledger, 'old').paidAmount, 3000);
      expect(_entryById(ledger, 'new').state, DebtState.partiallyPaid);
      expect(_entryById(ledger, 'new').paidAmount, 2000);
      expect(_entryById(ledger, 'new').remainingAmount, 2000);
      expect(ledger.balance, 2000);
      expect(ledger.totalPaid, 5000);
    });

    test('scrambled input order gives the identical allocation', () {
      final ordered = buildCustomerLedger([
        _debt(id: 'old', amount: 3000, createdAt: _day1),
        _debt(id: 'new', amount: 4000, createdAt: _day2),
        _payment(id: 'p1', amount: 5000, createdAt: _day3),
      ]);
      final scrambled = buildCustomerLedger([
        _payment(id: 'p1', amount: 5000, createdAt: _day3),
        _debt(id: 'new', amount: 4000, createdAt: _day2),
        _debt(id: 'old', amount: 3000, createdAt: _day1),
      ]);

      expect(_entryById(scrambled, 'old').state, DebtState.paid);
      expect(_entryById(scrambled, 'new').state, DebtState.partiallyPaid);
      expect(_entryById(scrambled, 'new').remainingAmount, 2000);
      expect(scrambled.balance, ordered.balance);
      expect(scrambled.totalPaid, ordered.totalPaid);
      expect(
        scrambled.debts.map((e) => e.debt.id),
        ordered.debts.map((e) => e.debt.id),
      );
    });

    test('a payment dated before every debt still applies', () {
      final ledger = buildCustomerLedger([
        _payment(id: 'p1', amount: 5000, createdAt: _day1),
        _debt(id: 'd1', amount: 5000, createdAt: _day2),
      ]);

      expect(_entryById(ledger, 'd1').state, DebtState.paid);
      expect(ledger.balance, 0);
      expect(ledger.creditBalance, 0);
    });

    test('the returned debts list is newest-first', () {
      final ledger = buildCustomerLedger([
        _debt(id: 'oldest', amount: 1000, createdAt: _day1),
        _debt(id: 'middle', amount: 1000, createdAt: _day2),
        _debt(id: 'newest', amount: 1000, createdAt: _day3),
      ]);

      expect(ledger.debts.map((e) => e.debt.id).toList(),
          ['newest', 'middle', 'oldest']);
    });
  });

  group('buildCustomerLedger — credit balance', () {
    test('overpayment leaves credit and a negative net balance', () {
      final ledger = buildCustomerLedger([
        _debt(id: 'd1', amount: 3000, createdAt: _day1),
        _payment(id: 'p1', amount: 5000, createdAt: _day2),
      ]);

      expect(ledger.totalDebt, 3000);
      expect(ledger.totalPaid, 3000);
      expect(ledger.creditBalance, 2000);
      expect(ledger.balance, -2000);
      expect(ledger.debts.first.state, DebtState.paid);
    });

    test('payments with no debts are pure credit', () {
      final ledger = buildCustomerLedger([
        _payment(id: 'p1', amount: 1000, createdAt: _day1),
        _payment(id: 'p2', amount: 500, createdAt: _day2),
      ]);

      expect(ledger.totalDebt, 0);
      expect(ledger.totalPaid, 0);
      expect(ledger.creditBalance, 1500);
      expect(ledger.balance, -1500);
      expect(ledger.debts, isEmpty);
    });

    test('balance and creditBalance are never both positive', () {
      final ledger = buildCustomerLedger([
        _debt(id: 'd1', amount: 3000, createdAt: _day1),
        _payment(id: 'p1', amount: 5000, createdAt: _day2),
      ]);

      expect(ledger.creditBalance > 0, isTrue);
      expect(ledger.balance <= 0, isTrue);
    });
  });

  group('buildCustomerLedger — adjustments', () {
    test('a negative adjustment reduces a debt like a payment', () {
      final ledger = buildCustomerLedger([
        _debt(id: 'd1', amount: 5000, createdAt: _day1),
        _adjustment(id: 'a1', amount: -2000, createdAt: _day2),
      ]);

      expect(ledger.balance, 3000);
      expect(ledger.totalPaid, 2000);
      expect(ledger.debts.first.state, DebtState.partiallyPaid);
    });

    test('a negative adjustment can push the balance negative', () {
      final ledger = buildCustomerLedger([
        _debt(id: 'd1', amount: 3000, createdAt: _day1),
        _adjustment(id: 'a1', amount: -5000, createdAt: _day2),
      ]);

      expect(ledger.balance, -2000);
      expect(ledger.creditBalance, 2000);
    });

    test('a positive adjustment acts as an additional debt', () {
      final ledger = buildCustomerLedger([
        _debt(id: 'd1', amount: 3000, createdAt: _day1),
        _adjustment(id: 'a1', amount: 1000, createdAt: _day2),
      ]);

      expect(ledger.totalDebt, 4000);
      expect(ledger.debts.length, 2);
      expect(ledger.balance, 4000);
      expect(ledger.unpaidCount, 2);
    });

    test('a debt-typed row with a negative amount is treated as credit', () {
      final ledger = buildCustomerLedger([
        _debt(id: 'd1', amount: 5000, createdAt: _day1),
        _debt(id: 'x', amount: -2000, createdAt: _day2),
      ]);

      expect(ledger.balance, 3000);
      expect(ledger.totalDebt, 5000);
      expect(ledger.totalPaid, 2000);
      expect(ledger.debts.length, 1);
      expect(_entryById(ledger, 'd1').state, DebtState.partiallyPaid);
    });
  });

  group('buildCustomerLedger — purity', () {
    test('the input list is never reordered', () {
      final input = [
        _debt(id: 'new', amount: 4000, createdAt: _day3),
        _payment(id: 'p1', amount: 1000, createdAt: _day2),
        _debt(id: 'old', amount: 3000, createdAt: _day1),
      ];
      final before = List.of(input);

      buildCustomerLedger(input);

      expect(input.map((r) => r.id).toList(), before.map((r) => r.id).toList());
      expect(input.length, 3);
    });
  });

  group('computeTotalDebt', () {
    test('sums the net debt of every customer', () {
      final total = computeTotalDebt([
        // c1: 5000 مدين − 2000 مدفوع = 3000
        _debt(id: 'd1', amount: 5000, createdAt: _day1, customerId: 'c1'),
        _payment(id: 'p1', amount: 2000, createdAt: _day2, customerId: 'c1'),
        // c2: 8000 كاملاً
        _debt(id: 'd2', amount: 8000, createdAt: _day1, customerId: 'c2'),
        // c3: مسوّى تماماً
        _debt(id: 'd3', amount: 3000, createdAt: _day1, customerId: 'c3'),
        _payment(id: 'p3', amount: 3000, createdAt: _day2, customerId: 'c3'),
      ]);

      expect(total, 11000);
    });

    test('a customer in credit does not offset another customer debt', () {
      final total = computeTotalDebt([
        _debt(id: 'd1', amount: 5000, createdAt: _day1, customerId: 'c1'),
        _payment(id: 'p2', amount: 2000, createdAt: _day1, customerId: 'c2'),
      ]);

      expect(total, 5000);
    });

    test('an empty list has no receivables', () {
      expect(computeTotalDebt([]), 0.0);
    });
  });
}
