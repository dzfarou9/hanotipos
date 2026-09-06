// lib/screens/subscription_expired_screen.dart

import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../helpers/localization_helper.dart';
import '../widgets/contact_row.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

class SubscriptionExpiredScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(ThemeMode) onThemeModeChange;

  const SubscriptionExpiredScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChange,
  });

  @override
  State<SubscriptionExpiredScreen> createState() =>
      _SubscriptionExpiredScreenState();
}

class _SubscriptionExpiredScreenState extends State<SubscriptionExpiredScreen> {
  bool _isLoading = false;

  Future<void> _handleLogout() async {
    setState(() => _isLoading = true);

    try {
      await AuthService.instance.logout();
    } catch (e) {
      AppConfig.logError('Logout error', e);
    }

    if (mounted) {
      setState(() => _isLoading = false);

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => LoginScreen(
            themeMode: widget.themeMode,
            onThemeModeChange: widget.onThemeModeChange,
          ),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    final bgColor =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final titleColor =
        isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final bodyColor =
        isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(60),
                  ),
                  child: Icon(
                    Icons.subscriptions_rounded,
                    size: 60,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  LocalizationHelper.expiredTitle,
                  style: AppTextStyles.headline1(color: titleColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  LocalizationHelper.expiredMessage,
                  style: AppTextStyles.bodyLarge(color: bodyColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceAlt
                        : AppColors.lightSurfaceAlt,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? AppColors.grey700.withValues(alpha: 0.3)
                          : AppColors.grey200.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Column(
                    children: [
                      ContactEmailRow(),
                      SizedBox(height: 12),
                      ContactWhatsAppRow(),
                      SizedBox(height: 12),
                      ContactWebsiteRow(),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ProfileScreen(
                            themeMode: widget.themeMode,
                            onThemeModeChange: widget.onThemeModeChange,
                            onBack: () => Navigator.pop(context),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_rounded, size: 20),
                    label: Text(LocalizationHelper.expiredViewProfile),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      side: BorderSide(color: accentColor),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _handleLogout,
                    icon: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isDark ? AppColors.black : AppColors.white,
                              ),
                            ),
                          )
                        : const Icon(Icons.logout_rounded, size: 20),
                    label: Text(_isLoading
                        ? LocalizationHelper.loading
                        : LocalizationHelper.expiredLogout),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor:
                          isDark ? AppColors.black : AppColors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
