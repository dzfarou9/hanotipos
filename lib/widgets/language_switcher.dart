// lib/widgets/language_switcher.dart

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/design_tokens.dart';

/// A compact dropdown button that lets the user switch the app language.
///
/// Shows the current language code (e.g. EN / AR / FR) with a globe icon and
/// opens a menu listing the supported languages. Selecting one calls
/// [context.setLocale] so EasyLocalization persists and applies the choice.
class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    final fgColor = isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;

    final menuItems = <PopupMenuItem<Locale>>[
      PopupMenuItem<Locale>(
        value: const Locale('ar'),
        child: Text(
          context.tr('settings.arabic'),
          style: AppTextStyles.bodyMedium(color: fgColor),
        ),
      ),
      PopupMenuItem<Locale>(
        value: const Locale('fr'),
        child: Text(
          context.tr('settings.french'),
          style: AppTextStyles.bodyMedium(color: fgColor),
        ),
      ),
      PopupMenuItem<Locale>(
        value: const Locale('en'),
        child: Text(
          context.tr('settings.english'),
          style: AppTextStyles.bodyMedium(color: fgColor),
        ),
      ),
    ];

    return PopupMenuButton<Locale>(
      tooltip: context.tr('settings.language'),
      color: isDark ? AppColors.darkSurface : AppColors.white,
      onSelected: (locale) => context.setLocale(locale),
      itemBuilder: (context) => menuItems,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.space12,
          vertical: DesignTokens.space8,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurface.withValues(alpha: 0.8)
              : AppColors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
          border: Border.all(color: accentColor.withValues(alpha: 0.35)),
          boxShadow: DesignTokens.softShadow(context),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language_rounded, size: 18, color: accentColor),
            const SizedBox(width: DesignTokens.space4),
            Text(
              context.locale.languageCode.toUpperCase(),
              style: AppTextStyles.labelMedium(color: accentColor),
            ),
          ],
        ),
      ),
    );
  }
}
