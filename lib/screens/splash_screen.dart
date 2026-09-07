// lib/screens/splash_screen.dart
//
// شاشة البداية — تصميم "مصقول" باتباع الثيم (فاتح/داكن):
//   1) خلفية بشعاع إmeraldي ناعم + مدارَان يتنفسان (transform فقط)
//   2) اسم العلامة: صعود + انكماش تباعد الأحرف (بدون توهج)
//   3) شريحة الشعار النصي (Tagline) بحافة شعرية
//   4) لودر: ثلاث نقاط تتنفس بتتابع زمني (بدون Spinner)
//
// كل الحركات transform/opacity فقط، بمنحنيات easeOutCubic/easeOutExpo —
// بلا elastic/bounce وبلا ظلال توهج. منطق الجلسة والمزامنة والتنقل
// محفوظ حرفياً من النسخة السابقة.

import 'dart:math' as math;
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
  // ── متحكمات الدخول المتتابع ──
  late final AnimationController _wordmarkController;
  late final AnimationController _pillController;
  late final AnimationController _loaderController;

  late final Animation<double> _wordmarkFade;
  late final Animation<double> _wordmarkRise;
  late final Animation<double> _wordmarkTracking;
  late final Animation<double> _pillFade;
  late final Animation<double> _pillRise;
  late final Animation<double> _loaderFade;

  // ── مدار التنفس الخلفي ──
  late final AnimationController _orbController;

  bool _minSplashElapsed = false;

  String get _appName => LocalizationHelper.brandName;

  ui.TextDirection get _textDirection => appTextDirection(context.locale);

  @override
  void initState() {
    super.initState();

    _wordmarkController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _wordmarkFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _wordmarkController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );
    _wordmarkRise = Tween<double>(begin: 24.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _wordmarkController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
      ),
    );
    _wordmarkTracking = Tween<double>(begin: 10.0, end: 4.0).animate(
      CurvedAnimation(
        parent: _wordmarkController,
        curve: const Interval(0.1, 0.9, curve: Curves.easeOutExpo),
      ),
    );

    _pillController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _pillFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pillController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );
    _pillRise = Tween<double>(begin: 16.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _pillController,
        curve: const Interval(0.0, 0.9, curve: Curves.easeOutCubic),
      ),
    );

    _loaderController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _loaderFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _loaderController, curve: Curves.easeOutCubic),
    );

    _orbController = AnimationController(
      duration: const Duration(milliseconds: 5000),
      vsync: this,
    )..repeat(reverse: true);

    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _wordmarkController.forward();
    });
    Future.delayed(const Duration(milliseconds: 550), () {
      if (mounted) _pillController.forward();
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _loaderController.forward();
    });
    _wordmarkController.forward();

    // ⭐ فحص الجلسة بعد أول إطار: الشاشة تُرسم فوراً قبل أي عمل شبكة/تخزين،
    // وأي فشل في فحص الجلسة يُسقط بأمان إلى شاشة الدخول بدلاً من تجميد البداية.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigateToNextScreen();
    });
  }

  @override
  void dispose() {
    _wordmarkController.dispose();
    _pillController.dispose();
    _loaderController.dispose();
    _orbController.dispose();
    super.dispose();
  }

  Future<void> _ensureMinSplashTime() async {
    if (!_minSplashElapsed) {
      await Future.delayed(const Duration(milliseconds: 1600));
      _minSplashElapsed = true;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // منطق التنقل والجلسة — محفوظ حرفياً (لا تعديل)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _navigateToNextScreen() async {
    try {
      await _runSessionCheck();
    } catch (e) {
      AppConfig.logError('⚠️ Session check failed, falling back to login', e);
      if (!mounted) return;
      await _ensureMinSplashTime();
      if (!mounted) return;
      _navigateToLogin();
    }
  }

  Future<void> _runSessionCheck() async {
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

  // ═══════════════════════════════════════════════════════════════════════════
  // الواجهة
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    final bgColor =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final textSecondary =
        isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;
    final textTertiary =
        isDark ? AppColors.textDarkTertiary : AppColors.textLightTertiary;
    final appName = _appName;
    final textDirection = _textDirection;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // ── الخلفية: شعاع ناعم + مدارَان يتنفسان ──
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.6,
                  colors: [
                    accentColor.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: _BreathingOrbs(
              animation: _orbController,
              accentColor: accentColor,
            ),
          ),

          // ── المحتوى المركزي ──
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // اسم العلامة: صعود + انكماش التباعد
                Directionality(
                  textDirection: textDirection,
                  child: AnimatedBuilder(
                    animation: _wordmarkController,
                    builder: (context, child) => Opacity(
                      opacity: _wordmarkFade.value,
                      child: Transform.translate(
                        offset: Offset(0, _wordmarkRise.value),
                        child: child,
                      ),
                    ),
                    child: Text(
                      appName,
                      style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w800,
                        color: accentColor,
                        letterSpacing: _wordmarkTracking.value,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // شريحة الشعار النصي
                Directionality(
                  textDirection: ui.TextDirection.ltr,
                  child: AnimatedBuilder(
                    animation: _pillController,
                    builder: (context, child) => Opacity(
                      opacity: _pillFade.value,
                      child: Transform.translate(
                        offset: Offset(0, _pillRise.value),
                        child: child,
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        LocalizationHelper.appTagline,
                        style: AppTextStyles.bodyMedium(color: textSecondary),
                      ),
                    ),
                  ),
                ),

                const Spacer(flex: 2),

                // أسفل: الشعار الفرعي + النقاط النابضة
                Directionality(
                  textDirection: ui.TextDirection.ltr,
                  child: AnimatedBuilder(
                    animation: _loaderController,
                    builder: (context, child) => Opacity(
                      opacity: _loaderFade.value,
                      child: child,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: Column(
                        children: [
                          Text(
                            LocalizationHelper.appSubtagline,
                            style: AppTextStyles.caption(
                              color: textTertiary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _BreathingDots(accentColor: accentColor),
                        ],
                      ),
                    ),
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

// ═════════════════════════════════════════════════════════════════════════════
// المدارَان الخلفيان: تمدد/انكماش بطيء — transform فقط
// ═════════════════════════════════════════════════════════════════════════════

class _BreathingOrbs extends StatelessWidget {
  final Animation<double> animation;
  final Color accentColor;
  const _BreathingOrbs({required this.animation, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Stack(
          children: [
            Positioned(
              top: -60,
              right: -40,
              child: Transform.scale(
                scale: 1.0 + 0.08 * math.sin(t * math.pi),
                child: _orb(180, 0.06),
              ),
            ),
            Positioned(
              bottom: 80,
              left: -50,
              child: Transform.scale(
                scale: 1.0 + 0.06 * math.sin((t + 0.5) * math.pi),
                child: _orb(220, 0.045),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _orb(double size, double alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            accentColor.withValues(alpha: alpha),
            accentColor.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// اللودر: ثلاث نقاط تتنفس بطور جيبي متتابع — transform فقط
// ═════════════════════════════════════════════════════════════════════════════

class _BreathingDots extends StatefulWidget {
  final Color accentColor;
  const _BreathingDots({required this.accentColor});

  @override
  State<_BreathingDots> createState() => _BreathingDotsState();
}

class _BreathingDotsState extends State<_BreathingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // طور متتابع: كل نقطة تتأخر 0.25 دورة عن سابقتها
            final phase = (_pulse.value - i * 0.25) % 1.0;
            final lift = math.sin(phase * math.pi);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Transform.translate(
                offset: Offset(0, -4 * lift),
                child: Transform.scale(
                  scale: 0.8 + 0.4 * lift,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.accentColor
                          .withValues(alpha: 0.35 + 0.65 * lift),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
