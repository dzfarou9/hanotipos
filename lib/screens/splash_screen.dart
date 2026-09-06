// lib/screens/splash_screen.dart

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/sync_service.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../helpers/localization_helper.dart';
import '../helpers/direction_helper.dart';
import 'login_screen.dart';
import 'main_screen.dart';
import 'subscription_expired_screen.dart';

class SplashScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(ThemeMode) onThemeModeChange;

  const SplashScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChange,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _textRevealController;
  late AnimationController _subtitleController;
  late AnimationController _taglineController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _textRevealAnimation;
  late Animation<double> _subtitleFadeAnimation;
  late Animation<double> _taglineFadeAnimation;

  bool _minSplashElapsed = false;

  String get _appName {
    return LocalizationHelper.brandName;
  }

  ui.TextDirection get _textDirection {
    return appTextDirection(context.locale);
  }

  bool get _isArabic => context.locale.languageCode == 'ar';

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
      ),
    );

    _textRevealController = AnimationController(
      duration: const Duration(milliseconds: 2200),
      vsync: this,
    );

    _textRevealAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textRevealController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeInOut),
      ),
    );

    _subtitleController = AnimationController(
      duration: const Duration(milliseconds: 2800),
      vsync: this,
    );

    _subtitleFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _subtitleController,
        curve: const Interval(0.7, 0.95, curve: Curves.easeIn),
      ),
    );

    _taglineController = AnimationController(
      duration: const Duration(milliseconds: 3200),
      vsync: this,
    );

    _taglineFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _taglineController,
        curve: const Interval(0.8, 1.0, curve: Curves.easeIn),
      ),
    );

    _scaleController.forward();
    _textRevealController.forward();
    _subtitleController.forward();
    _taglineController.forward();

    // ⭐ نبدأ فحص الجلسة والمزامنة فوراً (بدلاً من انتظار 3.5 ثانية)،
    // مع فرض حد أدنى لعرض شاشة البداية حتى لا "يومض" التطبيق.
    _navigateToNextScreen();
  }

  Future<void> _ensureMinSplashTime() async {
    if (!_minSplashElapsed) {
      await Future.delayed(const Duration(milliseconds: 1600));
      _minSplashElapsed = true;
    }
  }

  Future<void> _navigateToNextScreen() async {
    final authService = AuthService.instance;
    final db = DatabaseService.instance;
    final syncService = SyncService();
    final firebaseService = FirebaseService();

    final isLoggedIn = authService.isLoggedIn;

    if (isLoggedIn) {
      final isValid = await authService.validateSession();

      if (!mounted) return;

      if (!isValid) {
        await authService.logout();
        if (!mounted) return;
        await _ensureMinSplashTime();
        _navigateToLogin();
        return;
      }

      // ⭐ C-2: بوابة "الخادم أولاً" — عند انتهاء مهلة الفحص لا نثق
      // بـ Hive بلا قيد، بل نطبّق قاعدة الإيجار (48 ساعة بعد آخر تحقق
      // من السيرفر + تاريخ انتهاء مستقبلي).
      bool isActive;
      try {
        isActive =
            await firebaseService.isSubscriptionActive().timeout(
                  const Duration(seconds: 3),
                  onTimeout: () => firebaseService.isSubscriptionLeaseValid(),
                );
      } catch (e) {
        AppConfig.logError(
            '⚠️ Subscription check online failed, applying lease rule', e);
        isActive = firebaseService.isSubscriptionLeaseValid();
      }

      if (!mounted) return;

      if (isActive) {
        // ⭐ Offline First: شاشة البداية هي نقطة المزامنة الأولية الموثوقة
        // نرفع البيانات غير المتزامنة إلى Firebase، ثم نجلب البيانات الناقصة،
        // ونُحدّث Hive قبل الانتقال للشاشة الرئيسية (القراءة من المحلي فقط لاحقاً)
        try {
          final productCount = db.getProductCount();
          final saleCount = db.getSaleCount();
          AppConfig.log(
              '📊 Hive state before sync: $productCount products, $saleCount sales');

          if (syncService.isOnline) {
            AppConfig.log('📤 Running initial sync (upload unsynced + download)...');
            await syncService.syncNow().timeout(
                  const Duration(seconds: 20),
                  onTimeout: () {
                    AppConfig.log('⏰ Initial sync timed out, continuing to app');
                  },
                );
          } else {
            AppConfig.log('⚠️ No internet connection, using local data only');
          }

          final finalProductCount = db.getProductCount();
          final finalSaleCount = db.getSaleCount();
          AppConfig.log(
              '📊 Final Hive state: $finalProductCount products, $finalSaleCount sales');
        } catch (e) {
          AppConfig.logError('⚠️ Data loading error', e);
        }

        if (!mounted) return;

        await _ensureMinSplashTime();
        if (!mounted) return;

        _navigateToMain();
      } else {
        await _ensureMinSplashTime();
        if (!mounted) return;
        _navigateToSubscriptionExpired();
      }
    } else {
      await _ensureMinSplashTime();
      if (!mounted) return;
      _navigateToLogin();
    }
  }

  void _navigateToMain() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => MainScreen(
          themeMode: widget.themeMode,
          onThemeToggle: () {},
          onThemeModeChange: widget.onThemeModeChange,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  void _navigateToLogin() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => LoginScreen(
          themeMode: widget.themeMode,
          onThemeModeChange: widget.onThemeModeChange,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  void _navigateToSubscriptionExpired() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            SubscriptionExpiredScreen(
          themeMode: widget.themeMode,
          onThemeModeChange: widget.onThemeModeChange,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _textRevealController.dispose();
    _subtitleController.dispose();
    _taglineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    final bgColor =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final appName = _appName;
    final textDirection = _textDirection;
    final isArabic = _isArabic;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.5,
                  colors: [
                    accentColor.withValues(alpha: 0.08),
                    Colors.transparent,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _scaleController,
              child: Stack(
                children: List.generate(20, (i) {
                  return Positioned(
                    top: (i * 37.0) % MediaQuery.of(context).size.height,
                    left: (i * 53.0) % MediaQuery.of(context).size.width,
                    child: Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }),
              ),
              builder: (context, child) {
                return Opacity(
                  opacity: 0.5 + 0.5 * (1 - _scaleController.value),
                  child: child,
                );
              },
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                Directionality(
                  textDirection: textDirection,
                  child: AnimatedBuilder(
                    animation: _scaleController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _scaleAnimation.value,
                        child: AnimatedBuilder(
                          animation: _textRevealController,
                          builder: (context, child) {
                            if (isArabic) {
                              return Opacity(
                                opacity: _textRevealAnimation.value,
                                child: Text(
                                  appName,
                                  style: TextStyle(
                                    fontSize: 56,
                                    fontWeight: FontWeight.w900,
                                    color: accentColor,
                                    letterSpacing: 6,
                                    shadows: [
                                      Shadow(
                                        color: accentColor.withValues(
                                          alpha: 0.5 *
                                              _textRevealAnimation.value,
                                        ),
                                        blurRadius: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            final revealProgress = _textRevealAnimation.value;

                            // ⭐ صيغة مبسطة: اكتفاء بخاصية التدرج على الكلمة كلها
                            // بدلاً من تحويل كل حرف على حدة (طبقات أقل لكل إطار)
                            return Opacity(
                              opacity: revealProgress,
                              child: Transform.translate(
                                offset: Offset(
                                  0,
                                  20 * (1 - revealProgress),
                                ),
                                child: Text(
                                  appName,
                                  style: TextStyle(
                                    fontSize: 56,
                                    fontWeight: FontWeight.w900,
                                    color: accentColor,
                                    letterSpacing: 6,
                                    shadows: [
                                      Shadow(
                                        color: accentColor.withValues(
                                          alpha: 0.5 * revealProgress,
                                        ),
                                        blurRadius: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Directionality(
                  textDirection: ui.TextDirection.ltr,
                  child: AnimatedBuilder(
                    animation: _subtitleController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _subtitleFadeAnimation.value,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: accentColor.withValues(alpha: 0.3),
                                width: 1),
                          ),
                          child: Text(
                            LocalizationHelper.appTagline,
                            style: AppTextStyles.bodyMedium(
                              color: isDark
                                  ? AppColors.textDarkSecondary
                                  : AppColors.textLightSecondary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const Spacer(flex: 2),
                Directionality(
                  textDirection: ui.TextDirection.ltr,
                  child: AnimatedBuilder(
                    animation: _taglineController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _taglineFadeAnimation.value,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 40),
                          child: Column(
                            children: [
                              Text(
                                LocalizationHelper.appSubtagline,
                                style: AppTextStyles.caption(
                                  color: isDark
                                      ? AppColors.textDarkTertiary
                                      : AppColors.textLightTertiary,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      accentColor),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
