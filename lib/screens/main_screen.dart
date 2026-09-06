// lib/screens/main_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/cart_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import '../helpers/localization_helper.dart';
import '../widgets/sync_progress_widget.dart';
import '../widgets/sync_status_widget.dart';
// ⭐ إضافة import لـ DashboardMenu
import '../widgets/dashboard_menu.dart';
import '../theme/screen_palette.dart';
import 'dashboard_screen.dart';
import 'pos_screen.dart';
import 'sales_history_screen.dart';

// ⭐ تصدير MainScreen للاستخدام في ملفات أخرى
export 'main_screen.dart' show MainScreen;

class MainScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final VoidCallback onThemeToggle;
  final Function(ThemeMode) onThemeModeChange;

  const MainScreen({
    super.key,
    required this.themeMode,
    required this.onThemeToggle,
    required this.onThemeModeChange,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;

  // ⭐ شاشات تُبنى عند أول زيارة فقط (تحميل كسول) بدلاً من بناء الثلاث جميعاً
  late final List<Widget?> _screens;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isSyncing = false;
  bool _isInitialSyncDone = false;

  // ⭐ إشعار للشاشات داخل IndexedStack للعلم بتبديل التبويب النشط
  final ValueNotifier<int> _activeTabNotifier = ValueNotifier<int>(0);

  final GlobalKey _syncWidgetKey = GlobalKey();

  // ⭐ مفاتيح فريدة لكل شاشة
  final Map<int, GlobalKey> _screenKeys = {
    0: GlobalKey(),
    1: GlobalKey(),
    2: GlobalKey(),
  };

  // ⭐ Key للـ Scaffold للتحكم في الـ Drawer
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();

    // ⭐ تحميل كسول: تُبنى الشاشة عند أول زيارة للتبويب فقط
    _screens = [null, null, null];

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkInitialSync();
  }

  Future<void> _checkInitialSync() async {
    final syncService = SyncService();
    _isInitialSyncDone = syncService.isInitialSyncDone;

    if (!_isInitialSyncDone && !syncService.isSyncing) {
      setState(() => _isSyncing = true);

      try {
        await syncService.syncNow().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('⏰ Sync timeout, continuing...');
          },
        );
      } catch (e) {
        print('⚠️ Sync error: $e');
      } finally {
        if (mounted) {
          setState(() {
            _isSyncing = false;
            _isInitialSyncDone = SyncService().isInitialSyncDone;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _activeTabNotifier.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onTabTap(int index) {
    if (_currentIndex == index) return;

    _pulseController.stop();
    setState(() {
      _currentIndex = index;
    });

    // ⭐ إعلام الشاشات الداخلية بتبديل التبويب (تُستخدم لإعادة التحميل عند الدخول)
    _activeTabNotifier.value = index;
  }

  // ⭐ بناء الشاشة عند أول زيارة للتبويب فقط (تحميل كسول)
  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return RepaintBoundary(
          child: DashboardScreen(
            key: _screenKeys[0],
            isDarkMode: widget.themeMode == ThemeMode.dark,
            onThemeToggle: widget.onThemeToggle,
            themeMode: widget.themeMode,
            onThemeModeChange: widget.onThemeModeChange,
            // ⭐ تمرير دالة فتح الـ End Drawer
            onOpenDrawer: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        );
      case 2:
        return RepaintBoundary(
          child: SalesHistoryScreen(
            key: _screenKeys[2],
            activeTabIndex: _activeTabNotifier,
          ),
        );
      default:
        return RepaintBoundary(
          child: POSScreen(key: _screenKeys[1]!),  // Keep alive with fixed key
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final accentColor = context.accent;
    final isArabic = context.locale.languageCode == 'ar';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      extendBody: true,
      // ⭐ استخدام endDrawer لعرض القائمة الجانبية
      endDrawer: DashboardMenu(
        onClose: () {
          // ⭐ إغلاق القائمة الجانبية
          Navigator.pop(context);
        },
        themeMode: widget.themeMode,
        onThemeModeChange: widget.onThemeModeChange,
      ),
      body: Stack(
        children: [
          // ⭐ المحتوى الرئيسي (تحميل كسول: تُبنى الشاشة عند أول زيارة)
          IndexedStack(
            index: _currentIndex,
            children: [
              for (var i = 0; i <= _currentIndex; i++)
                _screens[i] ??= _buildScreen(i),
            ],
          ),

          // ⭐ مؤشر المزامنة (أولي - أثناء المزامنة الأولية)
          if (_isSyncing && !_isInitialSyncDone)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accentColor,
                      accentColor.withValues(alpha:0.85),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.topRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha:0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark ? AppColors.black : AppColors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      LocalizationHelper.loading,
                      style: TextStyle(
                        color: isDark ? AppColors.black : AppColors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• ${LocalizationHelper.syncPreparing}',
                      style: TextStyle(
                        color: (isDark ? AppColors.black : AppColors.white)
                            .withValues(alpha:0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ⭐ ويدجيت حالة المزامنة (ثانوي - يظهر دائماً في الزاوية)
          SyncStatusWidget(
            showAsFloating: true,
            onTap: () => SyncService().forceSync(),
          ),

          // ⭐ ويدجيت تقدم المزامنة
          Positioned(
            bottom: 100,
            left: 16,
            right: 16,
            child: SyncProgressWidget(
              key: _syncWidgetKey,
              showAsFloating: true,
              onTap: () {},
            ),
          ),

          // ⭐ Bottom Navigation Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomNavigationBar(isDark, accentColor, isArabic),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar(
      bool isDark, Color accentColor, bool isArabic) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark
              ? AppColors.grey700.withValues(alpha: 0.5)
              : AppColors.grey200.withValues(alpha: 0.8),
          width: 1,
        ),
        boxShadow: DesignTokens.raisedShadow(context),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTap,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: accentColor,
          unselectedItemColor: isDark
              ? AppColors.textDarkTertiary.withValues(alpha: 0.6)
              : AppColors.textLightTertiary.withValues(alpha: 0.6),
          selectedFontSize: 11,
          unselectedFontSize: 10,
          iconSize: 24,
          landscapeLayout: BottomNavigationBarLandscapeLayout.centered,
          showUnselectedLabels: true,
          enableFeedback: true,
          items: [
            BottomNavigationBarItem(
              icon: _buildNavIcon(
                icon: Icons.dashboard_rounded,
                isSelected: _currentIndex == 0,
                isDark: isDark,
                accentColor: accentColor,
              ),
              activeIcon: _buildNavIcon(
                icon: Icons.dashboard_rounded,
                isSelected: true,
                isDark: isDark,
                accentColor: accentColor,
                isActive: true,
              ),
              label: LocalizationHelper.bottomDashboard,
              tooltip: LocalizationHelper.bottomDashboard,
            ),
            BottomNavigationBarItem(
              icon: _buildCenterIcon(false, isDark, accentColor),
              activeIcon: _buildCenterIcon(true, isDark, accentColor),
              label: LocalizationHelper.bottomPos,
              tooltip: LocalizationHelper.bottomPos,
            ),
            BottomNavigationBarItem(
              icon: _buildNavIcon(
                icon: Icons.receipt_long_rounded,
                isSelected: _currentIndex == 2,
                isDark: isDark,
                accentColor: accentColor,
              ),
              activeIcon: _buildNavIcon(
                icon: Icons.receipt_long_rounded,
                isSelected: true,
                isDark: isDark,
                accentColor: accentColor,
                isActive: true,
              ),
              label: LocalizationHelper.bottomSalesHistory,
              tooltip: LocalizationHelper.bottomSalesHistory,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavIcon({
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required Color accentColor,
    bool isActive = false,
  }) {
    if (isActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          icon,
          color: accentColor,
          size: 24,
        ),
      );
    }
    return Icon(
      icon,
      size: 24,
    );
  }

  Widget _buildCenterIcon(bool isActive, bool isDark, Color accentColor) {
    final cartService = context.watch<CartService>();
    final hasItems = cartService.totalItems > 0;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) => Transform.scale(
        scale: isActive ? _pulseAnimation.value : 1.0,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? accentColor
                : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Container(
            padding: EdgeInsets.all(isActive ? 14 : 11),
            decoration: BoxDecoration(
              color: isDark
                  ? (isActive
                      ? AppColors.darkSurface
                      : AppColors.darkSurfaceAlt)
                  : (isActive
                      ? AppColors.lightSurface
                      : AppColors.lightSurfaceAlt),
              shape: BoxShape.circle,
              border: isActive
                  ? null
                  : Border.all(
                      color: (isDark
                              ? AppColors.grey600
                              : AppColors.grey300)
                          .withValues(alpha: 0.5),
                      width: 1,
                    ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.shopping_cart_rounded,
                  color: isActive
                      ? accentColor
                      : (isDark
                          ? AppColors.textDarkTertiary
                          : AppColors.grey500),
                  size: isActive ? 28 : 22,
                ),
                if (hasItems)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkSurface
                              : AppColors.lightSurface,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        '${cartService.totalItems}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
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
