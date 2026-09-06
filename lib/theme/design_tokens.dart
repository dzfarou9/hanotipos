import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Design tokens for the HANOTI POS design system.
///
/// A single source of truth for corner radii, spacing, durations and shadows
/// so every screen converges on the same visual rhythm.
class DesignTokens {
  DesignTokens._();

  // ==================== Corner Radii ====================
  static const double radiusXs = 8;
  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 20;
  static const double radiusXl = 28;
  static const double radiusPill = 999;

  // ==================== Spacing Scale ====================
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;

  /// Standard horizontal page margin.
  static const double pageMargin = 16;

  /// Standard gap between major page sections.
  static const double sectionGap = 24;

  // ==================== Durations ====================
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 250);
  static const Duration animSlow = Duration(milliseconds: 400);

  // ==================== Shadows ====================
  /// Subtle resting elevation for cards and tiles.
  static List<BoxShadow> softShadow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: isDark ? AppColors.shadowColorDark : AppColors.shadowColor,
        blurRadius: 14,
        spreadRadius: -2,
        offset: const Offset(0, 4),
      ),
    ];
  }

  /// Standard card elevation — slightly more present than [softShadow].
  static List<BoxShadow> cardShadow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: isDark
            ? AppColors.shadowColorDark
            : const Color(0xFF0F1B16).withValues(alpha: 0.08),
        blurRadius: 20,
        spreadRadius: -4,
        offset: const Offset(0, 8),
      ),
    ];
  }

  /// Prominent elevation for floating / raised surfaces (nav bar, sheets, FAB).
  static List<BoxShadow> raisedShadow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: isDark
            ? Colors.black.withValues(alpha: 0.5)
            : const Color(0xFF0F1B16).withValues(alpha: 0.12),
        blurRadius: 28,
        spreadRadius: -6,
        offset: const Offset(0, 12),
      ),
    ];
  }

  /// Colored glow, e.g. under the primary CTA or accent hero.
  static List<BoxShadow> accentGlow(Color color, {double opacity = 0.28}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: 24,
        spreadRadius: -6,
        offset: const Offset(0, 10),
      ),
    ];
  }

  // ==================== Borders ====================
  static BorderSide hairline(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BorderSide(
      color: isDark
          ? AppColors.grey700.withValues(alpha: 0.5)
          : AppColors.grey200.withValues(alpha: 0.8),
      width: 1,
    );
  }
}
