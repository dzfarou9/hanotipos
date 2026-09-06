import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/design_tokens.dart';
import '../theme/screen_palette.dart';

/// Shared empty-state for the HANOTI POS design system.
///
/// Circle icon wash + title + optional subtitle + optional action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final captionColor = isDark ? AppColors.textDarkTertiary : AppColors.textLightTertiary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 32,
                color: isDark ? AppColors.textDarkTertiary : AppColors.primary,
              ),
            ),
            const SizedBox(height: DesignTokens.space16),
            Text(
              title,
              style: AppTextStyles.bodyLarge(color: titleColor),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: DesignTokens.space8),
              Text(
                subtitle!,
                style: AppTextStyles.bodyMedium(color: captionColor),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: DesignTokens.space20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}