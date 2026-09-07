// lib/helpers/suppliers_stock_policy.dart

import '../helpers/quantity_format.dart';
import '../models/purchase_model.dart';

/// قواعد نقاء للمخزون: سقوف الإرجاع ومنع الكميات السالبة.
/// دوال ثابتة بدون حالة حتى تُختبر بسهولة.
abstract class SuppliersStockPolicy {
  /// السقف المتاح للإرجاع = المشترى − المرتجع سابقاً، ولا ينزل تحت الصفر.
  static double returnCap(
      {required double purchasedQuantity, required double alreadyReturnedQuantity}) {
    final cap = purchasedQuantity - alreadyReturnedQuantity;
    return cap <= QuantityFormat.epsilon ? 0.0 : QuantityFormat.round(cap);
  }

  /// هل تطبيق [change] على الكمية الحالية يجعلها سالبة؟
  static bool wouldGoNegative({required double currentQuantity, required double change}) {
    return currentQuantity + change < -QuantityFormat.epsilon;
  }

  /// يتحقق من كميات مرتجع جديد ضد الشراء الأصلي.
  /// يعيد معرفات المنتجات التي تجاوزت سقفها أو ليست في الشراء الأصلي.
  static List<String> invalidReturnProducts({
    required List<PurchaseItem> originalItems,
    required Map<String, double> returnedSoFarByProductId,
    required Map<String, double> newReturnByProductId,
  }) {
    final caps = <String, double>{};
    for (final item in originalItems) {
      caps[item.productId] =
          (caps[item.productId] ?? 0.0) + item.quantity;
    }

    final invalid = <String>[];
    newReturnByProductId.forEach((productId, newQty) {
      if (QuantityFormat.isZeroQty(newQty) || newQty < 0) return;
      final purchased = caps[productId];
      if (purchased == null) {
        invalid.add(productId);
        return;
      }
      final already = returnedSoFarByProductId[productId] ?? 0.0;
      if (QuantityFormat.exceedsQty(newQty, returnCap(purchasedQuantity: purchased, alreadyReturnedQuantity: already))) {
        invalid.add(productId);
      }
    });
    return invalid;
  }
}
