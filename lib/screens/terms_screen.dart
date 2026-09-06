// lib/screens/terms_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../helpers/localization_helper.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/design_tokens.dart';
import '../theme/screen_palette.dart';

/// شاشة الشروط والأحكام.
///
/// تعرض بنود الاستخدام التفصيلية للتطبيق، مع دعم كامل للوضع الليلي
/// والاتجاه (RTL).
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final accentColor = context.accent;

    final sections = [
      (
        title: LocalizationHelper.termsIntroTitle,
        body: LocalizationHelper.termsIntroBody,
      ),
      (
        title: LocalizationHelper.termsServiceTitle,
        body: LocalizationHelper.termsServiceBody,
      ),
      (
        title: LocalizationHelper.termsAccountTitle,
        body: LocalizationHelper.termsAccountBody,
      ),
      (
        title: LocalizationHelper.termsSubscriptionTitle,
        body: LocalizationHelper.termsSubscriptionBody,
      ),
      (
        title: LocalizationHelper.termsUseTitle,
        body: LocalizationHelper.termsUseBody,
      ),
      (
        title: LocalizationHelper.termsAccuracyTitle,
        body: LocalizationHelper.termsAccuracyBody,
      ),
      (
        title: LocalizationHelper.termsIpTitle,
        body: LocalizationHelper.termsIpBody,
      ),
      (
        title: LocalizationHelper.termsPrivacyTitle,
        body: LocalizationHelper.termsPrivacyBody,
      ),
      (
        title: LocalizationHelper.termsLiabilityTitle,
        body: LocalizationHelper.termsLiabilityBody,
      ),
      (
        title: LocalizationHelper.termsTerminationTitle,
        body: LocalizationHelper.termsTerminationBody,
      ),
      (
        title: LocalizationHelper.termsChangesTitle,
        body: LocalizationHelper.termsChangesBody,
      ),
      (
        title: LocalizationHelper.termsLawTitle,
        body: LocalizationHelper.termsLawBody,
      ),
      (
        title: LocalizationHelper.termsContactTitle,
        body: LocalizationHelper.termsContactBody,
      ),
    ];

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          },
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(Icons.arrow_back_rounded, color: accentColor),
        ),
        title: Text(
          LocalizationHelper.termsTitle,
          style: AppTextStyles.headline4(
            color: isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DesignTokens.pageMargin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(DesignTokens.space20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? AppColors.neonGradient
                        : AppColors.primaryGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                      ),
                      child: const Icon(
                        Icons.description_rounded,
                        color: AppColors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: DesignTokens.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            LocalizationHelper.termsTitle,
                            style: AppTextStyles.titleLarge(
                              color: AppColors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            LocalizationHelper.termsLastUpdated('16/08/2026'),
                            style: AppTextStyles.caption(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DesignTokens.space24),
              ...sections.map(
                (section) => _TermsSection(
                  title: section.title,
                  body: section.body,
                ),
              ),
              const SizedBox(height: DesignTokens.space8),
            ],
          ),
        ),
      ),
    );
  }
}

/// قسم واحد من بنود الشروط (عنوان + نص).
class _TermsSection extends StatelessWidget {
  final String title;
  final String body;

  const _TermsSection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Container(
      margin: const EdgeInsets.only(bottom: DesignTokens.space16),
      padding: const EdgeInsets.all(DesignTokens.space16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(
          color: isDark
              ? AppColors.grey700.withValues(alpha: 0.35)
              : AppColors.grey200.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? AppColors.neonGradient
                        : AppColors.primaryGradient,
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: DesignTokens.space12),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.titleMedium(
                    color: isDark
                        ? AppColors.textDarkPrimary
                        : AppColors.textLightPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.space12),
          Text(
            body,
            style: AppTextStyles.bodyMedium(
              color: isDark
                  ? AppColors.textDarkSecondary
                  : AppColors.textLightSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
