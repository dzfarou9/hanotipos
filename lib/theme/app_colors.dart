import 'package:flutter/material.dart';

/// Central color palette for HANOTI POS.
///
/// Single-accent system built on a fresh emerald brand root: a deep vivid
/// emerald in light mode, a bright legible emerald in dark mode. Neutrals are
/// a subtly green-tinted slate so surfaces feel calm and cohesive. Warning,
/// error and info use clearly distinct hues so alerts never collide with the
/// primary CTA.
///
/// NOTE: some legacy names (`neonOrange*`) are kept for API compatibility with
/// existing call sites — they now hold the dark-mode emerald values.
class AppColors {
  AppColors._();

  // ==================== Primary — Emerald (light) ====================
  static const Color primary = Color(0xFF00875A);
  static const Color primaryDark = Color(0xFF006C48);
  static const Color primaryVeryLight = Color(0xFFE3F5EE);

  // ==================== Primary — Emerald (dark) ====================
  // Names kept for API compatibility; screens use these in dark mode.
  static const Color neonOrange = Color(0xFF34D399);
  static const Color neonOrangeLight = Color(0xFF6EE7B7);
  static const Color neonOrangeVeryLight = Color(0xFF10362A);

  static const Color accent = Color(0xFF00875A);

  // ==================== Secondary Colors ====================
  static const Color secondary = Color(0xFF0E9384);
  static const Color secondaryLight = Color(0xFF2FD4C0);
  static const Color secondaryDark = Color(0xFF0B756A);
  static const Color secondaryVeryLight = Color(0xFFDFF5F1);

  // ==================== Status Colors ====================
  static const Color success = Color(0xFF16A34A);
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFD97706);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFDC2626);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF2563EB);
  static const Color infoLight = Color(0xFFDBEAFE);

  // Dark-mode friendly status text hues (for semantic text/icons on dark).
  static const Color successOnDark = Color(0xFF4ADE80);
  static const Color warningOnDark = Color(0xFFFBBF24);
  static const Color errorOnDark = Color(0xFFF87171);
  static const Color infoOnDark = Color(0xFF60A5FA);

  // ==================== Background Colors ====================
  static const Color lightBackground = Color(0xFFF4F7F5);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFEBF1EE);

  static const Color darkBackground = Color(0xFF0E1311);
  static const Color darkSurface = Color(0xFF171E1B);
  static const Color darkSurfaceAlt = Color(0xFF212B27);

  // ==================== Text Colors ====================
  static const Color textLightPrimary = Color(0xFF0F1B16);
  static const Color textLightSecondary = Color(0xFF51605A);
  static const Color textLightTertiary = Color(0xFF8A968F);

  static const Color textDarkPrimary = Color(0xFFECF1EE);
  static const Color textDarkSecondary = Color(0xFFB4C0BA);
  static const Color textDarkTertiary = Color(0xFF7C8A83);

  // ==================== Grey Scale ====================
  static const Color grey50 = Color(0xFFF8FAF9);
  static const Color grey100 = Color(0xFFF1F4F2);
  static const Color grey200 = Color(0xFFE3E9E6);
  static const Color grey300 = Color(0xFFCFD8D3);
  static const Color grey400 = Color(0xFF9CA8A2);
  static const Color grey500 = Color(0xFF6B7873);
  static const Color grey600 = Color(0xFF4B5852);
  static const Color grey700 = Color(0xFF374440);
  static const Color grey800 = Color(0xFF1F2925);
  static const Color grey900 = Color(0xFF111815);

  // ==================== Basic Colors ====================
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  // ==================== Gradient Colors ====================
  static const List<Color> primaryGradient = [
    Color(0xFF00A56E),
    Color(0xFF006C48),
  ];
  static const List<Color> secondaryGradient = [
    Color(0xFF12B8A6),
    Color(0xFF0B756A),
  ];
  static const List<Color> neonGradient = [
    Color(0xFF6EE7B7),
    Color(0xFF34D399),
  ];
  static const List<Color> welcomeGradient = [
    Color(0xFF00A56E),
    Color(0xFF006C48),
  ];
  static const List<Color> darkWelcomeGradient = [
    Color(0xFF1B2621),
    Color(0xFF10362A),
  ];

  // ==================== Shadow Colors ====================
  static Color shadowColor = const Color(0xFF0F1B16).withValues(alpha: 0.06);
  static Color shadowColorDark = const Color(0xFF000000).withValues(alpha: 0.40);

  // ==================== Transparent Colors ====================
  static Color primaryWithOpacity(double opacity) =>
      primary.withValues(alpha: opacity);
  static Color neonWithOpacity(double opacity) =>
      neonOrange.withValues(alpha: opacity);
  static Color blackWithOpacity(double opacity) =>
      black.withValues(alpha: opacity);
  static Color whiteWithOpacity(double opacity) =>
      white.withValues(alpha: opacity);
}
