// lib/helpers/sync_policy.dart

/// منطق قرارات مزامنة ما بعد تسجيل الدخول.
/// دوال نقية (pure) لسهولة الاختبار دون Firebase أو Hive.
class SyncPolicy {
  SyncPolicy._();

  /// هل نعيد المحاولة بعد فشل محاولة مزامنة؟
  /// [attempt] رقم المحاولة المنتهية (تبدأ من 1).
  static bool shouldRetryAfterFailure({
    required int attempt,
    required int maxRetries,
  }) {
    return attempt < maxRetries;
  }

  /// هل المخزن المحلي فارغ تماماً ويحتاج سحباً مباشراً من Firebase؟
  static bool needsDirectPull({
    required int productCount,
    required int saleCount,
  }) {
    return productCount == 0 && saleCount == 0;
  }
}
