// test/models/customer_debt_model_test.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/customer_model.dart';
import 'package:pos_app/models/debt_transaction_enum_adapter.dart';
import 'package:pos_app/models/debt_transaction_model.dart';

void main() {
  group('Customer JSON roundtrip', () {
    test('toJson then fromJson preserves fields', () {
      final now = DateTime(2026, 9, 4, 10);
      final customer = Customer(
        id: 'c1',
        name: 'محمد بن علي',
        phone: '0555000111',
        address: 'الجزائر',
        notes: 'زبون دائم',
        userId: 'u1',
        isSynced: false,
        createdAt: now,
        updatedAt: now,
      );
      final restored = Customer.fromJson(customer.toJson());
      expect(restored.id, 'c1');
      expect(restored.name, 'محمد بن علي');
      expect(restored.phone, '0555000111');
      expect(restored.address, 'الجزائر');
      expect(restored.notes, 'زبون دائم');
      expect(restored.userId, 'u1');
      expect(restored.createdAt, now);
    });

    test('fromJson tolerates null optionals', () {
      final map = {
        'id': 'c2',
        'name': 'x',
        'user_id': 'u1',
        'created_at': '2026-01-01T00:00:00.000',
        'updated_at': '2026-01-01T00:00:00.000',
      };
      final c = Customer.fromJson(map);
      expect(c.phone, isNull);
      expect(c.address, isNull);
      expect(c.notes, isNull);
    });

    test('fromJson marks records as synced', () {
      final c = Customer.fromJson({
        'id': 'c3',
        'name': 'y',
        'user_id': 'u1',
        'created_at': '2026-01-01T00:00:00.000',
        'updated_at': '2026-01-01T00:00:00.000',
      });
      expect(c.isSynced, isTrue);
    });

    test('parses Firestore Timestamp values', () {
      final when = DateTime(2026, 9, 4, 8, 15);
      final c = Customer.fromJson({
        'id': 'c4',
        'name': 'z',
        'user_id': 'u1',
        'created_at': Timestamp.fromDate(when),
        'updated_at': Timestamp.fromDate(when),
      });
      expect(c.createdAt, when);
      expect(c.updatedAt, when);
    });
  });

  group('DebtTransaction JSON roundtrip', () {
    test('debt row roundtrips with positive amount', () {
      final now = DateTime(2026, 9, 4, 10);
      final tx = DebtTransaction(
        id: 't1',
        customerId: 'c1',
        type: DebtTransactionType.debt,
        amount: 5000,
        saleId: 's1',
        userId: 'u1',
        createdAt: now,
        updatedAt: now,
      );
      final restored = DebtTransaction.fromJson(tx.toJson());
      expect(restored.id, 't1');
      expect(restored.customerId, 'c1');
      expect(restored.type, DebtTransactionType.debt);
      expect(restored.amount, 5000);
      expect(restored.saleId, 's1');
      expect(restored.createdAt, now);
    });

    test('payment row roundtrips with negative amount', () {
      final tx = DebtTransaction(
        id: 't2',
        customerId: 'c1',
        type: DebtTransactionType.payment,
        amount: -2000,
        note: 'دفعة نقدية',
        userId: 'u1',
      );
      final restored = DebtTransaction.fromJson(tx.toJson());
      expect(restored.type, DebtTransactionType.payment);
      expect(restored.amount, -2000);
      expect(restored.note, 'دفعة نقدية');
      expect(restored.saleId, isNull);
    });

    test('adjustment row roundtrips', () {
      final tx = DebtTransaction(
        id: 't3',
        customerId: 'c1',
        type: DebtTransactionType.adjustment,
        amount: -500,
        saleId: 's1',
        note: 'مرتجع',
        userId: 'u1',
      );
      final restored = DebtTransaction.fromJson(tx.toJson());
      expect(restored.type, DebtTransactionType.adjustment);
      expect(restored.amount, -500);
    });

    test('type crosses the wire as a name string', () {
      final tx = DebtTransaction(
        id: 't4',
        customerId: 'c1',
        type: DebtTransactionType.payment,
        amount: -100,
        userId: 'u1',
      );
      expect(tx.toJson()['type'], 'payment');
    });

    test('unknown type string falls back to debt', () {
      final tx = DebtTransaction.fromJson({
        'id': 't5',
        'customer_id': 'c1',
        'type': 'nonsense',
        'amount': 10,
        'user_id': 'u1',
        'created_at': '2026-01-01T00:00:00.000',
        'updated_at': '2026-01-01T00:00:00.000',
      });
      expect(tx.type, DebtTransactionType.debt);
    });

    test('fromJson tolerates missing amount and defaults to zero', () {
      final tx = DebtTransaction.fromJson({
        'id': 't6',
        'customer_id': 'c1',
        'type': 'debt',
        'user_id': 'u1',
        'created_at': '2026-01-01T00:00:00.000',
        'updated_at': '2026-01-01T00:00:00.000',
      });
      expect(tx.amount, 0.0);
    });

    test('parses Firestore Timestamp values', () {
      final when = DateTime(2026, 9, 4, 8, 15);
      final tx = DebtTransaction.fromJson({
        'id': 't7',
        'customer_id': 'c1',
        'type': 'debt',
        'amount': 10,
        'user_id': 'u1',
        'created_at': Timestamp.fromDate(when),
        'updated_at': Timestamp.fromDate(when),
      });
      expect(tx.createdAt, when);
      expect(tx.updatedAt, when);
    });
  });

  group('DebtTransaction Hive adapter', () {
    test('adapter has the reserved typeId 22', () {
      expect(DebtTransactionTypeAdapter().typeId, 22);
    });
  });
}
