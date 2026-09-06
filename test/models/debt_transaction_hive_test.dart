// اختبار انحدار: خرائط بايتات DebtTransactionType مثبّتة ولا يجوز تغييرها
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pos_app/models/debt_transaction_enum_adapter.dart';
import 'package:pos_app/models/debt_transaction_model.dart';

void main() {
  late Directory tempDir;
  late Box<DebtTransaction> box;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_debt_test');
    Hive.init(tempDir.path);
    // ⭐ سجل الadapters عالمي في Hive ولا يُصفَّر بين الاختبارات،
    // لذا نتحقق قبل التسجيل وإلا يفشل الاختبار الثاني بـ
    // "There is already a TypeAdapter for typeId 22".
    if (!Hive.isAdapterRegistered(22)) {
      Hive.registerAdapter(DebtTransactionTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(DebtTransactionAdapter());
    }
    box = await Hive.openBox<DebtTransaction>('debt_regression');
  });

  tearDown(() async {
    if (box.isOpen) await box.close();
    await Hive.deleteBoxFromDisk('debt_regression');
    await tempDir.delete(recursive: true);
  });

  // ⭐ صندوق Hive المفتوح يخزّن القيم في الذاكرة، فـ box.get بعد box.put
  // يعيد نفس الكائن دون استدعاء read() من المحوّل. نغلق الصندوق ونفتحه
  // ليُقرأ من القرص فعلاً — وإلا لا يختبر شيئاً من خريطة البايتات.
  Future<void> reopenBox() async {
    await box.close();
    box = await Hive.openBox<DebtTransaction>('debt_regression');
  }

  test('all three enum values survive a Hive roundtrip', () async {
    final rows = {
      'debt': DebtTransactionType.debt,
      'payment': DebtTransactionType.payment,
      'adjustment': DebtTransactionType.adjustment,
    };

    for (final entry in rows.entries) {
      await box.put(
        entry.key,
        DebtTransaction(
          id: entry.key,
          customerId: 'c1',
          type: entry.value,
          amount: 100,
          userId: 'u1',
        ),
      );
    }

    await reopenBox();

    for (final entry in rows.entries) {
      expect(box.get(entry.key)!.type, entry.value,
          reason: 'byte mapping for ${entry.key} changed');
    }
  });

  test('signed amounts and nullable fields survive a Hive roundtrip', () async {
    final createdAt = DateTime(2026, 9, 4, 12, 30);
    await box.put(
      'p1',
      DebtTransaction(
        id: 'p1',
        customerId: 'c1',
        type: DebtTransactionType.payment,
        amount: -2500.75,
        saleId: 's1',
        note: 'دفعة جزئية',
        userId: 'u1',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );

    await reopenBox();

    final read = box.get('p1')!;
    expect(read.type, DebtTransactionType.payment);
    expect(read.amount, -2500.75);
    expect(read.saleId, 's1');
    expect(read.note, 'دفعة جزئية');
    expect(read.createdAt, createdAt);
    expect(read.updatedAt, createdAt);
    expect(read.isSynced, isFalse);
  });

  test('Customer-less optional fields default to null', () async {
    await box.put(
      'd1',
      DebtTransaction(
        id: 'd1',
        customerId: 'c1',
        type: DebtTransactionType.debt,
        amount: 5000,
        userId: 'u1',
      ),
    );

    await reopenBox();

    final read = box.get('d1')!;
    expect(read.type, DebtTransactionType.debt);
    expect(read.saleId, isNull);
    expect(read.note, isNull);
  });
}
