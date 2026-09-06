import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/helpers/reports_helper.dart';
import 'package:pos_app/models/product_model.dart';
import 'package:pos_app/models/purchase_model.dart';
import 'package:pos_app/models/sale_model.dart';

// A fixed "now" keeps the week/month/year windows deterministic.
// 2025-06-18 is a Wednesday, so the current week starts Monday 2025-06-16.
final _now = DateTime(2025, 6, 18, 12);

Product _product(String id, {double? costPrice}) => Product(
      id: id,
      name: 'Product $id',
      category: 'General',
      price: 100,
      quantity: 5,
      userId: 'user1',
      costPrice: costPrice,
    );

SaleItem _saleItem(double price, int qty, {String productId = 'p1'}) => SaleItem(
      id: 'si-$productId-$price-$qty',
      productId: productId,
      productName: 'Product $productId',
      price: price,
      quantity: qty,
      subtotal: price * qty,
    );

Sale _sale(
  String id,
  double total, {
  required DateTime createdAt,
  bool isReturn = false,
  double? returnTotal,
  bool isFullyReturned = false,
  List<SaleItem>? items,
  List<SaleItem>? returnedItems,
}) =>
    Sale(
      id: id,
      items: items ?? [_saleItem(total, 1)],
      subtotal: total,
      discount: 0,
      tax: 0,
      total: total,
      paymentMethod: 'Cash',
      createdAt: createdAt,
      userId: 'user1',
      saleType: isReturn ? 'return' : 'sale',
      returnTotal: returnTotal,
      returnedItems: returnedItems,
      isFullyReturned: isFullyReturned,
    );

PurchaseItem _purchaseItem(double cost, int qty) => PurchaseItem(
      id: 'pi-$cost-$qty',
      productId: 'p1',
      productName: 'Product p1',
      costPrice: cost,
      quantity: qty,
      subtotal: cost * qty,
    );

Purchase _purchase(
  String id,
  double total, {
  required DateTime createdAt,
  bool isReturn = false,
  double? returnTotal,
}) =>
    Purchase(
      id: id,
      items: [_purchaseItem(total, 1)],
      supplierId: 'sup1',
      supplierName: 'Supplier 1',
      total: total,
      purchaseType: isReturn ? 'return' : 'purchase',
      userId: 'user1',
      createdAt: createdAt,
      returnTotal: returnTotal,
    );

ReportData _compute(
  ReportTimeFilter filter, {
  List<Sale> sales = const [],
  List<Purchase> purchases = const [],
  List<Product> products = const [],
  DateTime? customStart,
  DateTime? customEnd,
}) =>
    computeReport(
      allSales: sales,
      allPurchases: purchases,
      allProducts: products,
      filter: filter,
      now: _now,
      customStart: customStart,
      customEnd: customEnd,
    );

