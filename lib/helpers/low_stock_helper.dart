import '../models/product_model.dart';
import 'quantity_format.dart';

/// نتيجة تصنيف المنتجات حسب حالة المخزون.
class LowStockResult {
  /// منتجات المخزون المنخفض (الكمية بين 1 والعتبة شاملة).
  final List<Product> lowStock;

  /// منتجات نفد مخزونها (الكمية صفر).
  final List<Product> outOfStock;

  const LowStockResult({
    required this.lowStock,
    required this.outOfStock,
  });
}

/// يصنّف المنتجات إلى منخفضة المخزون ونافدة المخزون.
///
/// يعتمد على عتبة كل منتج (`minStockLevel`) — يتطابق التعريف مع إحصائيات
/// `DatabaseService.getInventoryStats()` (lowStock = كمية بين 1 وعتبة
/// المنتج، outOfStock = كمية صفر) ليتطابق عدد القائمة مع قيمة بطاقة
/// Low Stock في لوحة التحكم.
LowStockResult classifyLowStockProducts(List<Product> products) {
  final lowStock = <Product>[];
  final outOfStock = <Product>[];

  for (final product in products) {
    if (QuantityFormat.isZeroQty(product.quantity)) {
      outOfStock.add(product);
    } else if (product.quantity <= product.minStockLevel) {
      lowStock.add(product);
    }
  }

  return LowStockResult(lowStock: lowStock, outOfStock: outOfStock);
}