import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Context-based semantic palette.
///
/// Replaces the repeated `isDark ? AppColors.neonOrange : AppColors.primary`
/// style ternaries found throughout the app with a single source of truth.
extension ScreenPalette on BuildContext {
  ThemeData get _theme => Theme.of(this);

  Brightness get brightness => _theme.brightness;

  bool get isDark => brightness == Brightness.dark;

  /// Primary brand accent (theme-aware).
  Color get accent => _theme.colorScheme.primary;

  /// Readable text/icon color on top of the primary accent.
  Color get onAccent => _theme.colorScheme.onPrimary;

  /// Primary text color.
  Color get titleColor =>
      isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;

  /// Secondary text color.
  Color get bodyColor =>
      isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;

  /// Tertiary / caption text color.
  Color get captionColor =>
      isDark ? AppColors.textDarkTertiary : AppColors.textLightTertiary;

  /// Elevated surface color (cards, dialogs).
  Color get cardColor => _theme.colorScheme.surface;

  /// Scaffold background color.
  Color get scaffoldColor => _theme.scaffoldBackgroundColor;

  /// Alternate surface color (subtle backgrounds, chips).
  Color get surfaceAlt =>
      isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;

  /// Hairline divider / border color.
  Color get dividerColor =>
      isDark ? AppColors.grey700.withValues(alpha: 0.35) : AppColors.grey200;

  /// Semantic error color tuned for the current brightness.
  Color get errorColor => isDark ? AppColors.errorOnDark : AppColors.error;

  /// Semantic success color tuned for the current brightness.
  Color get successColor =>
      isDark ? AppColors.successOnDark : AppColors.success;

  /// Semantic warning color tuned for the current brightness.
  Color get warningColor =>
      isDark ? AppColors.warningOnDark : AppColors.warning;

  /// Semantic info color tuned for the current brightness.
  Color get infoColor => isDark ? AppColors.infoOnDark : AppColors.info;
}