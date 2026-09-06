import '../models/product_model.dart';
import '../models/sale_model.dart';

/// منتج من أفضل المنتجات مع إحصاءات مبيعاته.
class TopProduct {
  final Product product;

  /// كمية المبيعات الصافية (بعد خصم المرتجعات) في الشهر الحالي.
  final int quantity;

  /// إجمالي قيمة مبيعات المنتج في الشهر الحالي.
  final double totalSales;

  const TopProduct({
    required this.product,
    required this.quantity,
    required this.totalSales,
  });
}

/// يحسب أفضل المنتجات من حيث كمية المبيعات في الشهر الحالي.
///
/// - تمريرة واحدة على الفواتير مع تجميع مسبق لكميات/مبالغ المرتجعات لكل
///   فاتورة (تجنب البحث المتداخل لكل عنصر).
/// - يستبعد فواتير المرتجع (`isReturn`) والعمليات خارج الشهر الحالي.
/// - يخصم المرتجعات الجزئية من الكمية والإجمالي.
/// - يرتب تنازلياً حسب الكمية ويعيد أفضل `limit` منتج.
List<TopProduct> calculateTopProducts(
  List<Sale> allSales,
  List<Product> allProducts, {
  int limit = 3,
}) {
  final productById = {
    for (var product in allProducts) product.id: product,
  };
  final Map<String, int> productQuantity = {};
  final Map<String, double> productAmount = {};

  final now = DateTime.now();
  for (var sale in allSales) {
    if (sale.isReturn) continue;
    if (sale.createdAt.year != now.year ||
        sale.createdAt.month != now.month) {
      continue;
    }

    // ⭐ تجميع مسبق للمرتجعات لهذه الفاتورة (كمية ومبلغ لكل منتج)
    final returnedQty = <String, int>{};
    final returnedAmount = <String, double>{};
    if (sale.returnedItems != null) {
      for (var returned in sale.returnedItems!) {
        returnedQty[returned.productId] =
            (returnedQty[returned.productId] ?? 0) + returned.quantity;
        returnedAmount[returned.productId] =
            (returnedAmount[returned.productId] ?? 0) + returned.subtotal;
      }
    }

    for (var item in sale.items) {
      final netQty = item.quantity - (returnedQty[item.productId] ?? 0);
      if (netQty <= 0) continue;
      final netAmount = item.subtotal - (returnedAmount[item.productId] ?? 0);
      productQuantity[item.productId] =
          (productQuantity[item.productId] ?? 0) + netQty;
      productAmount[item.productId] =
          (productAmount[item.productId] ?? 0) + netAmount;
    }
  }

  final sorted = productQuantity.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final topProducts = <TopProduct>[];
  for (var entry in sorted.take(limit)) {
    final product = productById[entry.key];
    if (product == null) continue;
    topProducts.add(
      TopProduct(
        product: product,
        quantity: entry.value,
        totalSales: productAmount[entry.key] ?? 0.0,
      ),
    );
  }
  return topProducts;
}