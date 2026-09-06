import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/design_tokens.dart';

/// Unified snackbar feedback for HANOTI POS.
///
/// Replaces the per-screen `_showSnack` variants with one consistent recipe:
/// floating, rounded, semantic leading icon, and a colored accent bar.
enum AppSnackType { success, error, info, warning }

class AppSnackBar {
  AppSnackBar._();

  static void show(
    BuildContext context,
    String message, {
    AppSnackType type = AppSnackType.info,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (color, icon) = _resolve(type, isDark);

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: duration,
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.darkSurfaceAlt : AppColors.grey900,
        elevation: 6,
        margin: const EdgeInsets.all(DesignTokens.space12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        ),
        content: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: DesignTokens.space12),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.bodyMedium(color: AppColors.white),
              ),
            ),
          ],
        ),
        action: action,
      ),
    );
  }

  static void success(BuildContext context, String message) =>
      show(context, message, type: AppSnackType.success);
  static void error(BuildContext context, String message) =>
      show(context, message, type: AppSnackType.error);
  static void info(BuildContext context, String message) =>
      show(context, message, type: AppSnackType.info);
  static void warning(BuildContext context, String message) =>
      show(context, message, type: AppSnackType.warning);

  static (Color, IconData) _resolve(AppSnackType type, bool isDark) {
    switch (type) {
      case AppSnackType.success:
        return (isDark ? AppColors.successOnDark : AppColors.success,
            Icons.check_circle_rounded);
      case AppSnackType.error:
        return (isDark ? AppColors.errorOnDark : AppColors.error,
            Icons.error_rounded);
      case AppSnackType.warning:
        return (isDark ? AppColors.warningOnDark : AppColors.warning,
            Icons.warning_rounded);
      case AppSnackType.info:
        return (isDark ? AppColors.infoOnDark : AppColors.info,
            Icons.info_rounded);
    }
  }
}