void main() {
  group('filterStartDate', () {
    test('week starts on Monday of the current week', () {
      expect(
        filterStartDate(ReportTimeFilter.week, _now),
        DateTime(2025, 6, 16),
      );
    });

    test('month starts on the first of the month', () {
      expect(
        filterStartDate(ReportTimeFilter.month, _now),
        DateTime(2025, 6, 1),
      );
    });

    test('year starts on January 1st', () {
      expect(
        filterStartDate(ReportTimeFilter.year, _now),
        DateTime(2025, 1, 1),
      );
    });

    test('custom uses the supplied start, falling back to now', () {
      final start = DateTime(2025, 3, 4);
      expect(
        filterStartDate(ReportTimeFilter.custom, _now, customStart: start),
        start,
      );
      expect(filterStartDate(ReportTimeFilter.custom, _now), _now);
    });
  });

  group('filterEndDate', () {
    test('non-custom filters end at now', () {
      for (final filter in [
        ReportTimeFilter.week,
        ReportTimeFilter.month,
        ReportTimeFilter.year,
      ]) {
        expect(filterEndDate(filter, _now), _now);
      }
    });

    test('custom uses the supplied end, falling back to now', () {
      final end = DateTime(2025, 5, 9);
      expect(
        filterEndDate(ReportTimeFilter.custom, _now, customEnd: end),
        end,
      );
      expect(filterEndDate(ReportTimeFilter.custom, _now), _now);
    });
  });

  group('computeReport — sales metrics', () {
    test('sums revenue and counts transactions inside the window', () {
      final data = _compute(
        ReportTimeFilter.week,
        sales: [
          _sale('s1', 100, createdAt: DateTime(2025, 6, 16, 9)),
          _sale('s2', 300, createdAt: DateTime(2025, 6, 17, 9)),
        ],
      );

      expect(data.exportsTotal, 400);
      expect(data.salesCount, 2);
      expect(data.averageSaleValue, 200);
    });

    test('excludes sales outside the window', () {
      final data = _compute(
        ReportTimeFilter.week,
        sales: [
          // Sunday before the current week started.
          _sale('old', 500, createdAt: DateTime(2025, 6, 15, 9)),
          _sale('s1', 100, createdAt: DateTime(2025, 6, 17, 9)),
        ],
      );

      expect(data.exportsTotal, 100);
      expect(data.salesCount, 1);
    });

    test('standalone return records subtract their total and are not counted',
        () {
      final data = _compute(
        ReportTimeFilter.week,
        sales: [
          _sale('s1', 500, createdAt: DateTime(2025, 6, 17, 9)),
          _sale('r1', 200, createdAt: DateTime(2025, 6, 17, 10), isReturn: true),
        ],
      );

      expect(data.exportsTotal, 300);
      // The return itself is not a transaction.
      expect(data.salesCount, 1);
      expect(data.averageSaleValue, 300);
    });

    test('partial returns reduce revenue via remainingTotal', () {
      final data = _compute(
        ReportTimeFilter.week,
        sales: [
          _sale('s1', 500,
              createdAt: DateTime(2025, 6, 17, 9), returnTotal: 150),
        ],
      );

      expect(data.exportsTotal, 350);
      expect(data.salesCount, 1);
    });

    test('fully-returned invoices are excluded from the transaction count', () {
      final data = _compute(
        ReportTimeFilter.week,
        sales: [
          _sale('s1', 200, createdAt: DateTime(2025, 6, 17, 9)),
          _sale(
            's2',
            400,
            createdAt: DateTime(2025, 6, 17, 10),
            returnTotal: 400,
            isFullyReturned: true,
          ),
        ],
      );

      // s2 contributes 0 revenue (remainingTotal) and 0 to the count.
      expect(data.exportsTotal, 200);
      expect(data.salesCount, 1);
    });

    test('average sale value is 0 when there are no transactions', () {
      final data = _compute(ReportTimeFilter.week);
      expect(data.salesCount, 0);
      expect(data.averageSaleValue, 0);
    });
  });

  group('computeReport — purchases, products, placeholders', () {
    test('sums purchases net of returns inside the window', () {
      final data = _compute(
        ReportTimeFilter.month,
        purchases: [
          _purchase('p1', 1000, createdAt: DateTime(2025, 6, 2)),
          _purchase('p2', 400, createdAt: DateTime(2025, 6, 10),
              returnTotal: 100),
          _purchase('pr1', 250,
              createdAt: DateTime(2025, 6, 12), isReturn: true),
          // Outside the month.
          _purchase('old', 9999, createdAt: DateTime(2025, 5, 30)),
        ],
      );

      // 1000 + (400 - 100) - 250
      expect(data.importsTotal, 1050);
    });

    test('products count is the full inventory, not window-filtered', () {
      final data = _compute(
        ReportTimeFilter.week,
        products: [_product('a'), _product('b'), _product('c')],
      );

      expect(data.productsCount, 3);
    });

    test('debts stay at 0 without debt transactions', () {
      final data = _compute(
        ReportTimeFilter.year,
        sales: [_sale('s1', 900, createdAt: DateTime(2025, 4, 1))],
        purchases: [_purchase('p1', 300, createdAt: DateTime(2025, 4, 1))],
      );

      expect(data.debtsTotal, 0);
    });

    test('net profit is revenue when no product has a recorded cost', () {
      final data = _compute(
        ReportTimeFilter.year,
        sales: [_sale('s1', 900, createdAt: DateTime(2025, 4, 1))],
        products: [_product('p1')],
      );

      expect(data.costOfGoodsSold, 0);
      expect(data.netProfit, 900);
    });

    test('net profit subtracts the cost of every unit sold', () {
      final data = _compute(
        ReportTimeFilter.year,
        sales: [
          _sale('s1', 300,
              createdAt: DateTime(2025, 4, 1),
              items: [_saleItem(100, 3)]),
        ],
        products: [_product('p1', costPrice: 60)],
      );

      // 3 units × 60 cost = 180 COGS against 300 revenue.
      expect(data.costOfGoodsSold, 180);
      expect(data.netProfit, 120);
    });

    test('products without a cost contribute no COGS', () {
      final data = _compute(
        ReportTimeFilter.year,
        sales: [
          _sale('s1', 300, createdAt: DateTime(2025, 4, 1), items: [
            _saleItem(100, 2, productId: 'priced'),
            _saleItem(100, 1, productId: 'unpriced'),
          ]),
        ],
        products: [
          _product('priced', costPrice: 40),
          _product('unpriced'),
        ],
      );

      expect(data.costOfGoodsSold, 80);
      expect(data.netProfit, 220);
    });

    test('a standalone return record reverses its cost', () {
      final data = _compute(
        ReportTimeFilter.year,
        sales: [
          _sale('s1', 200,
              createdAt: DateTime(2025, 4, 1), items: [_saleItem(100, 2)]),
          _sale('r1', 100,
              createdAt: DateTime(2025, 4, 2),
              isReturn: true,
              items: [_saleItem(100, 1)]),
        ],
        products: [_product('p1', costPrice: 60)],
      );

      // Sold 2 (120 cost), returned 1 (-60 cost) => 60 COGS.
      // Revenue: 200 - 100 = 100. Profit: 100 - 60 = 40.
      expect(data.costOfGoodsSold, 60);
      expect(data.netProfit, 40);
    });

    test('units returned against a sale drop out of COGS', () {
      final data = _compute(
        ReportTimeFilter.year,
        sales: [
          _sale('s1', 300,
              createdAt: DateTime(2025, 4, 1),
              items: [_saleItem(100, 3)],
              returnedItems: [_saleItem(100, 1)],
              returnTotal: 100),
        ],
        products: [_product('p1', costPrice: 60)],
      );

      // 3 sold − 1 returned = 2 units × 60 = 120 COGS.
      // Revenue uses remainingTotal: 300 - 100 = 200. Profit: 80.
      expect(data.costOfGoodsSold, 120);
      expect(data.netProfit, 80);
    });

    test('net profit is negative when cost exceeds revenue', () {
      final data = _compute(
        ReportTimeFilter.year,
        sales: [
          _sale('s1', 100,
              createdAt: DateTime(2025, 4, 1), items: [_saleItem(50, 2)]),
        ],
        products: [_product('p1', costPrice: 80)],
      );

      expect(data.costOfGoodsSold, 160);
      expect(data.netProfit, -60);
    });

    test('an empty dataset yields an all-zero report', () {
      final data = _compute(ReportTimeFilter.week);

      expect(data.exportsTotal, 0);
      expect(data.importsTotal, 0);
      expect(data.salesCount, 0);
      expect(data.productsCount, 0);
    });
  });

  group('computeReport — chart data', () {
    test('week is bucketed per day and zero-filled from Monday to now', () {
      final data = _compute(
        ReportTimeFilter.week,
        sales: [
          _sale('s1', 100, createdAt: DateTime(2025, 6, 16, 9)),
          _sale('s2', 50, createdAt: DateTime(2025, 6, 16, 18)),
          _sale('s3', 70, createdAt: DateTime(2025, 6, 18, 8)),
        ],
      );

      // Monday 16th → Wednesday 18th inclusive.
      expect(data.chartData.keys, ['16/6', '17/6', '18/6']);
      expect(data.chartData['16/6'], 150);
      expect(data.chartData['17/6'], 0);
      expect(data.chartData['18/6'], 70);
    });

    test('year is bucketed into all twelve months, zero-filled', () {
      final data = _compute(
        ReportTimeFilter.year,
        sales: [
          _sale('s1', 200, createdAt: DateTime(2025, 1, 15)),
          _sale('s2', 300, createdAt: DateTime(2025, 6, 2)),
        ],
      );

      expect(data.chartData.length, 12);
      expect(data.chartData['Jan'], 200);
      expect(data.chartData['Jun'], 300);
      expect(data.chartData['Feb'], 0);
      expect(data.chartData['Dec'], 0);
    });

    test('month is bucketed per week of the month', () {
      final data = _compute(
        ReportTimeFilter.month,
        sales: [
          _sale('s1', 100, createdAt: DateTime(2025, 6, 3)),
          _sale('s2', 250, createdAt: DateTime(2025, 6, 9)),
          _sale('s3', 60, createdAt: DateTime(2025, 6, 17)),
        ],
      );

      // Days 1-7 → W1, 8-14 → W2, 15-21 → W3.
      expect(data.chartData['W1'], 100);
      expect(data.chartData['W2'], 250);
      expect(data.chartData['W3'], 60);
    });

    test('returns push a bucket negative rather than being dropped', () {
      final data = _compute(
        ReportTimeFilter.week,
        sales: [
          _sale('s1', 100, createdAt: DateTime(2025, 6, 17, 9)),
          _sale('r1', 300,
              createdAt: DateTime(2025, 6, 17, 11), isReturn: true),
        ],
      );

      expect(data.chartData['17/6'], -200);
    });

    test('custom range buckets per day across the supplied window', () {
      final data = _compute(
        ReportTimeFilter.custom,
        customStart: DateTime(2025, 6, 10),
        customEnd: DateTime(2025, 6, 12, 23, 59, 59),
        sales: [
          _sale('s1', 80, createdAt: DateTime(2025, 6, 10, 9)),
          _sale('s2', 40, createdAt: DateTime(2025, 6, 12, 20)),
          // Outside the custom window.
          _sale('s3', 500, createdAt: DateTime(2025, 6, 14, 9)),
        ],
      );

      expect(data.chartData.keys, ['10/6', '11/6', '12/6']);
      expect(data.chartData['10/6'], 80);
      expect(data.chartData['11/6'], 0);
      expect(data.chartData['12/6'], 40);
      expect(data.exportsTotal, 120);
    });
  });
}
