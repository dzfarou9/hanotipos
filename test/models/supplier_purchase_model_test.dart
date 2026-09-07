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
            quantity: 5.0,
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
              quantity: 2.0,
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

    test('invoice number and return state roundtrip', () {
      final purchase = Purchase(
        id: 'p2',
        supplierId: 's1',
        supplierName: 'مورد',
        items: [
          PurchaseItem(
              id: 'i3',
              productId: 'pr1',
              productName: 'سكر',
              costPrice: 50,
              quantity: 10.0,
              subtotal: 500),
        ],
        total: 500,
        invoiceNumber: 'INV-2026-001',
        returnedItems: [
          PurchaseItem(
              id: 'i4',
              productId: 'pr1',
              productName: 'سكر',
              costPrice: 50,
              quantity: 3.0,
              subtotal: 150),
        ],
        returnTotal: 150,
        isFullyReturned: false,
        userId: 'u1',
      );
      final restored = Purchase.fromJson(purchase.toJson());
      expect(restored.invoiceNumber, 'INV-2026-001');
      expect(restored.returnedItems!.length, 1);
      expect(restored.returnedItems!.first.quantity, 3.0);
      expect(restored.returnTotal, 150);
      expect(restored.isFullyReturned, isFalse);
      expect(restored.remainingTotal, 350);
    });

    test('availableForReturn subtracts saved and extra returns', () {
      final purchase = Purchase(
        id: 'p3',
        supplierId: 's1',
        supplierName: 'مورد',
        items: [
          PurchaseItem(
              id: 'a',
              productId: 'x',
              productName: 'سكر',
              costPrice: 10,
              quantity: 10.0,
              subtotal: 100),
          PurchaseItem(
              id: 'b',
              productId: 'y',
              productName: 'زيت',
              costPrice: 20,
              quantity: 4.0,
              subtotal: 80),
        ],
        total: 180,
        returnedItems: [
          PurchaseItem(
              id: 'c',
              productId: 'x',
              productName: 'سكر',
              costPrice: 10,
              quantity: 2.0,
              subtotal: 20),
        ],
        userId: 'u1',
      );

      // بدون مرتجعات قديمة: x متاح 8، y متاح 4
      final first = purchase.availableForReturn();
      expect(first.firstWhere((e) => e.productId == 'x').quantity, 8.0);
      expect(first.firstWhere((e) => e.productId == 'y').quantity, 4.0);

      // مع مرتجع قديم مستقل (نظام سابق): x متاح 5
      final second =
          purchase.availableForReturn(extraReturned: {'x': 3.0});
      expect(second.firstWhere((e) => e.productId == 'x').quantity, 5.0);
      // صنف رُجع بالكامل لا يظهر
      final third =
          purchase.availableForReturn(extraReturned: {'x': 8.0});
      expect(third.any((e) => e.productId == 'x'), isFalse);
      expect(third.any((e) => e.productId == 'y'), isTrue);
    });

    test('canBeReturned respects full return only for originals', () {
      final original = Purchase(
          id: 'o',
          supplierId: 's',
          supplierName: 'n',
          items: const [],
          total: 0,
          userId: 'u');
      final legacyReturn = Purchase(
          id: 'r',
          supplierId: 's',
          supplierName: 'n',
          items: const [],
          total: 0,
          purchaseType: 'return',
          userId: 'u');
      final fullyReturned = Purchase(
          id: 'f',
          supplierId: 's',
          supplierName: 'n',
          items: const [],
          total: 0,
          isFullyReturned: true,
          userId: 'u');
      expect(original.canBeReturned, isTrue);
      expect(legacyReturn.canBeReturned, isFalse);
      expect(fullyReturned.canBeReturned, isFalse);
    });
  });
}
