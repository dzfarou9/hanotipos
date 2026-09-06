// lib/helpers/suppliers_stock_policy.dart

import '../models/purchase_model.dart';

/// قواعد نقاء للمخزون: سقوف الإرجاع ومنع الكميات السالبة.
/// دوال ثابتة بدون حالة حتى تُختبر بسهولة.
abstract class SuppliersStockPolicy {
  /// السقف المتاح للإرجاع = المشترى − المرتجع سابقاً، ولا ينزل تحت الصفر.
  static int returnCap(
      {required int purchasedQuantity, required int alreadyReturnedQuantity}) {
    final cap = purchasedQuantity - alreadyReturnedQuantity;
    return cap < 0 ? 0 : cap;
  }

  /// هل تطبيق [change] على الكمية الحالية يجعلها سالبة؟
  static bool wouldGoNegative({required int currentQuantity, required int change}) {
    return currentQuantity + change < 0;
  }

  /// يتحقق من كميات مرتجع جديد ضد الشراء الأصلي.
  /// يعيد معرفات المنتجات التي تجاوزت سقفها أو ليست في الشراء الأصلي.
  static List<String> invalidReturnProducts({
    required List<PurchaseItem> originalItems,
    required Map<String, int> returnedSoFarByProductId,
    required Map<String, int> newReturnByProductId,
  }) {
    final caps = <String, int>{};
    for (final item in originalItems) {
      caps[item.productId] =
          (caps[item.productId] ?? 0) + item.quantity;
    }

    final invalid = <String>[];
    newReturnByProductId.forEach((productId, newQty) {
      if (newQty <= 0) return;
      final purchased = caps[productId];
      if (purchased == null) {
        invalid.add(productId);
        return;
      }
      final already = returnedSoFarByProductId[productId] ?? 0;
      if (newQty > returnCap(purchasedQuantity: purchased, alreadyReturnedQuantity: already)) {
        invalid.add(productId);
      }
    });
    return invalid;
  }
}
