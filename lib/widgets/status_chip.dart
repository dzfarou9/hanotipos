import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/design_tokens.dart';

/// Shared status/tag badge for the HANOTI POS design system.
///
/// One recipe: radius 8, ≥12px label, semantic color. Tinted by default
/// (colored text on a light wash); use [filled] for solid emphasis.
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;

  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
    this.backgroundColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // In dark mode, lift the semantic color toward white so tinted text stays
    // legible on the dark wash — while preserving its hue.
    final toned = isDark ? Color.lerp(color, AppColors.white, 0.35)! : color;
    final bg = filled
        ? color
        : (backgroundColor ??
            color.withValues(alpha: isDark ? 0.20 : 0.12));
    final fg = filled ? _onFilledColor(context) : toned;

    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
        border: filled
            ? null
            : Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTextStyles.labelMedium(color: fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Color _onFilledColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Bright status colors read better with dark text in both modes.
    if (color == AppColors.warning || color == AppColors.warningOnDark) {
      return isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    }
    return AppColors.white;
  }
}