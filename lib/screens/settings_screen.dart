// lib/screens/settings_screen.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/database_service.dart';
import '../services/qr_login_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_snackbar.dart';
import '../theme/design_tokens.dart';
import '../theme/screen_palette.dart';
import '../helpers/localization_helper.dart';
import '../helpers/login_rate_limiter.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(ThemeMode) onThemeModeChange;

  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChange,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedLanguage = 'en';
  ThemeMode _selectedThemeMode = ThemeMode.system;
  bool _isLoading = false;
  Map<String, dynamic>? _subscriptionInfo;
  String? _userName;
  String? _userPhone;
  String? _storeName;

  // ⭐ حد 3 محاولات خاطئة عند التحقق من كلمة المرور لتوليد QR
  final LoginRateLimiter _qrRateLimiter = LoginRateLimiter(maxAttempts: 3);

  @override
  void initState() {
    super.initState();
    _selectedThemeMode = widget.themeMode;
    _loadUserData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selectedLanguage = context.locale.languageCode;
  }

  Future<void> _loadUserData() async {
    try {
      final authService = AuthService.instance;
      _userName = authService.userName;
      _userPhone = authService.userPhone;
      _storeName = authService.storeName;

      // ⭐ لقطة Hive الكاملة للعرض الفوري (نفس مفاتيح رد السيرفر)
      _subscriptionInfo = FirebaseService().cachedSubscriptionInfo();
      if (mounted) setState(() {});
    } catch (e) {
      AppConfig.logError('Error loading user data', e);
    }

    final subscriptionInfo = await FirebaseService().getSubscriptionInfo();
    if (!mounted) return;
    // ⭐ لا تستبدل البيانات الصحيحة (من Hive) بقيمة null إذا فشل جلب الاشتراك
    setState(() {
      if (subscriptionInfo != null) {
        _subscriptionInfo = subscriptionInfo;
      }
    });
  }

  void _changeLanguage(BuildContext context, Locale locale) {
    context.setLocale(locale);
    setState(() {
      _selectedLanguage = locale.languageCode;
    });

    if (mounted) {
      AppSnackBar.show(
        context,
        LocalizationHelper.settingsLanguageChanged,
        type: AppSnackType.success,
        duration: const Duration(seconds: 2),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final accentColor = context.accent;
    final titleColor = context.titleColor;
    final bodyColor = context.bodyColor;
    final cardColor = context.surfaceAlt;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(LocalizationHelper.settingsTitle,
            style: AppTextStyles.headline4(color: titleColor)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(Icons.arrow_back_rounded, color: accentColor),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignTokens.space20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionCard(
              icon: Icons.person_rounded,
              title: LocalizationHelper.settingsProfile,
              iconColor: accentColor,
              isDark: isDark,
              accentColor: accentColor,
              cardColor: cardColor,
              child: _buildProfileContent(context, isDark, accentColor,
                  titleColor, bodyColor, cardColor),
            ),
            const SizedBox(height: DesignTokens.sectionGap),
            _buildSectionCard(
              icon: Icons.palette_rounded,
              title: LocalizationHelper.settingsAppearance,
              iconColor: accentColor,
              isDark: isDark,
              accentColor: accentColor,
              cardColor: cardColor,
              child: _buildAppearanceContent(context, isDark, accentColor,
                  titleColor, bodyColor),
            ),
            const SizedBox(height: DesignTokens.sectionGap),
            _buildSectionCard(
              icon: Icons.language_rounded,
              title: LocalizationHelper.settingsLanguage,
              iconColor: accentColor,
              isDark: isDark,
              accentColor: accentColor,
              cardColor: cardColor,
              child: _buildSettingTile(
                context,
                icon: Icons.language_rounded,
                title: _getCurrentLanguageLabel(),
                subtitle: LocalizationHelper.settingsSelectLanguage,
                isDark: isDark,
                accentColor: accentColor,
                titleColor: titleColor,
                bodyColor: bodyColor,
                onTap: () => _showLanguagePicker(
                    context, isDark, accentColor, titleColor),
              ),
            ),
            const SizedBox(height: DesignTokens.sectionGap),
            _buildSectionCard(
              icon: Icons.storefront_rounded,
              title: LocalizationHelper.settingsStoreInfo,
              iconColor: accentColor,
              isDark: isDark,
              accentColor: accentColor,
              cardColor: cardColor,
              child: _buildSettingTile(
                context,
                icon: Icons.storefront_rounded,
                title: _storeName ?? LocalizationHelper.defaultStoreName,
                subtitle: LocalizationHelper.settingsStoreInfoSubtitle,
                isDark: isDark,
                accentColor: accentColor,
                titleColor: titleColor,
                bodyColor: bodyColor,
                onTap: () => _showStoreInfoDialog(
                    context, isDark, accentColor, titleColor, bodyColor),
              ),
            ),
            const SizedBox(height: DesignTokens.sectionGap),
            _buildSectionCard(
              icon: Icons.qr_code_2_rounded,
              title: LocalizationHelper.qrLoginButton,
              iconColor: accentColor,
              isDark: isDark,
              accentColor: accentColor,
              cardColor: cardColor,
              child: _buildSettingTile(
                context,
                icon: Icons.qr_code_2_rounded,
                title: LocalizationHelper.qrLoginButtonSubtitle,
                subtitle: LocalizationHelper.qrLoginNote,
                isDark: isDark,
                accentColor: accentColor,
                titleColor: titleColor,
                bodyColor: bodyColor,
                onTap: () => _showLoginQrDialog(
                    context, isDark, accentColor, titleColor, bodyColor),
              ),
            ),
            const SizedBox(height: DesignTokens.sectionGap),
            _buildSectionCard(
              icon: Icons.warning_amber_rounded,
              title: LocalizationHelper.settingsDangerZone,
              iconColor: AppColors.error,
              borderColor: AppColors.error.withValues(alpha: 0.3),
              isDark: isDark,
              accentColor: accentColor,
              cardColor: cardColor,
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showLogoutDialog(
                      context, isDark, accentColor, titleColor, bodyColor),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: Text(LocalizationHelper.settingsLogout),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== PROFILE CONTENT ====================
  Widget _buildProfileContent(BuildContext context, bool isDark,
      Color accentColor, Color titleColor, Color bodyColor, Color cardColor) {
    final userName =
        _userName ?? AuthService.instance.userName ?? LocalizationHelper.defaultStoreAdmin;
    final userPhone = _userPhone ??
        AuthService.instance.userPhone ??
        LocalizationHelper.commonPhonePlaceholder;
    final storeName =
        _storeName ?? AuthService.instance.storeName ?? LocalizationHelper.defaultStoreName;

    final hasSubscription = _subscriptionInfo != null;
    final isActive = hasSubscription
        ? (_subscriptionInfo!['is_active'] as bool? ?? false)
        : false;
    final daysRemaining = hasSubscription
        ? (_subscriptionInfo!['days_remaining'] as int? ?? 0)
        : 0;
    final statusText = isActive
        ? LocalizationHelper.profileActive
        : LocalizationHelper.profileExpired;
    final statusColor = isActive ? AppColors.success : AppColors.error;

    return InkWell(
      onTap: () {
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
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: accentColor.withValues(alpha: 0.1),
                child:
                    Icon(Icons.person_rounded, size: 32, color: accentColor),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: cardColor, width: 2),
                  ),
                  child: Icon(
                    isActive ? Icons.check_rounded : Icons.close_rounded,
                    size: 10,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        userName,
                        style: AppTextStyles.bodyLarge(color: titleColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                        border:
                            Border.all(color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        statusText,
                        style: AppTextStyles.caption(
                          color: statusColor,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(storeName,
                    style: AppTextStyles.bodyMedium(color: accentColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.phone_android_rounded,
                        size: 14, color: bodyColor),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        userPhone,
                        style: AppTextStyles.bodySmall(color: bodyColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.timer_rounded, size: 14, color: bodyColor),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '$daysRemaining ${LocalizationHelper.profileDaysRemaining}',
                          style: AppTextStyles.bodySmall(color: bodyColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              color: isDark ? AppColors.grey500 : AppColors.grey400),
        ],
      ),
    );
  }

  // ==================== APPEARANCE CONTENT ====================
  Widget _buildAppearanceContent(BuildContext context, bool isDark,
      Color accentColor, Color titleColor, Color bodyColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildThemeOption(
          context,
          icon: Icons.light_mode_rounded,
          title: LocalizationHelper.settingsLightMode,
          subtitle: LocalizationHelper.settingsLightSubtitle,
          value: ThemeMode.light,
          isDark: isDark,
          accentColor: accentColor,
          titleColor: titleColor,
          bodyColor: bodyColor,
        ),
        const SizedBox(height: 12),
        _buildThemeOption(
          context,
          icon: Icons.dark_mode_rounded,
          title: LocalizationHelper.settingsDarkMode,
          subtitle: LocalizationHelper.settingsDarkSubtitle,
          value: ThemeMode.dark,
          isDark: isDark,
          accentColor: accentColor,
          titleColor: titleColor,
          bodyColor: bodyColor,
        ),
        const SizedBox(height: 12),
        _buildThemeOption(
          context,
          icon: Icons.settings_suggest_rounded,
          title: LocalizationHelper.settingsFollowSystem,
          subtitle: LocalizationHelper.settingsFollowSubtitle,
          value: ThemeMode.system,
          isDark: isDark,
          accentColor: accentColor,
          titleColor: titleColor,
          bodyColor: bodyColor,
        ),
      ],
    );
  }

  Widget _buildThemeOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required ThemeMode value,
    required bool isDark,
    required Color accentColor,
    required Color titleColor,
    required Color bodyColor,
  }) {
    final isSelected = _selectedThemeMode == value;
    return InkWell(
      onTap: () {
        setState(() => _selectedThemeMode = value);
        widget.onThemeModeChange(value);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? accentColor.withValues(alpha: 0.12)
                  : accentColor.withValues(alpha: 0.08))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected ? accentColor.withValues(alpha: 0.5) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? accentColor.withValues(alpha: 0.15)
                    : (isDark ? AppColors.darkSurfaceAlt : AppColors.grey100),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isSelected
                    ? accentColor
                    : (isDark ? AppColors.textDarkTertiary : AppColors.grey500),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppTextStyles.bodyMedium(
                          color: isSelected ? accentColor : titleColor)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: AppTextStyles.caption(color: bodyColor)),
                ],
              ),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(4),
                decoration:
                    BoxDecoration(color: accentColor, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded,
                    color: isDark ? AppColors.black : AppColors.white,
                    size: 16),
              ),
          ],
        ),
      ),
    );
  }

  // ==================== BUSINESS SETTINGS ====================
  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required Color iconColor,
    required bool isDark,
    required Color accentColor,
    required Color cardColor,
    required Widget child,
    Color? borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ??
              (isDark
                  ? accentColor.withValues(alpha: 0.15)
                  : AppColors.grey200.withValues(alpha: 0.5)),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? AppColors.shadowColorDark : AppColors.shadowColor,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.bodyLarge(color: iconColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  String _getCurrentLanguageLabel() {
    switch (_selectedLanguage) {
      case 'ar':
        return LocalizationHelper.settingsArabic;
      case 'fr':
        return LocalizationHelper.settingsFrench;
      default:
        return LocalizationHelper.settingsEnglish;
    }
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
    required Color accentColor,
    required Color titleColor,
    required Color bodyColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppTextStyles.bodyMedium(color: titleColor)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: AppTextStyles.caption(color: bodyColor)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: isDark ? AppColors.grey500 : AppColors.grey400,
                size: 20),
          ],
        ),
      ),
    );
  }

  // ==================== DIALOGS ====================

  void _showLanguagePicker(
      BuildContext context, bool isDark, Color accentColor, Color titleColor) {
    final currentLocale = context.locale;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        title: Text(
          LocalizationHelper.settingsSelectLanguage,
          style: TextStyle(
              color: titleColor, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile(
              title: Text(LocalizationHelper.settingsArabic,
                  style: TextStyle(color: titleColor)),
              value: 'ar',
              groupValue: currentLocale.languageCode,
              activeColor: accentColor,
              onChanged: (value) {
                _changeLanguage(context, const Locale('ar', 'SA'));
                Navigator.pop(ctx);
              },
            ),
            RadioListTile(
              title: Text(LocalizationHelper.settingsFrench,
                  style: TextStyle(color: titleColor)),
              value: 'fr',
              groupValue: currentLocale.languageCode,
              activeColor: accentColor,
              onChanged: (value) {
                _changeLanguage(context, const Locale('fr', 'FR'));
                Navigator.pop(ctx);
              },
            ),
            RadioListTile(
              title: Text(LocalizationHelper.settingsEnglish,
                  style: TextStyle(color: titleColor)),
              value: 'en',
              groupValue: currentLocale.languageCode,
              activeColor: accentColor,
              onChanged: (value) {
                _changeLanguage(context, const Locale('en', 'US'));
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showStoreInfoDialog(BuildContext context, bool isDark,
      Color accentColor, Color titleColor, Color bodyColor) async {
    final nameController = TextEditingController(
        text: _storeName ?? AuthService.instance.storeName ?? '');
    final phoneController =
        TextEditingController(text: AuthService.instance.storePhone ?? '');
    final addressController =
        TextEditingController(text: AuthService.instance.storeAddress ?? '');
    final taxIdController =
        TextEditingController(text: AuthService.instance.storeTaxId ?? '');
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        title: Text(LocalizationHelper.settingsStoreInfo,
            style: TextStyle(
                color: titleColor, fontSize: 18, fontWeight: FontWeight.w600)),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStoreField(
                  controller: nameController,
                  label: LocalizationHelper.settingsStoreName,
                  hint: LocalizationHelper.defaultStoreName,
                  isDark: isDark,
                  bodyColor: bodyColor,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return LocalizationHelper.registerStoreTooShort;
                    }
                    return null;
                  },
                ),
                _buildStoreField(
                  controller: phoneController,
                  label: LocalizationHelper.settingsStorePhone,
                  hint: LocalizationHelper.settingsStorePhoneHint,
                  isDark: isDark,
                  bodyColor: bodyColor,
                ),
                _buildStoreField(
                  controller: addressController,
                  label: LocalizationHelper.settingsStoreAddress,
                  hint: LocalizationHelper.settingsStoreAddressHint,
                  isDark: isDark,
                  bodyColor: bodyColor,
                ),
                _buildStoreField(
                  controller: taxIdController,
                  label: LocalizationHelper.settingsTaxId,
                  hint: LocalizationHelper.settingsTaxIdHint,
                  isDark: isDark,
                  bodyColor: bodyColor,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(LocalizationHelper.cancel,
                style: const TextStyle(color: AppColors.grey500)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final messenger = ScaffoldMessenger.of(context);
              try {
                await DatabaseService.instance.saveStoreInfo(
                  storeName: nameController.text.trim(),
                  phone: phoneController.text.trim(),
                  address: addressController.text.trim(),
                  taxId: taxIdController.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                messenger.showSnackBar(
                  SnackBar(
                    content:
                        Text(LocalizationHelper.settingsStoreInfoSaved),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              } catch (e) {
                debugPrint('Save store info error: $e');
                messenger.showSnackBar(
                  SnackBar(
                    content:
                        Text(LocalizationHelper.settingsStoreInfoError),
                    backgroundColor: AppColors.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(LocalizationHelper.save),
          ),
        ],
      ),
    );
    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    taxIdController.dispose();
  }

  // ==================== نافذة تسجيل الدخول عبر QR ====================

  Future<void> _showLoginQrDialog(BuildContext context, bool isDark,
      Color accentColor, Color titleColor, Color bodyColor) async {
    final phone = AuthService.instance.userPhone ?? '';
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final qrBoundaryKey = GlobalKey();
    String? qrData;
    String? qrError;
    var isVerifying = false;
    var isRegenerating = false;
    // ⭐ الرمز دائم (بلا انتهاء) — الإلغاء يتم بإعادة توليد الملح.

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> generateQr() async {
            // ⭐ يعرض فشل التحقق ويحتسب المحاولة (إلا لأخطاء الشبكة)
            void showFailure(String message, {bool isNetwork = false}) {
              if (!isNetwork) {
                _qrRateLimiter.recordFailure();
              }
              final remaining = _qrRateLimiter.attemptsRemaining;
              setDialogState(() {
                isVerifying = false;
                if (_qrRateLimiter.isLocked) {
                  qrError = LocalizationHelper.loginBlocked;
                } else if (!isNetwork && remaining > 0 && remaining < 3) {
                  qrError = '$message '
                      '($remaining ${LocalizationHelper.loginAttemptsRemaining})';
                } else {
                  qrError = message;
                }
              });
            }

            if (isVerifying) return;

            // ⭐ منع المحاولات بعد تجاوز الحد المسموح
            if (_qrRateLimiter.isLocked) {
              final remaining = _qrRateLimiter.remainingLock;
              final minutes = remaining != null
                  ? (remaining.inSeconds / 60).ceil()
                  : 5;
              setDialogState(() {
                qrError = LocalizationHelper.loginBlockedMinutes(minutes);
              });
              return;
            }

            if (!formKey.currentState!.validate()) return;
            setDialogState(() {
              isVerifying = true;
              qrError = null;
            });
            try {
              final valid = await AuthService.instance.verifyCredentials(
                phone: phone,
                password: passwordController.text,
              );
              if (!ctx.mounted) return;
              if (!valid) {
                showFailure(LocalizationHelper.authLoginError);
                return;
              }
              // ⭐ ملح لكل حساب: يُولَّد مرة واحدة عند أول توليد لرمز QR
              // ويُخزَّن في Hive (يُمسح عند تسجيل الخروج)، ودخله في
              // اشتقاق مفتاح AES يجعل كل رمز مختلفاً بين الحسابات.
              final db = DatabaseService.instance;
              var salt = db.getQrSalt();
              if (salt == null) {
                salt = QrLoginService.generateSalt();
                await db.saveQrSalt(salt);
              }
              final data = QrLoginService.encryptCredentials(
                phone: phone,
                password: passwordController.text,
                salt: salt,
              );
              setDialogState(() {
                isVerifying = false;
                qrData = data;
              });
            } catch (e) {
              if (!ctx.mounted) return;
              var message = e.toString();
              if (message.startsWith('Exception: ')) {
                message = message.substring(11);
              }
              if (message == 'null') {
                message = LocalizationHelper.authLoginError;
              }

              // ⭐ أخطاء الشبكة/عدم توفر Firebase لا تُحتسب كمحاولة
              final isNetwork =
                  message.contains(LocalizationHelper.authNetworkFailed) ||
                      message.contains(LocalizationHelper.authFirebaseUnavailable);
              showFailure(message, isNetwork: isNetwork);
            }
          }

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor:
                isDark ? AppColors.darkSurface : AppColors.lightSurface,
            title: Text(
              LocalizationHelper.qrLoginDialogTitle,
              style: TextStyle(
                  color: titleColor, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            content: qrData == null
                ? SingleChildScrollView(
                    child: Form(
                      key: formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TextFormField(
                              initialValue: phone,
                              readOnly: true,
                              style: TextStyle(color: bodyColor),
                              decoration: InputDecoration(
                                labelText:
                                    LocalizationHelper.loginPhoneLabel,
                                labelStyle: TextStyle(color: bodyColor),
                                filled: true,
                                fillColor: isDark
                                    ? AppColors.darkSurfaceAlt
                                    : AppColors.lightSurfaceAlt,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                                  borderSide: BorderSide(
                                      color: isDark
                                          ? AppColors.grey700
                                          : AppColors.grey300),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TextFormField(
                              controller: passwordController,
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => generateQr(),
                              style: TextStyle(color: bodyColor),
                              decoration: InputDecoration(
                                labelText:
                                    LocalizationHelper.loginPasswordLabel,
                                labelStyle: TextStyle(color: bodyColor),
                                filled: true,
                                fillColor: isDark
                                    ? AppColors.darkSurfaceAlt
                                    : AppColors.lightSurfaceAlt,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                                  borderSide: BorderSide(
                                      color: isDark
                                          ? AppColors.grey700
                                          : AppColors.grey300),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return LocalizationHelper
                                      .loginPasswordRequired;
                                }
                                if (value.length < 6) {
                                  return LocalizationHelper.loginPasswordMin;
                                }
                                return null;
                              },
                            ),
                          ),
                          Text(
                            LocalizationHelper.qrLoginNote,
                            style: AppTextStyles.caption(
                                color: isDark
                                    ? AppColors.textDarkTertiary
                                    : AppColors.textLightTertiary),
                          ),
                          if (qrError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                qrError!,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodySmall(
                                    color: AppColors.error),
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RepaintBoundary(
                        key: qrBoundaryKey,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.grey300.withValues(alpha: 0.6)),
                          ),
                          child: QrImageView(
                            data: qrData!,
                            version: QrVersions.auto,
                            size: 200,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        phone,
                        style: AppTextStyles.bodyMedium(color: accentColor),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        LocalizationHelper.qrLoginNote,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption(color: bodyColor),
                      ),
                      // ⭐ تحذير أمان: الرمز يحمل بيانات دخول فعلية
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 14, color: AppColors.error),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              LocalizationHelper.qrLoginSecurityWarning,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.caption(
                                  color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        LocalizationHelper.qrLoginPermanentNote,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption(
                            color: isDark
                                ? AppColors.textDarkTertiary
                                : AppColors.textLightTertiary),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _downloadQr(
                              context, qrBoundaryKey, phone),
                          icon: Icon(
                            Icons.download_rounded,
                            size: 18,
                            color: accentColor,
                          ),
                          label: Text(
                            LocalizationHelper.qrLoginDownload,
                            style: AppTextStyles.buttonText(
                                color: accentColor, fontSize: 14),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: accentColor.withValues(alpha: 0.5)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: isRegenerating
                              ? null
                              : () async {
                                  final confirmed =
                                      await _confirmRegenerateQr(ctx);
                                  if (confirmed != true) return;
                                  setDialogState(
                                      () => isRegenerating = true);
                                  try {
                                    final db = DatabaseService.instance;
                                    final newSalt =
                                        QrLoginService.generateSalt();
                                    await db.saveQrSalt(newSalt);
                                    final data =
                                        QrLoginService.encryptCredentials(
                                      phone: phone,
                                      password: passwordController.text,
                                      salt: newSalt,
                                    );
                                    setDialogState(() {
                                      qrData = data;
                                      isRegenerating = false;
                                    });
                                  } catch (e) {
                                    AppConfig.logError(
                                        'QR regenerate error', e);
                                    setDialogState(
                                        () => isRegenerating = false);
                                  }
                                },
                          icon: isRegenerating
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                            AppColors.white),
                                  ),
                                )
                              : Icon(
                                  Icons.refresh_rounded,
                                  size: 18,
                                  color: AppColors.error,
                                ),
                          label: Text(
                            LocalizationHelper.qrLoginRegenerate,
                            style: AppTextStyles.buttonText(
                                color: AppColors.error, fontSize: 14),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: AppColors.error.withValues(alpha: 0.5)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
            actions: qrData == null
                ? [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(LocalizationHelper.cancel,
                          style: const TextStyle(color: AppColors.grey500)),
                    ),
                    ElevatedButton(
                      onPressed: isVerifying ? null : generateQr,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: AppColors.white,
                        disabledBackgroundColor:
                            accentColor.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isVerifying
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    AppColors.white),
                              ),
                            )
                          : Text(LocalizationHelper.qrLoginGenerate),
                    ),
                  ]
                : [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(LocalizationHelper.done,
                          style: const TextStyle(color: AppColors.grey500)),
                    ),
                  ],
          );
        },
      ),
    );

    // ⭐ إيقاف التجديد التلقائي فور إغلاق النافذة
    passwordController.clear();
    passwordController.dispose();
  }

  // ⭐ تأكيد إعادة توليد الرمز الدائم — يعيد true عند الموافقة فقط
  Future<bool?> _confirmRegenerateQr(BuildContext dialogContext) {
    return showDialog<bool>(
      context: dialogContext,
      builder: (confirmCtx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          LocalizationHelper.qrLoginRegenerateTitle,
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Text(LocalizationHelper.qrLoginRegenerateBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmCtx, false),
            child: Text(LocalizationHelper.cancel,
                style: const TextStyle(color: AppColors.grey500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(confirmCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(LocalizationHelper.confirm),
          ),
        ],
      ),
    );
  }

  // ⭐ تنزيل رمز QR كصورة PNG
  Future<void> _downloadQr(
      BuildContext context, GlobalKey boundaryKey, String phone) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // ⭐ انتظار نهاية الإطار لضمان رسم الـ QR قبل الالتقاط
      await WidgetsBinding.instance.endOfFrame;

      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception(LocalizationHelper.qrLoginNotRendered);
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      if (byteData == null) {
        throw Exception(LocalizationHelper.qrLoginEncodeFailed);
      }

      final bytes = byteData.buffer.asUint8List();
      final fileName =
          'qr_login_${phone.replaceAll(RegExp(r'[^0-9]'), '')}.png';

      bool saved = false;
      if (!kIsWeb && !Platform.isIOS) {
        try {
          final savedPath = await FlutterFileDialog.saveFile(
            params: SaveFileDialogParams(
              data: bytes,
              fileName: fileName,
              mimeTypesFilter: const ['image/png'],
            ),
          );
          saved = savedPath != null;
        } on MissingPluginException {
          saved = false;
        }
      }

      if (!saved) {
        await _shareQrImage(bytes, fileName);
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(LocalizationHelper.qrLoginDownloaded),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      AppConfig.logError('QR download error', e);
      messenger.showSnackBar(
        SnackBar(
          content: Text(LocalizationHelper.qrLoginDownloadError),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _shareQrImage(Uint8List bytes, String fileName) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)]);
  }

  Widget _buildStoreField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool isDark,
    required Color bodyColor,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        validator: validator,
        style: TextStyle(color: bodyColor),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: bodyColor),
          filled: true,
          fillColor: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            borderSide: BorderSide(
                color: isDark ? AppColors.grey700 : AppColors.grey300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            borderSide: BorderSide(
                color: isDark ? AppColors.grey700 : AppColors.grey300),
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, bool isDark, Color accentColor,
      Color titleColor, Color bodyColor) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        title: Text(LocalizationHelper.settingsLogout,
            style: TextStyle(
                color: titleColor, fontSize: 18, fontWeight: FontWeight.w600)),
        content: Text(LocalizationHelper.settingsLogoutConfirm,
            style: TextStyle(color: bodyColor)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(LocalizationHelper.cancel,
                  style: TextStyle(color: AppColors.grey500))),
          ElevatedButton(
            onPressed: () async {
              setState(() => _isLoading = true);
              try {
                await AuthService.instance.logout();
              } catch (e) {
                AppConfig.logError('Logout error', e);
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (context) => LoginScreen(
                            themeMode: widget.themeMode,
                            onThemeModeChange: widget.onThemeModeChange,
                          )),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.white),
                    ),
                  )
                : Text(LocalizationHelper.settingsLogout),
          ),
        ],
      ),
    );
  }
}
