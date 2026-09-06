// lib/widgets/dashboard_menu.dart

import 'package:flutter/material.dart';
import '../helpers/localization_helper.dart';
import '../theme/app_text_styles.dart';
import '../theme/design_tokens.dart';
import '../theme/screen_palette.dart';
import '../screens/settings_screen.dart';
import '../screens/inventory_screen.dart';
import '../screens/suppliers_screen.dart';
import '../screens/customers_screen.dart';
import '../screens/purchases_history_screen.dart';
import '../screens/reports_screen.dart';

/// القائمة الجانبية للتنقل بين شاشات الإدارة.
///
/// قائمة مسطحة بلون واحد: صف لكل شاشة، مجموعة في قسم للإدارة وقسم
/// للتطبيق. الصفوف لا تحمل بطاقة خاصة بها — سطح القائمة هو البطاقة —
/// فيبقى الأخضر الأساسي هو اللون الوحيد في القائمة.
class DashboardMenu extends StatelessWidget {
  final VoidCallback onClose;
  final ThemeMode themeMode;
  final Function(ThemeMode) onThemeModeChange;

  const DashboardMenu({
    super.key,
    required this.onClose,
    required this.themeMode,
    required this.onThemeModeChange,
  });

  /// سقف عرض القائمة حتى لا تتمدد على الشاشات الكبيرة.
  static const double _maxWidth = 340;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: (MediaQuery.sizeOf(context).width * 0.82).clamp(0.0, _maxWidth),
      backgroundColor: context.cardColor,
      semanticLabel: LocalizationHelper.menuNavigation,
      // القائمة تفتح من الحافة اليمنى، فتُدوَّر الحافة الداخلية (اليسرى) فقط.
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(DesignTokens.radiusLg),
          bottomLeft: Radius.circular(DesignTokens.radiusLg),
        ),
      ),
      child: SafeArea(
        child: RepaintBoundary(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              Expanded(
                child: ListView(
                  // ‏8 هنا + 12 داخل كل صف = محتوى الصفوف يبدأ عند 20،
                  // على نفس خط الرأس والتذييل، مع بقاء مساحة للتموّج.
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.space8,
                    vertical: DesignTokens.space16,
                  ),
                  children: [
                    _buildSectionLabel(
                      context,
                      LocalizationHelper.menuSectionManage,
                    ),
                    _buildNavRow(
                      context,
                      icon: Icons.inventory_2_rounded,
                      label: LocalizationHelper.inventoryTitle,
                      onTap: () => _open(context, const InventoryScreen()),
                    ),
                    _buildNavRow(
                      context,
                      icon: Icons.local_shipping_rounded,
                      label: LocalizationHelper.suppliersTitle,
                      onTap: () => _open(context, const SuppliersScreen()),
                    ),
                    _buildNavRow(
                      context,
                      icon: Icons.people_rounded,
                      label: LocalizationHelper.customersTitle,
                      onTap: () => _open(context, const CustomersScreen()),
                    ),
                    _buildNavRow(
                      context,
                      icon: Icons.receipt_long_rounded,
                      label: LocalizationHelper.purchasesTitle,
                      onTap: () =>
                          _open(context, const PurchasesHistoryScreen()),
                    ),
                    _buildNavRow(
                      context,
                      icon: Icons.bar_chart_rounded,
                      label: LocalizationHelper.reportsTitle,
                      onTap: () => _open(context, const ReportsScreen()),
                    ),
                    const SizedBox(height: DesignTokens.space20),
                    _buildSectionLabel(
                      context,
                      LocalizationHelper.menuSectionApp,
                    ),
                    _buildNavRow(
                      context,
                      icon: Icons.settings_rounded,
                      label: LocalizationHelper.settingsTitle,
                      onTap: () => _open(
                        context,
                        SettingsScreen(
                          themeMode: themeMode,
                          onThemeModeChange: onThemeModeChange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  /// يغلق القائمة ثم يفتح الشاشة المطلوبة.
  void _open(BuildContext context, Widget screen) {
    onClose();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final accent = context.accent;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.space20,
        DesignTokens.space16,
        DesignTokens.space8,
        DesignTokens.space16,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.dividerColor)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            ),
            child: Text('ح', style: AppTextStyles.headline4(color: accent)),
          ),
          const SizedBox(width: DesignTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocalizationHelper.appName,
                  style: AppTextStyles.titleLarge(color: context.titleColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  LocalizationHelper.appTagline,
                  style: AppTextStyles.caption(color: context.captionColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 20),
            color: context.captionColor,
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.space12,
        DesignTokens.space4,
        DesignTokens.space12,
        DesignTokens.space8,
      ),
      child: Text(
        text,
        style: AppTextStyles.overline(color: context.captionColor),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildNavRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final accent = context.accent;
    final radius = BorderRadius.circular(DesignTokens.radiusSm);

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        splashColor: accent.withValues(alpha: 0.10),
        highlightColor: accent.withValues(alpha: 0.06),
        hoverColor: accent.withValues(alpha: 0.06),
        focusColor: accent.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.space12,
            vertical: 14,
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(width: DesignTokens.space16),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.titleMedium(color: context.titleColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.captionColor,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.space20,
        DesignTokens.space12,
        DesignTokens.space20,
        DesignTokens.space16,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.dividerColor)),
      ),
      child: Text(
        LocalizationHelper.menuAppVersion,
        style: AppTextStyles.caption(color: context.captionColor, fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
