// lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/screen_palette.dart';
import '../helpers/localization_helper.dart';
import '../helpers/platform_helper.dart';
import '../widgets/app_snackbar.dart';
import '../theme/design_tokens.dart';
import '../helpers/login_rate_limiter.dart';
import '../widgets/language_switcher.dart';
import 'register_screen.dart';
import 'login_qr_scan_screen.dart';
import 'main_screen.dart';
import 'subscription_expired_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_screen.dart';

class LoginScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(ThemeMode) onThemeModeChange;

  const LoginScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChange,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;
  String _errorMessage = '';
  bool _isFormValid = false;

  final LoginRateLimiter _rateLimiter = LoginRateLimiter();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _formKey.currentState?.reset();
      _phoneFocusNode.requestFocus();
    });

    _animationController.forward();
  }

  void _computeFormValid() {
    final phoneValid = _phoneController.text.trim().length >= 9;
    final passwordValid = _passwordController.text.length >= 6;
    final isValid = phoneValid && passwordValid;
    if (mounted &&
        (_isFormValid != isValid || _errorMessage.isNotEmpty)) {
      setState(() {
        _isFormValid = isValid;
        _errorMessage = '';
      });
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _phoneFocusNode.dispose();
    _passwordFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _startPasswordHideTimer() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _obscurePassword == false) {
        setState(() => _obscurePassword = true);
      }
    });
  }

  Future<void> _handleLogin() async {
    if (_rateLimiter.isLocked) {
      final remaining = _rateLimiter.remainingLock;
      final minutes = remaining != null
          ? (remaining.inSeconds / 60).ceil()
          : 5;
      _showSnackBar(
        LocalizationHelper.loginBlockedMinutes(minutes),
        AppColors.error,
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    HapticFeedback.mediumImpact();

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final authService = AuthService.instance;
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;

    bool success;
    try {
      success = await authService.login(
        phone: phone,
        password: password,
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().startsWith('Exception: ')
          ? e.toString().substring(11)
          : e.toString();

      // أخطاء الشبكة ليست محاولة خاطئة، لا تُحتسب في القفل
      if (!message.contains(LocalizationHelper.authNetworkFailed)) {
        _rateLimiter.recordFailure();
      }

      setState(() {
        _isLoading = false;
        _errorMessage = message == 'null' ? LocalizationHelper.loginError : message;
      });
      return;
    }

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      HapticFeedback.lightImpact();

      final isActive = await FirebaseService().isSubscriptionActive();

      if (!mounted) return;

      if (isActive) {
        _navigateToMain();
      } else {
        _navigateToSubscriptionExpired();
      }
    } else {
      HapticFeedback.heavyImpact();

      _rateLimiter.recordFailure();
      if (_rateLimiter.isLocked) {
        setState(() {
          _errorMessage = LocalizationHelper.loginBlocked;
        });
      } else {
        setState(() {
          _errorMessage =
              '${LocalizationHelper.loginError} (${_rateLimiter.attemptsRemaining} ${'login.attempts_remaining'.tr()})';
        });
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    AppSnackBar.show(context, message, type: _snackTypeFor(color));
  }

  AppSnackType _snackTypeFor(Color color) {
    if (color == AppColors.success) return AppSnackType.success;
    if (color == AppColors.error) return AppSnackType.error;
    if (color == AppColors.warning) return AppSnackType.warning;
    return AppSnackType.info;
  }

  void _navigateToMain() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => MainScreen(
          themeMode: widget.themeMode,
          onThemeToggle: () {},
          onThemeModeChange: widget.onThemeModeChange,
        ),
      ),
      (route) => false,
    );
  }

  void _navigateToSubscriptionExpired() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => SubscriptionExpiredScreen(
          themeMode: widget.themeMode,
          onThemeModeChange: widget.onThemeModeChange,
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final accentColor = context.accent;
    final bgColor = context.scaffoldColor;
    final errorColor = context.errorColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          AppColors.darkBackground,
                          AppColors.darkSurfaceAlt,
                          Colors.black,
                        ]
                      : [
                          AppColors.lightBackground,
                          AppColors.primaryVeryLight,
                          Colors.white,
                        ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
              child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              // ⭐ درجات غامقة حول الأيقونة البيضاء: التدرج
                              // الافتراضي يبدأ فاتحاً فيغسل الزاوية ويضعف التباين
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.neonOrange,
                                  AppColors.primary
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: accentColor.withValues(alpha:0.3),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.store_rounded,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Center(
                          child: Text(
                            LocalizationHelper.loginTitle,
                            style: AppTextStyles.headline3(
                              color: isDark
                                  ? AppColors.textDarkPrimary
                                  : AppColors.textLightPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            LocalizationHelper.loginSubtitle,
                            style: AppTextStyles.bodyMedium(
                              color: isDark
                                  ? AppColors.textDarkSecondary
                                  : AppColors.textLightSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_errorMessage.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: errorColor.withValues(alpha:0.1),
                              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                              border: Border.all(
                                color: errorColor.withValues(alpha:0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline_rounded,
                                    color: errorColor, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage,
                                    style: AppTextStyles.bodyMedium(
                                        color: errorColor),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        TextFormField(
                          controller: _phoneController,
                          focusNode: _phoneFocusNode,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              _passwordFocusNode.requestFocus(),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: InputDecoration(
                            labelText: LocalizationHelper.loginPhoneLabel,
                            hintText: LocalizationHelper.loginPhoneHint,
                            prefixIcon: const Icon(
                              Icons.phone_android_rounded,
                              size: 22,
                            ),
                            prefixText: '+213 ',
                            prefixStyle:
                                AppTextStyles.bodyMedium(color: accentColor),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            filled: true,
                            fillColor: isDark
                                ? AppColors.darkSurfaceAlt
                                : AppColors.lightSurface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: accentColor.withValues(alpha:0.3),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: accentColor.withValues(alpha:0.2),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: accentColor,
                                width: 2,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return LocalizationHelper.loginPhoneRequired;
                            }
                            if (v.trim().length < 9) {
                              return LocalizationHelper.loginPhoneValid;
                            }
                            return null;
                          },
                          onChanged: (_) => _computeFormValid(),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (_isFormValid) {
                              _handleLogin();
                            } else {
                              _passwordFocusNode.unfocus();
                            }
                          },
                          decoration: InputDecoration(
                            labelText: LocalizationHelper.loginPasswordLabel,
                            hintText: LocalizationHelper.loginPasswordHint,
                            prefixIcon:
                                const Icon(Icons.lock_rounded, size: 22),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                  if (!_obscurePassword) {
                                    _startPasswordHideTimer();
                                  }
                                });
                              },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                size: 20,
                                color: AppColors.grey400,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            filled: true,
                            fillColor: isDark
                                ? AppColors.darkSurfaceAlt
                                : AppColors.lightSurface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: accentColor.withValues(alpha:0.3),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: accentColor.withValues(alpha:0.2),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: accentColor,
                                width: 2,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return LocalizationHelper.loginPasswordRequired;
                            }
                            if (v.length < 6) {
                              return LocalizationHelper.loginPasswordMin;
                            }
                            return null;
                          },
                          onChanged: (value) {
                            _computeFormValid();
                          },
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(
                                      () => _rememberMe = !_rememberMe),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: Checkbox(
                                          value: _rememberMe,
                                          onChanged: (v) => setState(() =>
                                              _rememberMe = v ?? !_rememberMe),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          activeColor: accentColor,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        LocalizationHelper.loginRememberMe,
                                        style: AppTextStyles.bodySmall(
                                          color: isDark
                                              ? AppColors.textDarkSecondary
                                              : AppColors.textLightSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            TextButton(
                              onPressed: () {},
                              child: Text(
                                LocalizationHelper.loginForgotPassword,
                                style: AppTextStyles.caption(
                                  color: accentColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed:
                                (_isLoading || !_isFormValid) ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentColor,
                              foregroundColor:
                                  isDark ? AppColors.black : AppColors.white,
                              elevation: 4,
                              shadowColor:
                                  accentColor.withValues(alpha:0.3),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                              ),
                              disabledBackgroundColor: isDark
                                  ? AppColors.grey700.withValues(alpha:0.5)
                                  : AppColors.grey300,
                            ),
                            child: _isLoading
                                ? SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        isDark
                                            ? AppColors.black
                                            : AppColors.white,
                                      ),
                                    ),
                                  )
                                : Text(
                                    LocalizationHelper.loginSignIn,
                                    style: AppTextStyles.buttonText(
                                      color: isDark
                                          ? AppColors.black
                                          : AppColors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 54,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              if (PlatformHelper.isWindows) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                        'QR login is not available on Windows — use phone and password'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                return;
                              }
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => LoginQrScanScreen(
                                    themeMode: widget.themeMode,
                                    onThemeModeChange:
                                        widget.onThemeModeChange,
                                  ),
                                ),
                              );
                            },
                            icon: Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 22,
                              color: accentColor,
                            ),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                LocalizationHelper.qrLoginButton,
                                style: AppTextStyles.buttonText(
                                  color: accentColor,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: accentColor.withValues(alpha: 0.5),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              LocalizationHelper.loginNoAccount,
                              style: AppTextStyles.bodySmall(
                                color: isDark
                                    ? AppColors.textDarkTertiary
                                    : AppColors.textLightTertiary,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => RegisterScreen(
                                      themeMode: widget.themeMode,
                                      onThemeModeChange:
                                          widget.onThemeModeChange,
                                    ),
                                  ),
                                );
                              },
                              child: Text(
                                LocalizationHelper.loginRegisterNow,
                                style: AppTextStyles.bodyMedium(
                                  color: accentColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: AppTextStyles.bodySmall(
                                color: isDark
                                    ? AppColors.textDarkTertiary
                                    : AppColors.textLightTertiary,
                              ),
                              children: [
                                TextSpan(
                                  text:
                                      '${LocalizationHelper.loginAgreePrefix} ',
                                ),
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const PrivacyPolicyScreen(),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 2),
                                      child: Text(
                                        LocalizationHelper.loginAgreePrivacy,
                                        style: TextStyle(
                                          color: accentColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                TextSpan(
                                  text:
                                      ' ${LocalizationHelper.loginAgreeAnd} ',
                                ),
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const TermsScreen(),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 2),
                                      child: Text(
                                        LocalizationHelper.loginAgreeTerms,
                                        style: TextStyle(
                                          color: accentColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const Positioned(
          top: DesignTokens.space8,
          right: DesignTokens.space16,
          child: LanguageSwitcher(),
        ),
      ],
    ),
  ),
  );
  }
}
