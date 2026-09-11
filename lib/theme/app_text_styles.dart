import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Typography for HANOTI POS.
///
/// Uses the bundled **Tajawal** family (Regular 400 / Medium 500 / Bold 700)
/// which ships with the app, so Arabic, Latin and French all render with a
/// single cohesive typeface — and it works fully offline (no runtime font
/// fetch). Weights above 700 map to the nearest bundled weight.
class AppTextStyles {
  AppTextStyles._();

  static const String fontFamily = 'Tajawal';

  static TextStyle _base({
    required double fontSize,
    required FontWeight fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? AppColors.textLightPrimary,
        letterSpacing: letterSpacing,
        height: height,
      );

  // ==================== Headings ====================
  static TextStyle headline1({Color? color}) => _base(
        fontSize: 32, fontWeight: FontWeight.w700,
        color: color, letterSpacing: -0.5, height: 1.15,
      );

  static TextStyle headline2({Color? color}) => _base(
        fontSize: 28, fontWeight: FontWeight.w700,
        color: color, letterSpacing: -0.4, height: 1.18,
      );

  static TextStyle headline3({Color? color}) => _base(
        fontSize: 24, fontWeight: FontWeight.w700,
        color: color, letterSpacing: -0.3, height: 1.2,
      );

  static TextStyle headline4({Color? color}) => _base(
        fontSize: 20, fontWeight: FontWeight.w700,
        color: color, letterSpacing: -0.2, height: 1.25,
      );

  // ==================== Titles ====================
  static TextStyle titleLarge({Color? color}) => _base(
        fontSize: 17, fontWeight: FontWeight.w700, color: color, height: 1.3,
      );

  static TextStyle titleMedium({Color? color}) => _base(
        fontSize: 15, fontWeight: FontWeight.w500, color: color, height: 1.35,
      );

  // ==================== Body Text ====================
  static TextStyle bodyLarge({Color? color, double? fontSize}) => _base(
        fontSize: fontSize ?? 16, fontWeight: FontWeight.w400,
        color: color, height: 1.45,
      );

  static TextStyle bodyMedium({Color? color, double? fontSize}) => _base(
        fontSize: fontSize ?? 14, fontWeight: FontWeight.w400,
        color: color ?? AppColors.textLightSecondary, height: 1.45,
      );

  static TextStyle bodySmall({Color? color, double? fontSize}) => _base(
        fontSize: fontSize ?? 12, fontWeight: FontWeight.w400,
        color: color ?? AppColors.textLightTertiary, height: 1.4,
      );

  // ==================== Labels (semantic) ====================
  static TextStyle labelLarge({Color? color}) => _base(
        fontSize: 14, fontWeight: FontWeight.w500, color: color,
      );

  static TextStyle labelMedium({Color? color}) => _base(
        fontSize: 12, fontWeight: FontWeight.w500,
        color: color ?? AppColors.textLightSecondary,
      );

  // ==================== Special Text ====================
  static TextStyle buttonText({Color? color, double? fontSize}) => _base(
        fontSize: fontSize ?? 15, fontWeight: FontWeight.w700,
        color: color ?? AppColors.white, letterSpacing: 0.2,
      );

  static TextStyle caption({Color? color, double? fontSize}) => _base(
        fontSize: fontSize ?? 12, fontWeight: FontWeight.w400,
        color: color ?? AppColors.textLightTertiary,
      );

  static TextStyle overline({Color? color, double? fontSize}) => _base(
        fontSize: fontSize ?? 11, fontWeight: FontWeight.w700,
        color: color ?? AppColors.textLightTertiary, letterSpacing: 0.8,
      );

  // ==================== Numbers ====================
  // ⭐ أرقام جدولية (tabular figures): عرض كل رقم متساوٍ فتصطف الأعمدة
  // المالية (الأسعار، الإجماليات، الكميات) عمودياً في القوائم والتقارير.
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static TextStyle statNumber({Color? color}) => _base(
        fontSize: 28, fontWeight: FontWeight.w700,
        color: color, letterSpacing: -0.5,
      ).copyWith(fontFeatures: _tabular);

  static TextStyle priceLarge({Color? color}) => _base(
        fontSize: 24, fontWeight: FontWeight.w700,
        color: color ?? AppColors.primary, letterSpacing: -0.3,
      ).copyWith(fontFeatures: _tabular);

  /// أرقام مضمنة في نص عادي (سعر صف، كمية، إجمالي) — بنفس حجم الجسم.
  static TextStyle numeric(
          {Color? color, double fontSize = 14, FontWeight fontWeight = FontWeight.w600}) =>
      _base(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: 1.3,
      ).copyWith(fontFeatures: _tabular);

  // ==================== Dialog Title Helper ====================
  /// Returns appropriate text color for dialog titles based on brightness
  static Color dialogTitleColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.textDarkPrimary
        : AppColors.textLightPrimary;
  }

  /// Returns appropriate text color for dialog body based on brightness
  static Color dialogBodyColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.textDarkSecondary
        : AppColors.textLightSecondary;
  }
}
