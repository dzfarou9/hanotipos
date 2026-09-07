// lib/helpers/quantity_format.dart
//
// Decimal-quantity math/format for weighted products (kg/litre).
// Pure helpers — no services, no Flutter.

/// كمية عشرية بثلاث منازل: كل الكميات تمرّ هنا قبل الحفظ أو العرض.
class QuantityFormat {
  /// هامش مقارنة الكميات العشرية (نفس نمط debt_ledger_helper).
  static const double epsilon = 0.001;

  /// يقرب إلى 3 منازل عشرية.
  static double round(double v) => (v * 1000).roundToDouble() / 1000;

  /// يزيل الأصفار الزائدة: 2.0 → "2"، 0.850 → "0.85".
  static String quantity(double v) {
    final s = round(v).toStringAsFixed(3);
    if (!s.contains('.')) return s;
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// كمية مع وحدتها: "0.85 kg" / "12.5 كغ".
  static String withUnit(double v, String unit) {
    // الترجمة تتم عند المستدعي عبر unitLabel؛ هنا نص الوحدة الخام.
    return '${quantity(v)} $unit';
  }

  // ── مقارنات بهامش ──
  static bool isZeroQty(double v) => v.abs() <= epsilon;
  static bool greaterThanQty(double a, double b) => a - b > epsilon;
  static bool exceedsQty(double value, double cap) => value - cap > epsilon;
}
