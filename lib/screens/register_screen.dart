// lib/screens/register_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../config/app_config.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_snackbar.dart';
import '../theme/design_tokens.dart';
import '../helpers/localization_helper.dart';
import '../helpers/password_strength.dart';
import '../widgets/language_switcher.dart';
import 'main_screen.dart';
import 'subscription_expired_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_screen.dart';

class RegisterScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(ThemeMode) onThemeModeChange;

  const RegisterScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChange,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _fullNameController = TextEditingController();
  final _storeNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreeToTerms = false;
  bool _isLoading = false;
  String _errorMessage = '';
  bool _isFormValid = false;
  int _passwordStrength = 0;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final FocusNode _fullNameFocusNode = FocusNode();
  final FocusNode _storeNameFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();

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
      _fullNameFocusNode.requestFocus();
    });

    _animationController.forward();
  }

  void _computeFormValid() {
    final nameValid = _fullNameController.text.trim().length >= 3;
    final storeValid = _storeNameController.text.trim().length >= 2;
    final phoneValid = _phoneController.text.trim().length >= 9;
    final passwordValid = _passwordController.text.length >= 8;
    final confirmValid = _confirmPasswordController.text.isNotEmpty &&
        _confirmPasswordController.text == _passwordController.text;
    final isValid = nameValid &&
        storeValid &&
        phoneValid &&
        passwordValid &&
        confirmValid &&
        _agreeToTerms;
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
    _fullNameController.dispose();
    _storeNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameFocusNode.dispose();
    _storeNameFocusNode.dispose();
    _phoneFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
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

  void _startConfirmPasswordHideTimer() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _obscureConfirmPassword == false) {
        setState(() => _obscureConfirmPassword = true);
      }
    });
  }

  void _updatePasswordStrength(String password) {
    setState(() {
      _passwordStrength = calculatePasswordStrength(password);
    });
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (calculatePasswordStrength(_passwordController.text) < 3) {
      AppSnackBar.show(
        context,
        LocalizationHelper.authWeakPassword,
        type: AppSnackType.error,
        duration: const Duration(seconds: 3),
      );
      return;
    }

    if (!_agreeToTerms) {
      setState(() => _errorMessage = LocalizationHelper.registerErrorTerms);
      return;
    }

    // ⭐ H-4: تطبيع رقم الهاتف والتحقق منه قبل التسجيل (توحيد الصيغة المخزنة)
    final normalizedPhone =
        FirebaseService.normalizePhone(_phoneController.text.trim());
    if (normalizedPhone == null) {
      setState(() => _errorMessage = LocalizationHelper.registerPhoneValid);
      return;
    }

    HapticFeedback.mediumImpact();

    setState(() => _isLoading = true);

    try {
      final authService = AuthService.instance;
      final phone = _phoneController.text.trim();
      final fullName = _fullNameController.text.trim();
      final storeName = _storeNameController.text.trim();
      final password = _passwordController.text;

      final success = await authService.register(
        phone: phone,
        fullName: fullName,
        storeName: storeName,
        password: password,
      );

      if (!mounted) return;

      if (success) {
        HapticFeedback.lightImpact();

        if (mounted) {
          AppSnackBar.show(
            context,
            LocalizationHelper.registerSuccess,
            type: AppSnackType.success,
            duration: const Duration(seconds: 3),
          );
        }

        bool isActive = true;
        try {
          isActive = await FirebaseService().isSubscriptionActive();
        } catch (e) {
          AppConfig.logError('Subscription check exception', e);
          isActive = true;
        }

        if (!mounted) return;

        if (isActive) {
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
        } else {
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
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _isLoading = false;
          _errorMessage = LocalizationHelper.registerError;
        });
      }
    } catch (e) {
      // ⭐ لا نسجّل تفاصيل الاستثناء فقد تحتوي على رقم الهاتف/البريد
      AppConfig.logError('Registration exception: ${e.runtimeType}');
      if (mounted) {
        final raw = e.toString();
        final message = raw.startsWith('Exception: ')
            ? raw.substring(11)
            : LocalizationHelper.registerError;
        setState(() {
          _isLoading = false;
          _errorMessage = message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    final bgColor =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final errorColor = AppColors.error;

    return Scaffold(
      backgroundColor: bgColor,
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
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: LanguageSwitcher()),
          ),
        ],
      ),
      body: Container(
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
        child: SafeArea(
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
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              // ⭐ درجات غامقة حول الأيقونة البيضاء (نمط الشعار الموحد)
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.neonOrange,
                                  AppColors.primary
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
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
                                size: 32,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Center(
                          child: Text(
                            LocalizationHelper.registerTitle,
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
                            LocalizationHelper.registerSubtitle,
                            style: AppTextStyles.bodyMedium(
                              color: isDark
                                  ? AppColors.textDarkSecondary
                                  : AppColors.textLightSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 36),
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
                          controller: _fullNameController,
                          focusNode: _fullNameFocusNode,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              _storeNameFocusNode.requestFocus(),
                          decoration: InputDecoration(
                            labelText: LocalizationHelper.registerFullNameLabel,
                            hintText: LocalizationHelper.registerFullNameHint,
                            prefixIcon:
                                const Icon(Icons.person_rounded, size: 22),
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
                              return LocalizationHelper.registerNameRequired;
                            }
                            if (v.trim().length < 3) {
                              return LocalizationHelper.registerNameTooShort;
                            }
                            return null;
                          },
                          onChanged: (_) => _computeFormValid(),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _storeNameController,
                          focusNode: _storeNameFocusNode,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              _phoneFocusNode.requestFocus(),
                          decoration: InputDecoration(
                            labelText:
                                LocalizationHelper.registerStoreNameLabel,
                            hintText: LocalizationHelper.registerStoreNameHint,
                            prefixIcon:
                                const Icon(Icons.store_rounded, size: 22),
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
                              return LocalizationHelper.registerStoreRequired;
                            }
                            if (v.trim().length < 2) {
                              return LocalizationHelper.registerStoreTooShort;
                            }
                            return null;
                          },
                          onChanged: (_) => _computeFormValid(),
                        ),
                        const SizedBox(height: 16),
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
                            labelText: LocalizationHelper.registerPhoneLabel,
                            hintText: LocalizationHelper.registerPhoneHint,
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
                              return LocalizationHelper.registerPhoneRequired;
                            }
                            if (v.trim().length < 9) {
                              return LocalizationHelper.registerPhoneValid;
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
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              _confirmPasswordFocusNode.requestFocus(),
                          decoration: InputDecoration(
                            labelText: LocalizationHelper.registerPasswordLabel,
                            hintText: LocalizationHelper.registerPasswordHint,
                            prefixIcon:
                                const Icon(Icons.lock_rounded, size: 22),
                            prefixIconConstraints:
                                const BoxConstraints(minWidth: 36, minHeight: 36),
                            suffixIcon: SizedBox(
                              width: 44,
                              height: 44,
                              child: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                    if (!_obscurePassword) {
                                      _startPasswordHideTimer();
                                    }
                                  });
                                },
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  size: 20,
                                  color: AppColors.grey400,
                                ),
                              ),
                            ),
                            suffixIconConstraints:
                                const BoxConstraints(minWidth: 44, minHeight: 44),
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
                              return LocalizationHelper.registerPasswordRequired;
                            }
                            if (v.length < 8) {
                              return LocalizationHelper.registerPasswordMin;
                            }
                            return null;
                          },
                          onChanged: (value) {
                            _computeFormValid();
                            _updatePasswordStrength(value);
                          },
                        ),
                        buildPasswordStrengthIndicator(_passwordController.text, _passwordStrength),
                        TextFormField(
                          controller: _confirmPasswordController,
                          focusNode: _confirmPasswordFocusNode,
                          obscureText: _obscureConfirmPassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) =>
                              _confirmPasswordFocusNode.unfocus(),
                          decoration: InputDecoration(
                            labelText:
                                LocalizationHelper.registerConfirmPasswordLabel,
                            hintText:
                                LocalizationHelper.registerConfirmPasswordHint,
                            prefixIcon:
                                const Icon(Icons.lock_rounded, size: 22),
                            prefixIconConstraints:
                                const BoxConstraints(minWidth: 36, minHeight: 36),
                            suffixIcon: SizedBox(
                              width: 44,
                              height: 44,
                              child: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _obscureConfirmPassword =
                                        !_obscureConfirmPassword;
                                    if (!_obscureConfirmPassword) {
                                      _startConfirmPasswordHideTimer();
                                    }
                                  });
                                },
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  size: 20,
                                  color: AppColors.grey400,
                                ),
                              ),
                            ),
                            suffixIconConstraints:
                                const BoxConstraints(minWidth: 44, minHeight: 44),
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
                              return LocalizationHelper.registerConfirmRequired;
                            }
                            if (v != _passwordController.text) {
                              return LocalizationHelper.registerConfirmMatch;
                            }
                            return null;
                          },
                          onChanged: (_) => _computeFormValid(),
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() {
                              _agreeToTerms = !_agreeToTerms;
                              _computeFormValid();
                            });
                          },
                          child: Row(
                            children: [
                              SizedBox(
                                height: 24,
                                width: 24,
                                child: Checkbox(
                                  value: _agreeToTerms,
                                  onChanged: (v) {
                                    setState(() {
                                      _agreeToTerms =
                                          v ?? !_agreeToTerms;
                                      _computeFormValid();
                                    });
                                  },
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  activeColor: accentColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: AppTextStyles.bodySmall(
                                    color: isDark
                                        ? AppColors.textDarkSecondary
                                        : AppColors.textLightSecondary,
                                  ),
                                  children: [
                                    TextSpan(
                                      text:
                                          '${LocalizationHelper.registerAgreeTerms} ',
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
                                            LocalizationHelper.registerTerms,
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
                                          ' ${LocalizationHelper.registerAnd} ',
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
                                            LocalizationHelper.registerPrivacy,
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
                          ],
                        ),
                      ),
                        const SizedBox(height: 28),
                        SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed:
                                (_isLoading || !_isFormValid) ? null : _handleRegister,
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
                                    LocalizationHelper.registerCreateAccount,
                                    style: AppTextStyles.buttonText(
                                      color: isDark
                                          ? AppColors.black
                                          : AppColors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              LocalizationHelper.registerHaveAccount,
                              style: AppTextStyles.bodySmall(
                                color: isDark
                                    ? AppColors.textDarkTertiary
                                    : AppColors.textLightTertiary,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                Navigator.pop(context);
                              },
                              child: Text(
                                LocalizationHelper.registerSignIn,
                                style: AppTextStyles.bodyMedium(
                                  color: accentColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
