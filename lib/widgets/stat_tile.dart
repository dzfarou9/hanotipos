import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/design_tokens.dart';

/// Shared KPI stat tile for the HANOTI POS design system.
///
/// Icon chip + value + label + optional delta pill. Replaces the per-screen
/// stat chip/card/pill variants.
class StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? deltaText;
  final Color? deltaColor;
  final bool showShadow;
  final String? subtitle;
  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.deltaText,
    this.deltaColor,
    this.showShadow = false,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final valueColor = isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final labelColor = isDark ? AppColors.textDarkTertiary : AppColors.textLightTertiary;

    final tile = Container(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.space16, vertical: DesignTokens.space12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(
          color: isDark
              ? AppColors.grey700.withValues(alpha: 0.35)
              : AppColors.grey200.withValues(alpha: 0.6),
        ),
        boxShadow: showShadow ? DesignTokens.softShadow(context) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                padding: const EdgeInsets.all(DesignTokens.space8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              if (deltaText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (deltaColor ?? color).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    deltaText!,
                    style: AppTextStyles.caption(
                      color: deltaColor ?? color,
                      fontSize: 11,
                    ).copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTextStyles.statNumber(color: valueColor).copyWith(fontSize: 22, fontWeight: FontWeight.w800),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.caption(color: labelColor, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: AppTextStyles.overline(color: labelColor, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return tile;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        child: tile,
      ),
    );
  }
}