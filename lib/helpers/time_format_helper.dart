// lib/helpers/time_format_helper.dart
// أدوات تنسيق الوقت النسبي (منذ متى) مشتركة بين الشاشات.

import 'localization_helper.dart';

/// تنسيق الوقت النسبي لعرض "منذ متى" (الآن / د / س / يوم / تاريخ).
///
/// يعتمد على `LocalizationHelper` لضمان الترجمة. متاح للوحة التحكم
/// وقائمة الطلبات المعلقة وغيرها من الشاشات التي تعرض طوابع زمنية نسبية.
String formatTimeAgo(DateTime dateTime) {
  final now = DateTime.now();
  final diff = now.difference(dateTime);
  if (diff.inMinutes < 1) return LocalizationHelper.dashboardJustNow;
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} ${LocalizationHelper.dashboardMinutesAgo}';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} ${LocalizationHelper.dashboardHoursAgo}';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays} ${LocalizationHelper.dashboardDaysAgo}';
  }
  return '${dateTime.day}/${dateTime.month}';
}
