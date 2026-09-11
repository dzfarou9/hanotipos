// lib/screens/reports_screen.dart
//
// Reports & Analytics screen: time-filtered KPI cards, stat grid, and a Sales
// Overview line chart.
//
// Follows the same conventions as the existing screens:
// - StatefulWidget + setState + singleton services
// - ScreenPalette extension for theme-aware colors
// - AppTextStyles / DesignTokens for consistent typography and spacing
// - StatTile for KPI cards
// - SyncService.dataChangeNotifier for cross-screen reactivity
// - RefreshIndicator for pull-to-refresh
// - fl_chart for the line chart

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../widgets/skeleton.dart';
import '../helpers/localization_helper.dart';
import '../helpers/reports_helper.dart';
import '../models/product_model.dart';
import '../models/purchase_model.dart';
import '../models/sale_model.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/design_tokens.dart';
import '../theme/screen_palette.dart';
import '../widgets/stat_tile.dart';

/// Reports screen â€” shows aggregated sales/purchase/product data with a
/// time-filtered line chart of daily revenue.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // Constants
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  static const String _currency = 'DZD';
  static const List<ReportTimeFilter> _filters = [
    ReportTimeFilter.week,
    ReportTimeFilter.month,
    ReportTimeFilter.year,
    ReportTimeFilter.custom,
  ];

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // Dependencies
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  final SyncService _sync = SyncService();
  Timer? _refreshDebounce;

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // State
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  ReportTimeFilter _selectedFilter = ReportTimeFilter.week;
  ReportData _reportData = const ReportData();
  bool _isLoading = true;
  DateTime? _customStart;
  DateTime? _customEnd;

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // Lifecycle
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  @override
  void initState() {
    super.initState();
    _loadData();
    _sync.dataChangeNotifier.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    _sync.dataChangeNotifier.removeListener(_onDataChanged);
    _refreshDebounce?.cancel();
    super.dispose();
  }

  void _onDataChanged() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(
      const Duration(milliseconds: 400),
      () {
        if (mounted) _loadData();
      },
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // Data loading
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        _sync.getAllSales(),
        _sync.getPurchases(),
        _sync.getAllProducts(),
      ]);

      final allSales = results[0] as List<Sale>;
      final allPurchases = results[1] as List<Purchase>;
      final allProducts = results[2] as List<Product>;

      if (!mounted) return;

      final data = computeReport(
        allSales: allSales,
        allPurchases: allPurchases,
        allProducts: allProducts,
        allDebtTransactions: DatabaseService.instance.getAllDebtTransactions(),
        filter: _selectedFilter,
        customStart: _customStart,
        customEnd: _customEnd,
      );

      setState(() {
        _reportData = data;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _onFilterChanged(ReportTimeFilter filter) async {
    // The Custom chip always re-opens the picker so the range can be adjusted.
    if (filter == ReportTimeFilter.custom) {
      final picked = await _pickCustomRange();
      if (picked == null || !mounted) return;
      setState(() {
        _selectedFilter = ReportTimeFilter.custom;
        _customStart = DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        );
        // Inclusive end-of-day so sales made on the last day are counted.
        _customEnd = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
        _isLoading = true;
      });
      await _loadData();
      return;
    }

    if (filter == _selectedFilter) return;
    setState(() {
      _selectedFilter = filter;
      _isLoading = true;
    });
    await _loadData();
  }

  /// Opens the Material date-range picker used by the Custom filter.
  Future<DateTimeRange?> _pickCustomRange() {
    final now = DateTime.now();
    final accentColor = context.accent;
    final initial = (_customStart != null && _customEnd != null)
        ? DateTimeRange(start: _customStart!, end: _customEnd!)
        : DateTimeRange(
            start: now.subtract(const Duration(days: 6)),
            end: now,
          );

    return showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initial,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: accentColor),
        ),
        child: child!,
      ),
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // Formatting helpers
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  /// Compacts an amount to K/M form. Sign-aware, because a bucket's net revenue
  /// can be negative when returns outweigh sales.
  String _formatAmount(double amount) {
    final sign = amount < 0 ? '-' : '';
    final magnitude = amount.abs();
    if (magnitude >= 1000000) {
      return '$sign${(magnitude / 1000000).toStringAsFixed(1)}'
          '${LocalizationHelper.commonMillionSuffix}';
    }
    if (magnitude >= 1000) {
      return '$sign${(magnitude / 1000).toStringAsFixed(1)}'
          '${LocalizationHelper.commonThousandSuffix}';
    }
    return amount.toStringAsFixed(0);
  }

  /// Localises a chart bucket key for display.
  ///
  /// Buckets are stored as stable keys (`Jan`â€¦`Dec`, `W1`â€¦`W5`, `d/m`) so the
  /// aggregation helper stays pure; only the label shown to the user is
  /// translated. Day keys (`d/m`) are numeric and pass through unchanged.
  String _localizeChartLabel(String key) {
    final month = monthNumberFromChartKey(key);
    if (month != null) return LocalizationHelper.shortMonthName(month);
    final week = weekNumberFromChartKey(key);
    if (week != null) return LocalizationHelper.weekShort(week);
    return key;
  }

  String _formatCurrency(double amount) {
    return '${amount.toStringAsFixed(0)} $_currency';
  }

  /// Compact day/month label used by the Custom filter chip. The project has no
  /// `intl` dependency and formats dates manually elsewhere, so this follows
  /// that convention rather than introducing DateFormat.
  String _shortDate(DateTime date) => '${date.day}/${date.month}';

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // Build
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  @override
  Widget build(BuildContext context) {
    final accentColor = context.accent;
    final titleColor = context.titleColor;
    final bodyColor = context.bodyColor;
    final scaffoldColor = context.scaffoldColor;

    return Scaffold(
      backgroundColor: scaffoldColor,
      appBar: AppBar(
        title: Text(
          'reports.title'.tr(),
          style: AppTextStyles.headline4(color: titleColor),
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(Icons.arrow_back_rounded, color: accentColor),
        ),
      ),
      body: _isLoading
          ? const SkeletonLoadingView()
          : RefreshIndicator(
              onRefresh: _loadData,
              color: accentColor,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.pageMargin,
                  DesignTokens.space8,
                  DesignTokens.pageMargin,
                  DesignTokens.pageMargin,
                ),
                children: [
                  _buildFilterRow(context),
                  const SizedBox(height: DesignTokens.sectionGap),
                  _buildMainProfitCard(context),
                  const SizedBox(height: DesignTokens.sectionGap),
                  _buildStatsGrid(context),
                  const SizedBox(height: DesignTokens.sectionGap),
                  _buildSalesChart(context, titleColor, bodyColor, accentColor),
                ],
              ),
            ),
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // Filter bar
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  Widget _buildFilterRow(BuildContext context) {
    final accentColor = context.accent;
    final isDark = context.isDark;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in _filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildFilterChip(
                context,
                label: _filterLabel(filter),
                isSelected: _selectedFilter == filter,
                accentColor: accentColor,
                isDark: isDark,
                onTap: () => _onFilterChanged(filter),
              ),
            ),
        ],
      ),
    );
  }

  String _filterLabel(ReportTimeFilter filter) {
    switch (filter) {
      case ReportTimeFilter.week:
        return 'reports.week'.tr();
      case ReportTimeFilter.month:
        return 'reports.month'.tr();
      case ReportTimeFilter.year:
        return 'reports.year'.tr();
      case ReportTimeFilter.custom:
        // Once a range is picked the chip shows it, so the selection is visible
        // without re-opening the picker.
        if (_selectedFilter == ReportTimeFilter.custom &&
            _customStart != null &&
            _customEnd != null) {
          return '${_shortDate(_customStart!)} â†’ ${_shortDate(_customEnd!)}';
        }
        return 'reports.custom'.tr();
    }
  }

  Widget _buildFilterChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required Color accentColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: DesignTokens.animFast,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.space16,
          vertical: DesignTokens.space12,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: isDark ? 0.20 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
          border: Border.all(
            color: isSelected
                ? accentColor.withValues(alpha: isDark ? 0.5 : 0.4)
                : context.dividerColor,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMedium(
            color: isSelected ? accentColor : context.bodyColor,
          ),
        ),
      ),
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // Main profit card (top section)
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  Widget _buildMainProfitCard(BuildContext context) {
    final isDark = context.isDark;
    final accentColor = context.accent;

    return Container(
      padding: const EdgeInsets.all(DesignTokens.space20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1B2621), const Color(0xFF10362A)]
              : AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        boxShadow: DesignTokens.accentGlow(accentColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Net Profit row
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: DesignTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'reports.netProfit'.tr(),
                      style: AppTextStyles.caption(
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCurrency(_reportData.netProfit),
                      style: AppTextStyles.headline2(color: Colors.white),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
                ),
                child: Text(
                  '${'reports.cogs'.tr()} ${_formatAmount(_reportData.costOfGoodsSold)}',
                  style: AppTextStyles.caption(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.space20),
          Divider(
            color: Colors.white.withValues(alpha: 0.15),
            height: 1,
          ),
          const SizedBox(height: DesignTokens.space16),
          // Sub-metrics row
          Row(
            children: [
              Expanded(
                child: _buildSubMetric(
                  context,
                  icon: Icons.receipt_rounded,
                  label: 'reports.salesCount'.tr(),
                  value: '${_reportData.salesCount}',
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withValues(alpha: 0.15),
              ),
              Expanded(
                child: _buildSubMetric(
                  context,
                  icon: Icons.analytics_rounded,
                  label: 'reports.avgSale'.tr(),
                  value: '${_formatAmount(_reportData.averageSaleValue)} $_currency',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubMetric(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 18),
        const SizedBox(height: 6),
        Text(
          value,
          style: AppTextStyles.titleLarge(color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTextStyles.caption(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 10,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // Stats grid (4 cards)
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  Widget _buildStatsGrid(BuildContext context) {
    final accentColor = context.accent;

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 480 ? 2 : 4;
        final tiles = [
          StatTile(
            icon: Icons.shopping_cart_rounded,
            label: 'reports.imports'.tr(),
            value: _formatCurrency(_reportData.importsTotal),
            color: context.infoColor,
          ),
          StatTile(
            icon: Icons.trending_up_rounded,
            label: 'reports.exports'.tr(),
            value: _formatCurrency(_reportData.exportsTotal),
            color: accentColor,
          ),
          StatTile(
            icon: Icons.account_balance_rounded,
            label: 'reports.debts'.tr(),
            value: _formatCurrency(_reportData.debtsTotal),
            color: context.warningColor,
          ),
          StatTile(
            icon: Icons.inventory_2_rounded,
            label: 'reports.products'.tr(),
            value: '${_reportData.productsCount}',
            color: context.successColor,
          ),
        ];

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

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // Sales Overview Line Chart
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  Widget _buildSalesChart(
    BuildContext context,
    Color titleColor,
    Color bodyColor,
    Color accentColor,
  ) {
    final chartData = _reportData.chartData;
    final isDark = context.isDark;
    final entries = chartData.entries.toList();

    // Build spots. Values can be negative when returns outweigh sales in a
    // bucket, so both bounds are tracked rather than assuming a zero floor.
    final spots = <FlSpot>[];
    double maxValue = 0;
    double minValue = 0;
    bool hasNonZero = false;
    for (int i = 0; i < entries.length; i++) {
      final value = entries[i].value;
      if (value > maxValue) maxValue = value;
      if (value < minValue) minValue = value;
      if (value != 0) hasNonZero = true;
      spots.add(FlSpot(i.toDouble(), value));
    }

    // If there's no data, show a minimal empty state.
    if (entries.isEmpty || !hasNonZero) {
      return Container(
        padding: const EdgeInsets.all(DesignTokens.space32),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          border: Border.all(color: context.dividerColor),
        ),
        child: Column(
          children: [
            Icon(
              Icons.show_chart_rounded,
              size: 48,
              color: context.captionColor.withValues(alpha: 0.4),
            ),
            const SizedBox(height: DesignTokens.space12),
            Text(
              'reports.noChartData'.tr(),
              style: AppTextStyles.bodyMedium(color: bodyColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Pad the top, and the bottom too when any bucket went negative, so the
    // line and its dots are never clipped by the plot edges.
    final yMax = maxValue > 0 ? maxValue * 1.15 : 1.0;
    final yMin = minValue < 0 ? minValue * 1.15 : 0.0;
    final yInterval = (yMax - yMin) / 4;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.space4,
        DesignTokens.space20,
        DesignTokens.space16,
        DesignTokens.space20,
      ),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: DesignTokens.space12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusXs,
                    ),
                  ),
                  child: Icon(
                    Icons.show_chart_rounded,
                    color: accentColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: DesignTokens.space12),
                Text(
                  'reports.salesOverview'.tr(),
                  style: AppTextStyles.titleLarge(color: titleColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: DesignTokens.space20),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: entries.length > 1 ? (entries.length - 1).toDouble() : 1,
                minY: yMin,
                maxY: yMax,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: context.dividerColor,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: entries.length > 10
                          ? (entries.length / 5).ceilToDouble()
                          : 1,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= entries.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _localizeChartLabel(entries[idx].key),
                            style: AppTextStyles.caption(
                              color: bodyColor,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      interval: yInterval,
                      getTitlesWidget: (value, meta) {
                        // Hide the 0 label only on a zero baseline; when a
                        // bucket is negative the zero line is meaningful.
                        if (value == 0 && yMin == 0) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          _formatAmount(value),
                          style: AppTextStyles.caption(
                            color: bodyColor,
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (spot) =>
                        isDark ? AppColors.darkSurface : AppColors.lightSurface,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final idx = spot.spotIndex;
                        final label = idx < entries.length
                            ? _localizeChartLabel(entries[idx].key)
                            : '';
                        return LineTooltipItem(
                          '$label\n${_formatCurrency(spot.y)}',
                          TextStyle(
                            color: spot.bar.gradient?.colors.first ?? accentColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.28,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    gradient: LinearGradient(
                      colors: [
                        accentColor,
                        accentColor.withValues(alpha: 0.6),
                      ],
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          accentColor.withValues(alpha: 0.25),
                          accentColor.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                    dotData: const FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}