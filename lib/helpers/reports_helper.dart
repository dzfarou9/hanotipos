// lib/helpers/reports_helper.dart
//
// Pure aggregation helpers for the ReportsScreen.
//
// Each function is a pure transformation of its inputs — no services, no state,
// no side effects. This makes them testable (see test/helpers/ pattern in
// top_products_helper_test.dart) and keeps chart/aggregation logic out of the
// screen widget.
//
// Return-aware accounting
// -----------------------
// Matches the dashboard convention (dashboard_screen.dart:298-357):
//   - Normal sales contribute `remainingTotal` to revenue.
//   - Standalone return records (sale.isReturn) subtract their `total`.
//   - Fully-returned invoices are excluded from the transaction count.
//   - Purchases follow the same pattern: `remainingTotal` for normal purchases,
//     standalone returns subtract their `total`.
//   - Cost of goods sold mirrors the same signs, priced from each product's
//     current `costPrice` (products without a cost contribute nothing).

import '../models/product_model.dart';
import '../models/purchase_model.dart';
import '../models/sale_model.dart';
import '../models/debt_transaction_model.dart';
import 'debt_ledger_helper.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Time filter
// ═══════════════════════════════════════════════════════════════════════════════

/// Time period filter for the reports screen.
enum ReportTimeFilter {
  week,
  month,
  year,
  custom,
}

/// Returns the start datetime for the given filter relative to [now].
DateTime filterStartDate(ReportTimeFilter filter, DateTime now,
    {DateTime? customStart}) {
  switch (filter) {
    case ReportTimeFilter.week:
      // Start of the current week (Monday).
      final weekDay = now.weekday;
      return DateTime(now.year, now.month, now.day - (weekDay - 1));
    case ReportTimeFilter.month:
      return DateTime(now.year, now.month, 1);
    case ReportTimeFilter.year:
      return DateTime(now.year, 1, 1);
    case ReportTimeFilter.custom:
      return customStart ?? now;
  }
}

