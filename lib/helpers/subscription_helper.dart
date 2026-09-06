// lib/helpers/subscription_helper.dart
//
// حسابات الاشتراك — دوال نقية بالكامل.
//
// لا Hive ولا Firestore ولا Flutter هنا: المدخل تواريخ وقيم والمخرج أرقام
// وحالات، تماماً كباقي مساعدي `lib/helpers/` (انظر debt_ledger_helper.dart).
//
// المبادئ الثابتة
// ---------------
//   - عدّ الأيام بالتقريب لأعلى (ceil) لا بالقصّ: اشتراك ينتهي بعد 23 ساعة
//     يبقى "يوم واحد" لا "صفر". القصّ (`Duration.inDays`) كان يعرض 0 لمشترك
//     نشط — وهو سبب عرض «0 يوم» في شاشتي الملف الشخصي والإعدادات.
//   - الاشتراك المنتهي يعطي صفراً دائماً، ولا يعطي رقماً سالباً.
//   - النوع (plan_type) لا يُخترع أبداً: إن لم يكن محفوظاً فهو null والواجهة
//     تعرض تسمية عامة. اختراع 'trial' كان يُظهر كل اشتراك مدفوع كتجريبي.

/// عدد الأيام المتبقية حتى [endDate] منسوبة إلى [now].
///
/// يُقرِّب لأعلى: أي جزء من يوم يُحسب يوماً كاملاً، فآخر يوم لا يظهر صفراً
/// بينما الاشتراك ما زال نشطاً. يعيد صفراً إذا انتهى الاشتراك.
int daysRemaining(DateTime endDate, DateTime now) {
  if (!now.isBefore(endDate)) return 0;
  final remaining = endDate.difference(now);
  final wholeDays = remaining.inDays;
  // أي بقية بعد الأيام الكاملة تعني أننا داخل يوم آخر.
  final hasPartialDay = remaining > Duration(days: wholeDays);
  return hasPartialDay ? wholeDays + 1 : wholeDays;
}

/// هل الاشتراك ما زال سارياً بتاريخ انتهائه فقط؟
///
/// [endDate] فارغ (null) يعني «لا اشتراك» = غير ساري.
bool isSubscriptionValid(DateTime? endDate, DateTime now) {
  if (endDate == null) return false;
  return now.isBefore(endDate);
}

/// هل يُقبل مخزن Hive كدليل صلاحية عند تعذر الوصول للسيرفر؟
///
/// قاعدة «الإيجار» (C-2): نشط + تاريخ انتهاء مستقبلي + تحقق ناجح من
/// السيرفر خلال [leaseDuration]. أي شرط ناقص يُبطل الإيجار.
bool isLeaseValid({
  required bool isActive,
  required DateTime? endDate,
  required DateTime? lastVerified,
  required Duration leaseDuration,
  required DateTime now,
}) {
  if (!isActive) return false;
  if (endDate == null || lastVerified == null) return false;
  if (!now.isBefore(endDate)) return false;
  return now.difference(lastVerified) <= leaseDuration;
}
