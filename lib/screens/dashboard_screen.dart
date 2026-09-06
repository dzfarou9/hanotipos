// lib/screens/dashboard_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import '../models/sale_model.dart';
import '../services/sync_service.dart';
import '../helpers/low_stock_helper.dart';
import '../helpers/top_products_helper.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/design_tokens.dart';
import '../theme/screen_palette.dart';
import '../helpers/localization_helper.dart';
import '../helpers/time_format_helper.dart';
import '../widgets/stat_tile.dart';
import '../widgets/low_stock_sheet.dart';
import '../widgets/app_snackbar.dart';

class DashboardScreen extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onThemeToggle;
  final ThemeMode themeMode;
  final Function(ThemeMode) onThemeModeChange;
  final VoidCallback? onOpenDrawer;

  const DashboardScreen({
    super.key,
    required this.isDarkMode,
    required this.onThemeToggle,
    required this.themeMode,
    required this.onThemeModeChange,
    this.onOpenDrawer,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final SyncService _sync = SyncService();

  Map<String, dynamic> _stats = {};
  List<Sale> _recentSales = [];
  List<TopProduct> _topProducts = [];
  Map<String, double> _paymentDistribution = {};
  double _todayRevenue = 0.0;
  double _yesterdayRevenue = 0.0;
  int _todayTransactions = 0;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  static const String _currency = 'DZD';

  bool _isDataStale = true;
  bool _isLoadingData = false;
  bool _pendingRefresh = false;
  Timer? _refreshDebounce;

  late AnimationController _counterController;
  late Animation<double> _counterAnimation;

  // ⭐ مقتطف آمن لرقم الفاتورة (منع الانهيار مع معرفات قصيرة)
  static String _shortId(String id) =>
      id.length >= 8 ? id.substring(0, 8) : id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _counterController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _counterAnimation = CurvedAnimation(
      parent: _counterController,
      curve: Curves.easeOutCubic,
    );

    _loadData();

    _sync.dataChangeNotifier.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _sync.dataChangeNotifier.removeListener(_onDataChanged);
    _counterController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshIfNeeded();
    }
  }

  void _onDataChanged() {
    _isDataStale = true;
    // ⭐ تجميع إشعارات تغيير البيانات المتتالية في إعادة تحميل واحدة
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _refreshIfNeeded();
    });
  }

  void _refreshIfNeeded() {
    if (_isDataStale && mounted) {
      if (_isLoadingData) {
        _pendingRefresh = true;
      } else {
        _isDataStale = false;
        _loadData();
      }
    }
  }

  Future<void> _loadData() async {
    if (_isLoadingData) {
      _pendingRefresh = true;
      return;
    }
    _isLoadingData = true;
    _isDataStale = false;

    if (!mounted) return;
    final isFirstLoad = _stats.isEmpty;
    setState(() {
      _isLoading = isFirstLoad;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      // ⭐ جلب كل المبيعات والمنتجات بدون سقف لضمان صحة الإحصائيات المالية
      final allSales = await _sync.getAllSales();
      final allProducts = await _sync.getAllProducts();

      if (!mounted) return;

      // ⭐ لازي: نعرض الأساسيات فوراً (المبيعات والمنتجات والمعاملات الأخيرة)
      // قبل حساب الإحصائيات الثقيلة في الخلفية، فلا ينتظر المستخدم
      setState(() {
        _recentSales = allSales.take(5).toList();
        _isLoading = false;
        _hasError = false;
      });

      // ⭐ نترك الإطار الأول يُرسم ثم نكمل الحسابات الثقيلة في الخلفية
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      // ⭐ حساب الإحصائيات في مسح واحد بدلاً من 6 مسحات منفصلة
      final aggregates = _computeAggregates(allSales);
      final todayRevenue = aggregates.todayRevenue;
      final todayTransactions = aggregates.todayTransactions;
      final yesterdayRevenue = aggregates.yesterdayRevenue;
      final averageSales = aggregates.averageSales;
      final topProducts = calculateTopProducts(allSales, allProducts);
      final paymentDistribution = aggregates.paymentDistribution;

      final inventoryStats = await _sync.getInventoryStats();

      final stats = {
        'todayRevenue': todayRevenue,
        'todayTransactions': todayTransactions,
        'totalProducts': inventoryStats['totalProducts'],
        'totalInventory': inventoryStats['totalQuantity'],
        'lowStock': inventoryStats['lowStock'],
        'outOfStock': inventoryStats['outOfStock'],
        'averageSales': averageSales,
      };

      if (!mounted) return;

      setState(() {
        _stats = stats;
        _topProducts = topProducts;
        _paymentDistribution = paymentDistribution;
        _todayRevenue = todayRevenue;
        _todayTransactions = todayTransactions;
        _yesterdayRevenue = yesterdayRevenue;
      });

      _counterController.reset();
      _counterController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = _stats.isEmpty;
        _errorMessage = e.toString();
      });

      AppSnackBar.show(
        context,
        '${LocalizationHelper.error}: ${e.toString()}',
        type: AppSnackType.error,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: LocalizationHelper.syncRetry,
          textColor: Colors.white,
          onPressed: _loadData,
        ),
      );
    } finally {
      _isLoadingData = false;
      if (_pendingRefresh && mounted) {
        _pendingRefresh = false;
        _loadData();
      }
    }
  }

  // ⭐ حساب الإحصائيات في مسح واحد للمبيعات (بدلاً من 6 مسحات منفصلة)
  ({
    double todayRevenue,
    int todayTransactions,
    double yesterdayRevenue,
    double averageSales,
    Map<String, double> paymentDistribution,
  }) _computeAggregates(List<Sale> allSales) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final yesterday = now.subtract(const Duration(days: 1));
    final startOfYesterday =
        DateTime(yesterday.year, yesterday.month, yesterday.day);
    final weekAgo = now.subtract(const Duration(days: 7));

    final Map<String, double> dailyNetSales = {};
    for (int i = 0; i < 7; i++) {
      final date = weekAgo.add(Duration(days: i));
      dailyNetSales['${date.day}/${date.month}/${date.year}'] = 0.0;
    }

    double todayRevenue = 0.0;
    int todayTransactions = 0;
    double yesterdayRevenue = 0.0;
    final Map<String, double> paymentDistribution = {};

    for (var sale in allSales) {
      final createdAt = sale.createdAt;
      final isToday =
          createdAt.isAfter(startOfDay) && createdAt.isBefore(endOfDay);
      if (isToday) {
        if (sale.isReturn) {
          todayRevenue -= sale.total;
        } else {
          todayRevenue += sale.remainingTotal;
          if (!sale.isFullyReturned) todayTransactions++;
        }
      }

      final isYesterday = createdAt.isAfter(startOfYesterday) &&
          createdAt.isBefore(startOfDay);
      if (isYesterday) {
        if (sale.isReturn) {
          yesterdayRevenue -= sale.total;
        } else {
          yesterdayRevenue += sale.remainingTotal;
        }
      }

      final dailyKey =
          '${createdAt.day}/${createdAt.month}/${createdAt.year}';
      if (dailyNetSales.containsKey(dailyKey)) {
        dailyNetSales[dailyKey] =
            (dailyNetSales[dailyKey] ?? 0.0) +
                (sale.isReturn ? -sale.total : sale.remainingTotal);
      }

      if (!sale.isReturn && sale.remainingTotal > 0) {
        paymentDistribution[sale.paymentMethod] =
            (paymentDistribution[sale.paymentMethod] ?? 0.0) +
                sale.remainingTotal;
      }
    }

    double totalNetSales = 0.0;
    int daysWithPositiveSales = 0;
    dailyNetSales.forEach((key, value) {
      if (value > 0) {
        totalNetSales += value;
        daysWithPositiveSales++;
      }
    });

    return (
      todayRevenue: todayRevenue,
      todayTransactions: todayTransactions,
      yesterdayRevenue: yesterdayRevenue,
      averageSales: daysWithPositiveSales == 0
          ? 0.0
          : totalNetSales / daysWithPositiveSales,
      paymentDistribution: paymentDistribution,
    );
  }

  double get _revenueChangePercent {
    if (_yesterdayRevenue <= 0) return _todayRevenue > 0 ? 100.0 : 0.0;
    return ((_todayRevenue - _yesterdayRevenue) / _yesterdayRevenue) * 100;
  }

  String get _revenueChangeText {
    final change = _revenueChangePercent;
    if (_yesterdayRevenue <= 0 && change == 0.0) {
      return LocalizationHelper.dashboardVsYesterday;
    }
    final isPositive = change >= 0;
    return '${isPositive ? '↑' : '↓'} ${change.abs().toStringAsFixed(1)}% ${LocalizationHelper.dashboardVsYesterday}';
  }

  Future<void> _showLowStockProducts() async {
    try {
      final products = await _sync.getAllProducts();
      final result = classifyLowStockProducts(products);

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => SafeArea(
          child: LowStockProductsSheet(
            lowStock: result.lowStock,
            outOfStock: result.outOfStock,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(
        context,
        '${LocalizationHelper.error} ${LocalizationHelper.dashboardLowStockTitle}',
      );
    }
  }

  void _showTransactionDetails(Sale sale) {
    final accentColor = context.accent;
    final titleColor = context.titleColor;
    final bodyColor = context.bodyColor;
    final isReturn = sale.isReturned;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd)),
        backgroundColor: context.cardColor,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 450, maxHeight: 600),
          padding: const EdgeInsets.all(DesignTokens.space20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(DesignTokens.space8),
                        decoration: BoxDecoration(
                          color: isReturn
                              ? AppColors.warningLight
                              : accentColor.withValues(alpha:0.1),
                          borderRadius:
                              BorderRadius.circular(DesignTokens.radiusXs),
                        ),
                        child: Icon(
                          isReturn
                              ? Icons.reply_rounded
                              : Icons.receipt_long_rounded,
                          color: isReturn ? AppColors.warning : accentColor,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: DesignTokens.space8),
                      Text(
                        isReturn
                            ? LocalizationHelper.salesHistoryReturn
                            : LocalizationHelper.dashboardTransactionDetails,
                        style: AppTextStyles.headline4(color: titleColor),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    tooltip: LocalizationHelper.cancel,
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.grey400),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.space16),
              Container(
                padding: const EdgeInsets.all(DesignTokens.space16),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha:0.06),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                ),
                child: Column(
                  children: [
                    _buildDetailRow(
                      LocalizationHelper.dashboardDate,
                      _formatFullDate(sale.createdAt),
                      bodyColor,
                    ),
                    const SizedBox(height: 6),
                    _buildDetailRow(
                      LocalizationHelper.dashboardTime,
                      _formatTime(sale.createdAt),
                      bodyColor,
                    ),
                    const SizedBox(height: 6),
                    _buildDetailRow(
                      LocalizationHelper.dashboardPayment,
                      LocalizationHelper.paymentMethod(sale.paymentMethod),
                      bodyColor,
                    ),
                    const SizedBox(height: 6),
                    _buildDetailRow(
                      LocalizationHelper.dashboardTotalAmount,
                      '${sale.total.toStringAsFixed(2)} $_currency',
                      isReturn ? AppColors.warning : accentColor,
                      isBold: true,
                    ),
                    if (isReturn) ...[
                      const SizedBox(height: 6),
                      _buildDetailRow(
                        LocalizationHelper.salesHistoryReturn,
                        LocalizationHelper.salesHistoryReturn,
                        AppColors.warning,
                      ),
                      if (sale.originalSaleId != null)
                        _buildDetailRow(
                          LocalizationHelper.salesHistoryInvoice,
                          '#${_shortId(sale.originalSaleId!).toUpperCase()}',
                          bodyColor,
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: DesignTokens.space16),
              Text(
                '${LocalizationHelper.dashboardProductsList} (${sale.items.length})',
                style: AppTextStyles.bodyLarge(color: titleColor),
              ),
              const SizedBox(height: DesignTokens.space8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sale.items.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: context.dividerColor,
                  ),
                  itemBuilder: (_, i) {
                    final item = sale.items[i];
                    final isReturned = sale.returnedItems
                            ?.any((r) => r.productId == item.productId) ??
                        false;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha:0.1),
                              borderRadius:
                                  BorderRadius.circular(DesignTokens.radiusXs),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${item.quantity}',
                              style: AppTextStyles.caption(color: accentColor),
                            ),
                          ),
                          const SizedBox(width: DesignTokens.space8),
                          Expanded(
                            child: Text(
                              isReturned
                                  ? '${item.productName} (${LocalizationHelper.salesHistoryReturned})'
                                  : item.productName,
                              style: AppTextStyles.bodyMedium(
                                color: isReturned
                                    ? AppColors.warning
                                    : bodyColor,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${item.subtotal.toStringAsFixed(2)} $_currency',
                            style: AppTextStyles.bodyMedium(
                              color: isReturn ? AppColors.warning : accentColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _refreshIfNeeded());
  }

  Widget _buildDetailRow(String label, String value, Color color,
      {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodySmall(color: AppColors.grey500)),
        Text(
          value,
          style: isBold
              ? AppTextStyles.bodyLarge(color: color)
              : AppTextStyles.bodyMedium(color: color),
        ),
      ],
    );
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    return LocalizationHelper.formatHeaderDate(
      LocalizationHelper.dayName(now.weekday),
      now.day,
      now.month,
      now.year,
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return LocalizationHelper.dashboardGoodMorning;
    if (hour < 18) return LocalizationHelper.dashboardGoodAfternoon;
    return LocalizationHelper.dashboardGoodEvening;
  }

  IconData _getTimeIcon() {
    final hour = DateTime.now().hour;
    if (hour < 6) return Icons.nights_stay_rounded;
    if (hour < 12) return Icons.wb_sunny_rounded;
    if (hour < 18) return Icons.wb_cloudy_rounded;
    return Icons.nights_stay_rounded;
  }

  String _formatTimeAgo(DateTime dateTime) => formatTimeAgo(dateTime);

  String _formatFullDate(DateTime dateTime) =>
      '${dateTime.day}/${dateTime.month}/${dateTime.year}';

  String _formatTime(DateTime dateTime) =>
      '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final accentColor = context.accent;
    final textPrimary = context.titleColor;
    final textSecondary = context.bodyColor;
    final backgroundColor = context.scaffoldColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: accentColor,
          child: _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: accentColor),
                      const SizedBox(height: 16),
                      Text(
                        LocalizationHelper.loading,
                        style: AppTextStyles.bodyMedium(color: textSecondary),
                      ),
                    ],
                  ),
                )
              : _hasError
                  ? _buildErrorWidget(isDark, accentColor, textSecondary)
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      children: [
                        _buildTopBar(context, isDark, accentColor),
                        const SizedBox(height: 16),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: RepaintBoundary(
                            child:
                                _buildWelcomeCard(context, isDark, accentColor),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: RepaintBoundary(
                            child:
                                _buildStatsGrid(context, isDark, accentColor),
                          ),
                        ),
                        if (_topProducts.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20),
                            child: RepaintBoundary(
                              child: _buildTopProductsSection(
                                  context, isDark, accentColor, textPrimary),
                            ),
                          ),
                        ],
                        if (_paymentDistribution.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20),
                            child: RepaintBoundary(
                              child: _buildPaymentDistributionSection(
                                context,
                                isDark,
                                accentColor,
                                textPrimary,
                                textSecondary,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Padding(
                          padding: EdgeInsets.only(
                            left: 20,
                            right: 20,
                            bottom:
                                MediaQuery.of(context).padding.bottom + 120,
                          ),
                          child: RepaintBoundary(
                            child: _buildRecentTransactions(
                              context,
                              isDark,
                              accentColor,
                              textPrimary,
                              textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(
      BuildContext context, bool isDark, Color accentColor) {
    final revenue = _todayRevenue;
    final transactions = _todayTransactions;
    final change = _revenueChangePercent;
    final isPositive = change >= 0;
    final changeText = _revenueChangeText;
    final greeting = _getGreeting();
    final timeIcon = _getTimeIcon();
    final formattedDate = _getFormattedDate();

    // ⭐ الألوان: صلبان عميقة متدرجة بدل التدرج البسيط
    final gradientColors = isDark
        ? [AppColors.darkSurface, AppColors.darkSurfaceAlt, AppColors.darkSurface]
        : [
            AppColors.primaryDark,
            AppColors.primary,
            AppColors.secondaryDark,
          ];
    // لون النص الفاتح فوق البطاقة
    final onCard = isDark ? AppColors.textDarkPrimary : AppColors.white;
    final onCardSecondary =
        isDark ? AppColors.textDarkSecondary : AppColors.white.withValues(alpha: 0.8);
    final onCardTertiary =
        isDark ? AppColors.textDarkTertiary : AppColors.white.withValues(alpha: 0.65);
    // أسطح زجاجية داخل البطاقة
    final glassColor =
        (isDark ? AppColors.white : AppColors.black).withValues(alpha: 0.10);
    final glassBorder =
        (isDark ? AppColors.white : AppColors.black).withValues(alpha: 0.16);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        border: isDark
            ? Border.all(color: accentColor.withValues(alpha: 0.3), width: 1.5)
            : null,
        boxShadow: DesignTokens.accentGlow(accentColor, opacity: 0.22),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        child: Stack(
          children: [
            // ⭐ لمعة قطرية ناعمة أعلى اليسار
            Positioned(
              top: -60,
              left: -40,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.white.withValues(alpha: isDark ? 0.06 : 0.14),
                      AppColors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // ⭐ حلقة زخرفية كبيرة تخرج من حافة اليمين
            Positioned(
              top: -30,
              right: -70,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.white.withValues(alpha: isDark ? 0.05 : 0.08),
                    width: 22,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ⭐ الترويسة: تحية + تاريخ + أيقونة وقت داخل دائرة زجاجية
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    greeting,
                                    style: AppTextStyles.bodyLarge(
                                      color: onCardSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formattedDate,
                              style: AppTextStyles.caption(
                                color: onCardTertiary,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: glassColor,
                          border: Border.all(color: glassBorder, width: 1),
                        ),
                        child: Icon(
                          timeIcon,
                          color: onCard.withValues(alpha: 0.9),
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // ⭐ شريط الإيراد: لوح زجاجي واحد بدل الفاصل + النصوص المبعثرة
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: glassColor,
                      borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                      border: Border.all(color: glassBorder, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    LocalizationHelper.dashboardTodayRevenue,
                                    style: AppTextStyles.caption(
                                      color: onCardSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  AnimatedBuilder(
                                    animation: _counterAnimation,
                                    builder: (context, child) {
                                      final displayValue =
                                          revenue * _counterAnimation.value;
                                      return FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        child: Text(
                                          '${displayValue.toStringAsFixed(0)} $_currency',
                                          style: AppTextStyles.headline1(
                                            color: onCard,
                                          ),
                                          maxLines: 1,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // ⭐ لوحة المعاملات: زجاج مطابق ليوحّد النظام
                            Container(
                              width: 88,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 12),
                              decoration: BoxDecoration(
                                color: glassColor,
                                borderRadius:
                                    BorderRadius.circular(DesignTokens.radiusLg),
                                border:
                                    Border.all(color: glassBorder, width: 1),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      '$transactions',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                        color: onCard,
                                      ),
                                      maxLines: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    LocalizationHelper.dashboardTransactions,
                                    style: AppTextStyles.caption(
                                      color: onCardTertiary,
                                      fontSize: 10,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // ⭐ شريحة الاتجاه: حبة أنعم بلون الحالة
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: (isPositive
                                    ? AppColors.success
                                    : AppColors.error)
                                .withValues(alpha: 0.22),
                            borderRadius:
                                BorderRadius.circular(DesignTokens.radiusPill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPositive
                                    ? Icons.trending_up_rounded
                                    : Icons.trending_down_rounded,
                                color: isDark
                                    ? (isPositive
                                        ? AppColors.successOnDark
                                        : AppColors.errorOnDark)
                                    : AppColors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                changeText,
                                style: AppTextStyles.caption(
                                  color: isDark
                                      ? (isPositive
                                          ? AppColors.successOnDark
                                          : AppColors.errorOnDark)
                                      : AppColors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_yesterdayRevenue > 0) ...[
                          const SizedBox(height: 10),
                          Text(
                            '${LocalizationHelper.dashboardYesterday}: ${_yesterdayRevenue.toStringAsFixed(0)} $_currency',
                            style: AppTextStyles.caption(
                              color: onCardTertiary,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context, bool isDark, Color accentColor) {
    final todayTransactions = _todayTransactions;
    final averageSales = _stats['averageSales'] ?? 0.0;
    final totalProducts = _stats['totalProducts'] ?? 0;
    final lowStock = _stats['lowStock'] ?? 0;
    final outOfStock = _stats['outOfStock'] ?? 0;
    final lowStockTotal = lowStock + outOfStock;

    final tiles = [
      StatTile(
        icon: Icons.shopping_cart_rounded,
        label: LocalizationHelper.dashboardSalesToday,
        value: '$todayTransactions',
        color: accentColor,
        subtitle: LocalizationHelper.dashboardTransactions,
      ),
      StatTile(
        icon: Icons.trending_up_rounded,
        label: LocalizationHelper.dashboardAverageSales,
        value: '${averageSales.toStringAsFixed(0)}',
        color: AppColors.info,
        subtitle: LocalizationHelper.dashboardPerDay,
      ),
      StatTile(
        icon: Icons.inventory_2_rounded,
        label: LocalizationHelper.dashboardProducts,
        value: '$totalProducts',
        color: AppColors.success,
        subtitle: LocalizationHelper.dashboardInStock,
      ),
      StatTile(
        icon: Icons.warning_rounded,
        label: LocalizationHelper.dashboardLowStockTitle,
        value: '$lowStockTotal',
        color: lowStockTotal > 0 ? AppColors.warning : AppColors.success,
        subtitle: lowStockTotal > 0
            ? LocalizationHelper.dashboardLowStock
            : LocalizationHelper.dashboardInStock,
        deltaText: lowStockTotal > 0
            ? LocalizationHelper.dashboardAlert
            : LocalizationHelper.dashboardExcellent,
        deltaColor: lowStockTotal > 0 ? AppColors.error : AppColors.success,
        onTap: _showLowStockProducts,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 480 ? 2 : 4;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: DesignTokens.space12,
          crossAxisSpacing: DesignTokens.space12,
          childAspectRatio: 1.05,
          children: tiles,
        );
      },
    );
  }

  Widget _buildTopProductsSection(
    BuildContext context,
    bool isDark,
    Color accentColor,
    Color textPrimary,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha:0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: AppColors.warning,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  LocalizationHelper.dashboardTopProducts,
                  style: AppTextStyles.headline4(color: textPrimary),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _topProducts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final topProduct = _topProducts[i];
              final product = topProduct.product;
              final medals = ['1', '2', '3'];
              final colors = [
                AppColors.warning,
                AppColors.grey400,
                AppColors.info,
              ];
              return Container(
                width: 80,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceAlt
                      : AppColors.lightSurfaceAlt,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                  border: Border.all(
                    color: colors[i % colors.length].withValues(alpha:0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      medals[i],
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: colors[i % colors.length],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.name,
                      style: AppTextStyles.caption(
                        color: isDark
                            ? AppColors.textDarkPrimary
                            : AppColors.textLightPrimary,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${topProduct.totalSales.toStringAsFixed(0)} $_currency',
                      style: AppTextStyles.caption(
                        color: accentColor,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentDistributionSection(
    BuildContext context,
    bool isDark,
    Color accentColor,
    Color textPrimary,
    Color textSecondary,
  ) {
    final total =
        _paymentDistribution.values.fold(0.0, (sum, val) => sum + val);
    final colors = [
      AppColors.success,
      AppColors.info,
      AppColors.warning,
      AppColors.secondary,
      AppColors.error,
    ];

    final sortedEntries = _paymentDistribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sortedEntries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha:0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.pie_chart_rounded,
                color: AppColors.info,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              LocalizationHelper.dashboardPaymentDistribution,
              style: AppTextStyles.headline4(color: textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            side: BorderSide(
              color: isDark
                  ? AppColors.grey700.withValues(alpha:0.3)
                  : AppColors.grey200.withValues(alpha:0.5),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: sortedEntries.asMap().entries.map((entry) {
                final index = entry.key;
                final paymentMethod =
                    LocalizationHelper.paymentMethod(entry.value.key);
                final amount = entry.value.value;
                final percentage = total > 0 ? (amount / total) * 100 : 0;
                final color = colors[index % colors.length];

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: Text(
                              paymentMethod,
                              style: AppTextStyles.bodyMedium(
                                color: isDark
                                    ? AppColors.textDarkPrimary
                                    : AppColors.textLightPrimary,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                height: 10,
                                color: isDark
                                    ? AppColors.darkSurfaceAlt
                                    : AppColors.lightSurfaceAlt,
                                child: FractionallySizedBox(
                                  widthFactor: percentage / 100,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [color, color.withValues(alpha:0.7)],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${percentage.toStringAsFixed(1)}%',
                            style: AppTextStyles.bodyMedium(
                              color: isDark
                                  ? AppColors.textDarkPrimary
                                  : AppColors.textLightPrimary,
                              fontSize: 13,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${amount.toStringAsFixed(0)} $_currency',
                            style: AppTextStyles.caption(
                              color: textSecondary,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentTransactions(
    BuildContext context,
    bool isDark,
    Color accentColor,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha:0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.receipt_long_rounded,
                    color: accentColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  LocalizationHelper.dashboardRecentTransactions,
                  style: AppTextStyles.headline4(color: textPrimary),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_recentSales.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              side: BorderSide(
                color: isDark
                    ? AppColors.grey700.withValues(alpha:0.3)
                    : AppColors.grey200.withValues(alpha:0.5),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha:0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.receipt_long_rounded,
                        size: 40,
                        color: isDark
                            ? AppColors.textDarkTertiary
                            : AppColors.textLightTertiary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      LocalizationHelper.dashboardNoTransactions,
                      style: AppTextStyles.bodyLarge(color: textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      LocalizationHelper.dashboardCompleteSale,
                      style: AppTextStyles.bodySmall(
                        color: isDark
                            ? AppColors.textDarkTertiary
                            : AppColors.textLightTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              side: BorderSide(
                color: isDark
                    ? AppColors.grey700.withValues(alpha:0.3)
                    : AppColors.grey200.withValues(alpha:0.5),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _recentSales.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: isDark
                          ? AppColors.grey700.withValues(alpha: 0.3)
                          : AppColors.grey200,
                    ),
                  _buildTransactionTile(
                    context,
                    sale: _recentSales[i],
                    isDark: isDark,
                    accentColor: accentColor,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTransactionTile(
    BuildContext context, {
    required dynamic sale,
    required bool isDark,
    required Color accentColor,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final isReturn = sale.isReturned;
    final String statusLabel;
    final Color statusColor;
    final Color statusBg;
    if (sale.isReturn) {
      statusLabel = LocalizationHelper.salesHistoryReturn;
      statusColor = AppColors.warning;
      statusBg = AppColors.warningLight;
    } else if (sale.isFullyReturned) {
      statusLabel = LocalizationHelper.salesHistoryFullyReturned;
      statusColor = AppColors.error;
      statusBg = AppColors.errorLight;
    } else if (sale.returnedItems != null &&
        sale.returnedItems!.isNotEmpty) {
      statusLabel =
          LocalizationHelper.salesHistoryPartiallyReturned;
      statusColor = AppColors.info;
      statusBg = AppColors.infoLight;
    } else {
      statusLabel = LocalizationHelper.dashboardCompleted;
      statusColor = AppColors.success;
      statusBg = AppColors.success.withValues(alpha: 0.15);
    }
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 8,
      ),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isReturn
              ? AppColors.warning.withValues(alpha: 0.15)
              : accentColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        ),
        child: Icon(
          isReturn
              ? Icons.reply_rounded
              : Icons.receipt_long_rounded,
          color: isReturn ? AppColors.warning : accentColor,
          size: 18,
        ),
      ),
      title: Text(
        isReturn
                        ? '${LocalizationHelper.salesHistoryReturn} #${_shortId(sale.id).toUpperCase()}'
                        : '${LocalizationHelper.dashboardInvoice} #${_shortId(sale.id).toUpperCase()}',
        style: AppTextStyles.bodyMedium(color: textPrimary),
      ),
      subtitle: Text(
        '${_formatTimeAgo(sale.createdAt)} • ${LocalizationHelper.paymentMethod(sale.paymentMethod)} • ${sale.items.length} ${LocalizationHelper.posItems}',
        style: AppTextStyles.caption(
          color: textSecondary,
          fontSize: 10,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${sale.total.toStringAsFixed(2)} $_currency',
            style: AppTextStyles.bodyLarge(
              color: isReturn ? AppColors.warning : accentColor,
            ).copyWith(fontSize: 14),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              statusLabel,
              style: AppTextStyles.overline(
                color: statusColor,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
      onTap: () => _showTransactionDetails(sale),
    );
  }

  Widget _buildTopBar(BuildContext context, bool isDark, Color accentColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha:0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildAppName(isDark, accentColor),
          _buildMenuButton(context, isDark, accentColor),
        ],
      ),
    );
  }

  Widget _buildAppName(bool isDark, Color accentColor) {
    final appName = LocalizationHelper.brandName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: accentColor.withValues(alpha:0.2), width: 0.5),
          ),
          child: Text(
            LocalizationHelper.posBadge,
            style: AppTextStyles.overline(
              color: accentColor,
              fontSize: 10,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          appName,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: isDark ? AppColors.neonOrange : AppColors.primary,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildMenuButton(
    BuildContext context,
    bool isDark,
    Color accentColor,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          widget.onOpenDrawer?.call();
        },
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha:0.08),
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            border: Border.all(color: accentColor.withValues(alpha:0.2), width: 1),
          ),
          child: Icon(
            Icons.menu_rounded,
            color: accentColor,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(
      bool isDark, Color accentColor, Color textSecondary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              LocalizationHelper.error,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppColors.textDarkPrimary
                    : AppColors.textLightPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              style: AppTextStyles.bodyMedium(color: textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(LocalizationHelper.syncRetry),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: isDark ? AppColors.black : AppColors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