/// Returns the end datetime for the given filter relative to [now].
DateTime filterEndDate(ReportTimeFilter filter, DateTime now,
    {DateTime? customEnd}) {
  switch (filter) {
    case ReportTimeFilter.custom:
      return customEnd ?? now;
    default:
      return now;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Data model for the reports screen
// ═══════════════════════════════════════════════════════════════════════════════

/// Aggregated report data for a single time period.
///
/// All monetary values are in the app's currency (DZD).
class ReportData {
  /// Net profit: sales revenue minus the cost of goods sold.
  ///
  /// COGS uses each sold product's current [Product.costPrice]. Items whose
  /// product no longer exists, or has no cost recorded, contribute zero cost —
  /// so profit degrades to revenue rather than becoming wrong.
  final double netProfit;

  /// Cost of goods sold over the period (net of returns).
  final double costOfGoodsSold;

  /// Number of sales transactions (excluding fully-returned invoices).
  final int salesCount;

  /// Average sale value per transaction.
  final double averageSaleValue;

  /// Total sum of purchases (net of returns).
  final double importsTotal;

  /// Total sum of sales revenue (net of returns).
  final double exportsTotal;

  /// Placeholder for future debts data.
  final double debtsTotal;

  /// Total count of products in inventory.
  final int productsCount;

  /// Chart data points: label → value for the Sales Overview line chart.
  /// Labels are locale-aware short day/month names.
  final Map<String, double> chartData;

  const ReportData({
    this.netProfit = 0.0,
    this.costOfGoodsSold = 0.0,
    this.salesCount = 0,
    this.averageSaleValue = 0.0,
    this.importsTotal = 0.0,
    this.exportsTotal = 0.0,
    this.debtsTotal = 0.0,
    this.productsCount = 0,
    this.chartData = const {},
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// Aggregation
// ═══════════════════════════════════════════════════════════════════════════════

/// Computes a full [ReportData] snapshot for the given time filter.
///
/// Parameters:
///   - [allSales]: all sales in the system (filtered by date internally).
///   - [allPurchases]: all purchases in the system (filtered by date internally).
///   - [allProducts]: all products (used for the total count).
///   - [filter]: the time period to aggregate over.
///   - [now]: reference "now" time (injected for testability).
///   - [customStart] / [customEnd]: for [ReportTimeFilter.custom].
ReportData computeReport({
  required List<Sale> allSales,
  required List<Purchase> allPurchases,
  required List<Product> allProducts,
  required ReportTimeFilter filter,
  List<DebtTransaction> allDebtTransactions = const [],
  DateTime? now,
  DateTime? customStart,
  DateTime? customEnd,
}) {
  final referenceNow = now ?? DateTime.now();
  final start = filterStartDate(filter, referenceNow, customStart: customStart);
  final end = filterEndDate(filter, referenceNow, customEnd: customEnd);

  // ── Filter sales by date range ──────────────────────────────────────────
  final periodSales = allSales.where((s) {
    return !s.createdAt.isBefore(start) && !s.createdAt.isAfter(end);
  }).toList();

  // ── Filter purchases by date range ──────────────────────────────────────
  final periodPurchases = allPurchases.where((p) {
    return !p.createdAt.isBefore(start) && !p.createdAt.isAfter(end);
  }).toList();

  // ── Sales metrics (return-aware) ────────────────────────────────────────
  double revenue = 0.0;
  int transactionCount = 0;

  for (final sale in periodSales) {
    if (sale.isReturn) {
      revenue -= sale.total;
    } else {
      revenue += sale.remainingTotal;
      if (!sale.isFullyReturned) {
        transactionCount++;
      }
    }
  }

  final salesCount = transactionCount;
  final averageSaleValue = salesCount > 0 ? revenue / salesCount : 0.0;

  // ── Purchase metrics (return-aware) ─────────────────────────────────────
  double purchasesTotal = 0.0;
  for (final purchase in periodPurchases) {
    if (purchase.isReturn) {
      purchasesTotal -= purchase.total;
    } else {
      purchasesTotal += purchase.remainingTotal;
    }
  }

  // ── Product count ───────────────────────────────────────────────────────
  final productsCount = allProducts.length;

  // ── Cost of goods sold + net profit ─────────────────────────────────────
  final costByProductId = <String, double>{
    for (final product in allProducts)
      if (product.hasCost) product.id: product.costPrice!,
  };
  final cogs = _computeCogs(periodSales, costByProductId);

  // ── Chart data: daily breakdown over the period ─────────────────────────
  final chartData = _buildChartData(
    periodSales,
    start: start,
    end: end,
    filter: filter,
    now: referenceNow,
  );

  return ReportData(
    netProfit: revenue - cogs,
    costOfGoodsSold: cogs,
    salesCount: salesCount,
    averageSaleValue: averageSaleValue,
    importsTotal: purchasesTotal,
    exportsTotal: revenue,
    debtsTotal: computeTotalDebt(allDebtTransactions),
    productsCount: productsCount,
    chartData: chartData,
  );
}

/// Cost of goods sold for the given sales, using current product costs.
///
/// Mirrors the revenue convention so profit and revenue stay comparable:
///   - A normal sale adds cost for every unit sold, minus the units returned
///     against it (its `returnedItems`).
///   - A standalone return record subtracts the cost of its units.
///   - Products with no recorded cost contribute nothing.
double _computeCogs(
  List<Sale> periodSales,
  Map<String, double> costByProductId,
) {
  double cogs = 0.0;

  for (final sale in periodSales) {
    final sign = sale.isReturn ? -1.0 : 1.0;

    for (final item in sale.items) {
      final unitCost = costByProductId[item.productId];
      if (unitCost == null) continue;
      cogs += sign * unitCost * item.quantity;
    }

    // Units returned against a normal sale never left the shop, so their
    // cost is removed. Standalone return records already carry the sign above.
    if (!sale.isReturn) {
      for (final item in sale.returnedItems ?? const <SaleItem>[]) {
        final unitCost = costByProductId[item.productId];
        if (unitCost == null) continue;
        cogs -= unitCost * item.quantity;
      }
    }
  }

  return cogs;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Chart data builders
// ═══════════════════════════════════════════════════════════════════════════════

/// Builds a map of label → daily net revenue for the chart.
///
/// Day labels use short locale-independent English keys (Mon, Tue, … / Jan,
/// Feb, …) so the screen can localise them. The map is zero-filled: every day
/// in the range gets an entry, even if no sales occurred.
Map<String, double> _buildChartData(
  List<Sale> periodSales, {
  required DateTime start,
  required DateTime end,
  required ReportTimeFilter filter,
  required DateTime now,
}) {
  final data = <String, double>{};

  switch (filter) {
    case ReportTimeFilter.week:
    case ReportTimeFilter.custom:
      // Daily breakdown.
      final days = end.difference(start).inDays.clamp(1, 365);
      for (int i = 0; i <= days; i++) {
        final day = start.add(Duration(days: i));
        final key = '${day.day}/${day.month}';
        data[key] = 0.0;
      }
      for (final sale in periodSales) {
        final key =
            '${sale.createdAt.day}/${sale.createdAt.month}';
        final contribution = sale.isReturn
            ? -sale.total
            : sale.remainingTotal;
        data[key] = (data[key] ?? 0.0) + contribution;
      }
      break;

    case ReportTimeFilter.month:
      // Weekly breakdown within the month.
      final monthStart = start;
      final monthEnd = end;
      int weekIndex = 1;
      DateTime weekStart = monthStart;
      while (weekStart.isBefore(monthEnd)) {
        final weekEnd = weekStart.add(const Duration(days: 6));
        final key = 'W$weekIndex';
        data[key] = 0.0;
        weekStart = weekEnd.add(const Duration(days: 1));
        weekIndex++;
      }
      for (final sale in periodSales) {
        final dayOfMonth = sale.createdAt.day;
        final weekNum = ((dayOfMonth - 1) ~/ 7) + 1;
        final key = 'W$weekNum';
        final contribution = sale.isReturn
            ? -sale.total
            : sale.remainingTotal;
        data[key] = (data[key] ?? 0.0) + contribution;
      }
      break;

    case ReportTimeFilter.year:
      // Monthly breakdown.
      for (int m = 1; m <= 12; m++) {
        data[_shortMonthKey(m)] = 0.0;
      }
      for (final sale in periodSales) {
        if (sale.createdAt.year != now.year) continue;
        final key = _shortMonthKey(sale.createdAt.month);
        final contribution = sale.isReturn
            ? -sale.total
            : sale.remainingTotal;
        data[key] = (data[key] ?? 0.0) + contribution;
      }
      break;
  }

  return data;
}

/// Returns a stable English month key (e.g., "Jan", "Feb") for the given month
/// number (1-based).
///
/// These keys are data identifiers, not display text: this helper stays pure
/// (no `.tr()`), and the screen localises them for display via
/// `_localizeChartLabel` in reports_screen.dart.
String _shortMonthKey(int month) {
  const names = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return names[month - 1];
}

/// Month number (1-based) for a key produced by [_shortMonthKey], or null.
int? monthNumberFromChartKey(String key) {
  const names = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final index = names.indexOf(key);
  return index == -1 ? null : index + 1;
}

/// Week number for a `W<n>` chart key, or null when the key is another shape.
int? weekNumberFromChartKey(String key) {
  if (key.length < 2 || !key.startsWith('W')) return null;
  return int.tryParse(key.substring(1));
}