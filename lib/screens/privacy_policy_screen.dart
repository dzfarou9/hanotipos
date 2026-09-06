// lib/screens/privacy_policy_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../helpers/localization_helper.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/design_tokens.dart';
import '../theme/screen_palette.dart';

/// شاشة سياسة الخصوصية.
///
/// تعرض بنود الخصوصية بناءً على البيانات التي يجمعها التطبيق فعلياً،
/// مع دعم كامل للوضع الليلي والاتجاه (RTL).
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final accentColor = context.accent;

    final sections = [
      (
        title: LocalizationHelper.privacyIntroTitle,
        body: LocalizationHelper.privacyIntroBody,
      ),
      (
        title: LocalizationHelper.privacyCollectTitle,
        body: LocalizationHelper.privacyCollectBody,
      ),
      (
        title: LocalizationHelper.privacyUseTitle,
        body: LocalizationHelper.privacyUseBody,
      ),
      (
        title: LocalizationHelper.privacyStorageTitle,
        body: LocalizationHelper.privacyStorageBody,
      ),
      (
        title: LocalizationHelper.privacyCameraTitle,
        body: LocalizationHelper.privacyCameraBody,
      ),
      (
        title: LocalizationHelper.privacySharingTitle,
        body: LocalizationHelper.privacySharingBody,
      ),
      (
        title: LocalizationHelper.privacySecurityTitle,
        body: LocalizationHelper.privacySecurityBody,
      ),
      (
        title: LocalizationHelper.privacyRetentionTitle,
        body: LocalizationHelper.privacyRetentionBody,
      ),
      (
        title: LocalizationHelper.privacyRightsTitle,
        body: LocalizationHelper.privacyRightsBody,
      ),
      (
        title: LocalizationHelper.privacyChildrenTitle,
        body: LocalizationHelper.privacyChildrenBody,
      ),
      (
        title: LocalizationHelper.privacyChangesTitle,
        body: LocalizationHelper.privacyChangesBody,
      ),
      (
        title: LocalizationHelper.privacyContactTitle,
        body: LocalizationHelper.privacyContactBody,
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
          LocalizationHelper.privacyTitle,
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
                        Icons.privacy_tip_rounded,
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
                            LocalizationHelper.privacyTitle,
                            style: AppTextStyles.titleLarge(
                              color: AppColors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            LocalizationHelper.privacyLastUpdated('16/08/2026'),
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
                (section) => _PrivacySection(
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

/// قسم واحد من بنود السياسة (عنوان + نص).
class _PrivacySection extends StatelessWidget {
  final String title;
  final String body;

  const _PrivacySection({required this.title, required this.body});

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
