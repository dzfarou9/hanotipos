// lib/screens/profile_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/database_service.dart';
import '../config/app_config.dart';
import '../helpers/subscription_helper.dart' as subscription;
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/design_tokens.dart';
import '../helpers/localization_helper.dart';
import '../helpers/password_strength.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/contact_row.dart';

class ProfileScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(ThemeMode) onThemeModeChange;
  final VoidCallback? onBack;

  const ProfileScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChange,
    this.onBack,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseService _firebase = FirebaseService();
  final AuthService _auth = AuthService.instance;
  final DatabaseService _db = DatabaseService.instance;

  bool _isLoading = true;
  Map<String, dynamic>? _subscriptionInfo;
  String? _userName;
  String? _userPhone;
  String? _storeName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      _userName = _auth.userName;
      _userPhone = _auth.userPhone;
      _storeName = _auth.storeName;

      // ⭐ عرض فوري من لقطة Hive قبل انتظار السيرفر، ثم استبدالها برد
      // السيرفر إن نجح. الفشل يُبقي اللقطة المحلية (لا نمسح بيانات صحيحة).
      final cached = _firebase.cachedSubscriptionInfo();
      if (cached != null) _subscriptionInfo = cached;

      AppConfig.log('Loading subscription info...');
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        final fresh = await _firebase.loadAndSaveSubscriptionInfo(userId);
        // ⭐ null من السيرفر يعني «لا اشتراك نشط» — حكم نهائي يمسح اللقطة.
        _subscriptionInfo = fresh;
      }
    } catch (e) {
      AppConfig.logError('Error loading profile data', e);
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  /// تسمية الخطة. النوع غير المعروف (لم يُقرأ من السيرفر بعد) يعرض تسمية
  /// عامة بدل اختراع «تجريبي».
  String _getPlanName(String? planType) {
    switch (planType) {
      case 'trial':
        return LocalizationHelper.profileTrial;
      case 'basic':
        return LocalizationHelper.profileBasic;
      case 'premium':
        return LocalizationHelper.profilePremium;
      case 'enterprise':
        return LocalizationHelper.profileEnterprise;
      default:
        // النوع غير معروف (لم يُقرأ من السيرفر بعد): تسمية عامة، لا اختراع.
        return (planType == null || planType.isEmpty)
            ? LocalizationHelper.profileActiveSubscription
            : planType;
    }
  }

  // ⭐ تحويل آمن لتاريخ الاشتراك (يقبل DateTime أو Timestamp أو String)
  DateTime? _parseStartDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    if (value is Timestamp) return value.toDate();
    return null;
  }

  Color _getPlanColor(String? planType) {
    switch (planType) {
      case 'trial':
        return AppColors.warning;
      case 'basic':
        return AppColors.info;
      case 'premium':
        return AppColors.success;
      case 'enterprise':
        return AppColors.secondary;
      default:
        return AppColors.primary;
    }
  }

  IconData _getPlanIcon(String? planType) {
    switch (planType) {
      case 'trial':
        return Icons.science_rounded;
      case 'basic':
        return Icons.star_border_rounded;
      case 'premium':
        return Icons.star_rounded;
      case 'enterprise':
        return Icons.business_center_rounded;
      default:
        return Icons.subscriptions_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    final titleColor =
        isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final bodyColor =
        isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;
    final cardColor =
        isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    final borderColor = isDark
        ? AppColors.grey700.withValues(alpha:0.3)
        : AppColors.grey200.withValues(alpha:0.5);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(LocalizationHelper.profileTitle,
            style: AppTextStyles.headline4(color: titleColor)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: widget.onBack ?? () => Navigator.pop(context),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(Icons.arrow_back_rounded, color: accentColor),
        ),
        actions: [
          IconButton(
            onPressed: _loadData,
            tooltip: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
            icon: Icon(Icons.refresh_rounded, color: accentColor),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: accentColor),
                  const SizedBox(height: 16),
                  Text(LocalizationHelper.loading,
                      style: AppTextStyles.bodyMedium(color: bodyColor)),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildUserCard(isDark, accentColor, titleColor, bodyColor,
                      cardColor, borderColor),
                  const SizedBox(height: 20),
                  _buildSubscriptionCard(isDark, accentColor, titleColor,
                      bodyColor, cardColor, borderColor),
                  const SizedBox(height: 20),
                  _buildOptionsCard(isDark, accentColor, titleColor, bodyColor,
                      cardColor, borderColor),
                ],
              ),
            ),
    );
  }

  Widget _buildUserCard(
    bool isDark,
    Color accentColor,
    Color titleColor,
    Color bodyColor,
    Color cardColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.person_rounded, color: accentColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userName ?? LocalizationHelper.profileUserInfo,
                      style: AppTextStyles.headline4(color: titleColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _storeName ?? LocalizationHelper.profileStore,
                      style: AppTextStyles.bodyMedium(color: accentColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: borderColor),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.phone_android_rounded, size: 18, color: bodyColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _userPhone ?? LocalizationHelper.profileStore,
                  style: AppTextStyles.bodyMedium(color: bodyColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.store_rounded, size: 18, color: bodyColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _storeName ?? LocalizationHelper.profileStore,
                  style: AppTextStyles.bodyMedium(color: bodyColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.email_rounded, size: 18, color: bodyColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_userPhone ?? ''}@hanoti.pos',
                  style: AppTextStyles.bodyMedium(color: bodyColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard(
    bool isDark,
    Color accentColor,
    Color titleColor,
    Color bodyColor,
    Color cardColor,
    Color borderColor,
  ) {
    // ⭐ حقول الاشتراك: رد السيرفر أولاً، ثم لقطة Hive الكاملة كاحتياط.
    // (كل مسارات القراءة تعيد الآن نفس المفاتيح، فلا تختفي التواريخ.)
    final info = _subscriptionInfo;
    final hiveEndDate = _db.getSubscriptionEndDate();
    final hiveIsActive = _db.getSubscriptionActive();

    final hasSubscription = info != null ||
        subscription.isSubscriptionValid(hiveEndDate, DateTime.now());
    final planType = info != null
        ? info['plan_type'] as String?
        : _db.getSubscriptionPlanType();
    final isActive =
        info != null ? (info['is_active'] as bool? ?? false) : hiveIsActive;
    final endDate =
        info != null ? (info['end_date'] as DateTime?) : hiveEndDate;
    final daysRemaining = info != null
        ? (info['days_remaining'] as int? ?? 0)
        : (hiveEndDate != null
            ? subscription.daysRemaining(hiveEndDate, DateTime.now())
            : 0);

    final planName = hasSubscription
        ? _getPlanName(planType)
        : LocalizationHelper.profileNoSubscription;
    final planColor =
        hasSubscription && isActive ? _getPlanColor(planType) : AppColors.error;
    final planIcon = hasSubscription && isActive
        ? _getPlanIcon(planType)
        : Icons.error_outline_rounded;
    final statusText = isActive
        ? LocalizationHelper.profileActive
        : LocalizationHelper.profileExpired;
    final statusColor = isActive ? AppColors.success : AppColors.error;
    final autoRenew = info != null
        ? (info['auto_renew'] as bool? ?? false)
        : _db.getSubscriptionAutoRenew();
    final startDate = info != null
        ? _parseStartDate(info['start_date'])
        : _db.getSubscriptionStartDate();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: planColor.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(planIcon, color: planColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LocalizationHelper.profileSubscription,
                      style: AppTextStyles.bodySmall(color: bodyColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      planName,
                      style: AppTextStyles.headline4(
                          color: isActive ? planColor : AppColors.error),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:
                      isActive ? AppColors.successLight : AppColors.errorLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusText,
                  style: AppTextStyles.caption(
                    color: statusColor,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: borderColor),
          const SizedBox(height: 12),
          if (isActive) ...[
            Row(
              children: [
                Icon(Icons.timer_rounded, size: 18, color: bodyColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    LocalizationHelper.profileDaysRemaining,
                    style: AppTextStyles.bodyMedium(color: bodyColor),
                  ),
                ),
                Text(
                  daysRemaining > 0
                      ? LocalizationHelper.days(daysRemaining)
                      : '0',
                  style: AppTextStyles.bodyLarge(
                    color: daysRemaining > 7
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (startDate != null) ...[
            Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 18, color: bodyColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    LocalizationHelper.profileStartDate,
                    style: AppTextStyles.bodyMedium(color: bodyColor),
                  ),
                ),
                Text(
                  '${startDate.day}/${startDate.month}/${startDate.year}',
                  style: AppTextStyles.bodyMedium(color: titleColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (endDate != null) ...[
            Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 18, color: bodyColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    LocalizationHelper.profileEndDate,
                    style: AppTextStyles.bodyMedium(color: bodyColor),
                  ),
                ),
                Text(
                  '${endDate.day}/${endDate.month}/${endDate.year}',
                  style: AppTextStyles.bodyMedium(
                    color: isActive ? titleColor : AppColors.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Icon(Icons.autorenew_rounded, size: 18, color: bodyColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  LocalizationHelper.profileAutoRenew,
                  style: AppTextStyles.bodyMedium(color: bodyColor),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: autoRenew
                      ? AppColors.successLight
                      : AppColors.grey200.withValues(alpha:0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  autoRenew
                      ? LocalizationHelper.profileEnabled
                      : LocalizationHelper.profileDisabled,
                  style: AppTextStyles.caption(
                    color: autoRenew ? AppColors.success : AppColors.grey500,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          if (!hasSubscription || !isActive) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                border: Border.all(color: AppColors.error.withValues(alpha:0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_rounded, color: AppColors.error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      LocalizationHelper.profileContactSupport,
                      style: AppTextStyles.bodySmall(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionsCard(
    bool isDark,
    Color accentColor,
    Color titleColor,
    Color bodyColor,
    Color cardColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
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
          Text(LocalizationHelper.profileOptions,
              style: AppTextStyles.bodyLarge(color: titleColor)),
          const SizedBox(height: 16),
          _buildOptionTile(
            icon: Icons.refresh_rounded,
            title: LocalizationHelper.profileRenew,
            subtitle: LocalizationHelper.profileRenewSubtitle,
            color: AppColors.success,
            titleColor: titleColor,
            bodyColor: bodyColor,
            onTap: () {
              _showRenewDialog(context, isDark, accentColor, titleColor);
            },
          ),
          const SizedBox(height: 12),
          Divider(color: borderColor),
          const SizedBox(height: 12),
          _buildOptionTile(
            icon: Icons.support_agent_rounded,
            title: LocalizationHelper.profileSupport,
            subtitle: LocalizationHelper.profileSupportSubtitle,
            color: AppColors.info,
            titleColor: titleColor,
            bodyColor: bodyColor,
            onTap: () {
              _showSupportDialog(context, isDark, accentColor, titleColor);
            },
          ),
          const SizedBox(height: 12),
          Divider(color: borderColor),
          const SizedBox(height: 12),
          // ⭐ H-3: تغيير كلمة المرور من داخل الملف الشخصي
          _buildOptionTile(
            icon: Icons.lock_reset_rounded,
            title: 'profile.change_password'.tr(),
            subtitle: 'profile.change_password_subtitle'.tr(),
            color: AppColors.warning,
            titleColor: titleColor,
            bodyColor: bodyColor,
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => const _ChangePasswordDialog(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color titleColor,
    required Color bodyColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.bodyMedium(color: titleColor)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.caption(color: bodyColor)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.grey400),
          ],
        ),
      ),
    );
  }

  void _showRenewDialog(
      BuildContext context, bool isDark, Color accentColor, Color titleColor) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        title: Text(LocalizationHelper.profileRenew,
            style: TextStyle(
                color: titleColor, fontSize: 18, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh_rounded, size: 50, color: accentColor),
            const SizedBox(height: 12),
            Text(
              LocalizationHelper.profileRenewSubtitle,
              style: TextStyle(
                  color: isDark
                      ? AppColors.textDarkSecondary
                      : AppColors.textLightSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha:0.05),
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              ),
              child: const Column(
                children: [
                  ContactEmailRow(),
                  SizedBox(height: 8),
                  ContactWhatsAppRow(),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(LocalizationHelper.profileClose,
                style: TextStyle(color: AppColors.grey500)),
          ),
        ],
      ),
    );
  }

  void _showSupportDialog(
      BuildContext context, bool isDark, Color accentColor, Color titleColor) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        title: Text(LocalizationHelper.profileSupport,
            style: TextStyle(
                color: titleColor, fontSize: 18, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.support_agent_rounded, size: 50, color: accentColor),
            const SizedBox(height: 12),
            Text(
              LocalizationHelper.profileSupportSubtitle,
              style: TextStyle(
                  color: isDark
                      ? AppColors.textDarkSecondary
                      : AppColors.textLightSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha:0.05),
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              ),
              child: const Column(
                children: [
                  ContactEmailRow(),
                  SizedBox(height: 8),
                  ContactWhatsAppRow(),
                  SizedBox(height: 8),
                  ContactWebsiteRow(),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(LocalizationHelper.profileClose,
                style: TextStyle(color: AppColors.grey500)),
          ),
        ],
      ),
    );
  }
}

/// ⭐ H-3: نافذة تغيير كلمة المرور
///
/// تحقق من كلمة المرور الحالية، وتتطلب قوة كلمة مرور جديدة >= 3
/// (8+ أحرف مع فئتين على الأقل) وتطابق التأكيد قبل الإرسال إلى
/// [AuthService.changePassword].
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;
  int _newStrength = 0;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final newPassword = _newController.text;
    final confirm = _confirmController.text;

    // ⭐ تحقق من تطابق كلمتي المرور
    if (newPassword != confirm) {
      AppSnackBar.error(context, LocalizationHelper.registerConfirmMatch);
      return;
    }

    // ⭐ سياسة كلمة المرور: قوة 3+ (8 أحرف على الأقل مع فئتين)
    if (calculatePasswordStrength(newPassword) < 3) {
      AppSnackBar.error(context, 'auth.password_too_weak'.tr());
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await AuthService.instance.changePassword(
        currentPassword: _currentController.text,
        newPassword: newPassword,
      );

      if (!mounted) return;
      Navigator.pop(context);
      AppSnackBar.success(context, 'auth.password_changed'.tr());
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      final raw = e.toString();
      final message = raw.startsWith('Exception: ')
          ? raw.substring(11)
          : 'auth.password_change_error'.tr();
      AppSnackBar.error(
          context, message == 'null' ? 'auth.password_change_error'.tr() : message);
    }
  }

  InputDecoration _inputDecoration(
    BuildContext context,
    String label,
    Color accentColor,
    bool isDark,
    bool obscure,
    VoidCallback onToggle,
  ) {
    return InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.lock_rounded, size: 22),
      suffixIcon: IconButton(
        onPressed: onToggle,
        icon: Icon(
          obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          size: 20,
          color: AppColors.grey400,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      filled: true,
      fillColor: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accentColor.withValues(alpha: 0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accentColor.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accentColor, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    final titleColor =
        isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            ),
            child: Icon(Icons.lock_reset_rounded, color: accentColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'profile.change_password'.tr(),
              style: TextStyle(
                  color: titleColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _currentController,
                obscureText: _obscureCurrent,
                decoration: _inputDecoration(
                  context,
                  'profile.current_password'.tr(),
                  accentColor,
                  isDark,
                  _obscureCurrent,
                  () =>
                      setState(() => _obscureCurrent = !_obscureCurrent),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return LocalizationHelper.loginPasswordRequired;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _newController,
                obscureText: _obscureNew,
                decoration: _inputDecoration(
                  context,
                  'profile.new_password'.tr(),
                  accentColor,
                  isDark,
                  _obscureNew,
                  () => setState(() => _obscureNew = !_obscureNew),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return LocalizationHelper.loginPasswordRequired;
                  }
                  if (v.length < 8) {
                    return LocalizationHelper.loginPasswordMin;
                  }
                  return null;
                },
                onChanged: (value) {
                  setState(() {
                    _newStrength = calculatePasswordStrength(value);
                  });
                },
              ),
              buildPasswordStrengthIndicator(_newController.text, _newStrength),
              TextFormField(
                controller: _confirmController,
                obscureText: _obscureConfirm,
                decoration: _inputDecoration(
                  context,
                  'profile.confirm_new_password'.tr(),
                  accentColor,
                  isDark,
                  _obscureConfirm,
                  () => setState(
                      () => _obscureConfirm = !_obscureConfirm),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return LocalizationHelper.registerConfirmRequired;
                  }
                  if (v != _newController.text) {
                    return LocalizationHelper.registerConfirmMatch;
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _isSubmitting ? null : () => Navigator.pop(context),
          child: Text(LocalizationHelper.cancel,
              style: const TextStyle(color: AppColors.grey500)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: isDark ? AppColors.black : AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            ),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(LocalizationHelper.save),
        ),
      ],
    );
  }
}
