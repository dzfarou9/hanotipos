// lib/screens/inventory_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/product_model.dart';
import '../services/sync_service.dart';
import '../services/firebase_service.dart';
import '../services/database_service.dart';
import '../services/scanner_feedback_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/design_tokens.dart';
import '../theme/screen_palette.dart';
import '../helpers/localization_helper.dart';
import '../helpers/quantity_format.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/barcode_scanner_view.dart';
import '../widgets/inventory/inventory_search_field.dart';
import '../widgets/inventory/product_form_dialog.dart';
import '../widgets/inventory/confirm_delete_dialog.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final SyncService _sync = SyncService();
  final FirebaseService _firebase = FirebaseService();
  final DatabaseService _db = DatabaseService.instance;

  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  Map<String, String> _searchCache = <String, String>{};
  String _searchQuery = '';
  String _selectedCategory = 'All';
  String _sortBy = 'common.newest';
  List<String> _categories = ['All'];

  bool _isScannerVisible = false;
  bool _isDialogOpen = false;
  bool _isProcessingBarcode = false;
  bool _isLoading = true;
  bool _loadFailed = false;

  int _loadGeneration = 0;
  Map<String, dynamic> _stats = const <String, dynamic>{};

  // ⭐ تجميع إشعارات تغيير البيانات في تحميل واحد بعد توقف النشاط
  Timer? _reloadDebounce;
  bool _isReloading = false;
  bool _reloadPendingDuringLoad = false;

  // ⭐ حالة إيقاف الماسح تُدار عبر ValueNotifier لتجنب إعادة بناء الشاشة
  final ValueNotifier<bool> _scannerPaused = ValueNotifier<bool>(false);

  final FocusNode _searchFocusNode = FocusNode();

  static const String _currency = 'DZD';

  static const List<String> _sortOptions = [
    'common.newest',
    'common.oldest',
    'common.name_az',
    'common.name_za',
    'common.price_low',
    'common.price_high',
    'common.quantity_low',
    'common.quantity_high',
  ];

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _sync.dataChangeNotifier.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _scannerPaused.dispose();
    _searchFocusNode.dispose();
    _sync.dataChangeNotifier.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (!mounted) return;
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 250), _performReload);
  }

  // ⭐ تنفيذ تحميل واحد مهما تعددت الإشعارات، مع منع التداخل أثناء التحميل
  Future<void> _performReload() async {
    if (_isReloading) {
      _reloadPendingDuringLoad = true;
      return;
    }
    _isReloading = true;
    try {
      await _loadProducts();
    } finally {
      _isReloading = false;
      if (_reloadPendingDuringLoad) {
        _reloadPendingDuringLoad = false;
        _performReload();
      }
    }
  }

  // ==================== Data Loading ====================

  Future<void> _loadProducts() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() => _isLoading = _products.isEmpty);
    }

    try {
      final products = await _sync.getAllProducts();

      if (!mounted || generation != _loadGeneration) return;

      final changed = _productsChanged(_products, products);

      setState(() {
        _products = products;
        _isLoading = false;
        _loadFailed = false;
        if (changed) {
          _categories = ['All', ..._deriveCategories(products)];
          _searchCache = _buildSearchCache(products);
          _refilterAndSort();
        }
      });

      _loadStatsInBackground(generation);
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _loadFailed = _products.isEmpty;
      });

      _showSnack(AppColors.error, '${LocalizationHelper.error}: $e');
    }
  }

  // ⭐ إحصائيات المخزون تُجلب في الخلفية دون إبطاء ظهور قائمة المنتجات
  Future<void> _loadStatsInBackground(int generation) async {
    try {
      final stats = await _sync.getInventoryStats();
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _stats = stats);
    } catch (_) {
      // فشل الإحصائيات لا يمنع عرض المنتجات
    }
  }

  Map<String, String> _buildSearchCache(List<Product> products) {
    final cache = <String, String>{};
    for (final product in products) {
      cache[product.id] =
          '${product.name} ${product.category} ${product.barcode ?? ''}'
              .toLowerCase();
    }
    return cache;
  }

  // ⭐ هل تغيّر محتوى المنتجات فعلياً؟ (لتجنب إعادة بناء الكاش بلا داعٍ)
  bool _productsChanged(List<Product> oldProducts, List<Product> newProducts) {
    if (oldProducts.length != newProducts.length) return true;
    for (var i = 0; i < oldProducts.length; i++) {
      final a = oldProducts[i];
      final b = newProducts[i];
      if (a.id != b.id ||
          a.name != b.name ||
          a.category != b.category ||
          a.price != b.price ||
          a.quantity != b.quantity ||
          a.minStockLevel != b.minStockLevel ||
          a.barcode != b.barcode ||
          !a.updatedAt.isAtSameMomentAs(b.updatedAt)) {
        return true;
      }
    }
    return false;
  }

  // ⭐ اشتقاق الفئات من المنتجات المجلوبة بدلاً من استدعاء service إضافي
  List<String> _deriveCategories(List<Product> products) {
    return products.map((p) => p.category).toSet().toList()..sort();
  }

  // ==================== Filter / Sort / Search ====================

  void _refilterAndSort() {
    final query = _searchQuery.trim().toLowerCase();
    final selected = _selectedCategory;

    _filteredProducts = <Product>[];
    if (query.isEmpty && selected == 'All') {
      _filteredProducts = List.of(_products);
    } else {
      for (final product in _products) {
        if (selected != 'All' && product.category != selected) continue;
        if (query.isNotEmpty) {
          final haystack = _searchCache[product.id];
          if (haystack == null || !haystack.contains(query)) continue;
        }
        _filteredProducts.add(product);
      }
    }

    // ⭐ القائمة مصدرها getAllProducts وهي مرتبة تنازلياً حسب updatedAt أصلاً
    if (_sortBy != 'common.newest') {
      _sortProducts(_filteredProducts);
    }
  }

  void _sortProducts(List<Product> products) {
    switch (_sortBy) {
      case 'common.newest':
        products.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case 'common.oldest':
        products.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
        break;
      case 'common.name_az':
        products.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'common.name_za':
        products.sort((a, b) => b.name.compareTo(a.name));
        break;
      case 'common.price_low':
        products.sort((a, b) => a.price.compareTo(b.price));
        break;
      case 'common.price_high':
        products.sort((a, b) => b.price.compareTo(a.price));
        break;
      case 'common.quantity_low':
        products.sort((a, b) => a.quantity.compareTo(b.quantity));
        break;
      case 'common.quantity_high':
        products.sort((a, b) => b.quantity.compareTo(a.quantity));
        break;
    }
  }

  // ==================== Dialogs / Scanner ====================

  // ⭐ إشعار الماسح عبر ValueNotifier دون إعادة بناء الشاشة كاملة
  void _updateScannerPause() {
    _scannerPaused.value = _isDialogOpen || _isProcessingBarcode;
  }

  Future<T?> _guardDialog<T>(Future<T?> Function() action) async {
    if (mounted && !_isDialogOpen) {
      _isDialogOpen = true;
      _updateScannerPause();
    }
    try {
      return await action();
    } finally {
      if (mounted && _isDialogOpen) {
        _isDialogOpen = false;
        _updateScannerPause();
      }
    }
  }

  void _toggleScanner() {
    setState(() => _isScannerVisible = !_isScannerVisible);
  }

  Future<void> _processScannedProduct(String barcode) async {
    if (_isProcessingBarcode) return;

    final normalized = barcode.trim();
    if (normalized.isEmpty) return;

    _isProcessingBarcode = true;
    _updateScannerPause();

    try {
      // البحث في قاعدة البيانات المحلية فقط (Hive) — لا يتم الاتصال بـ Firebase
      final product = _db.getProductByBarcode(normalized);

      if (!mounted) return;

      if (product != null) {
        // ⭐ اهتزاز متوسط عند العثور على المنتج
        ScannerFeedbackService.productFound();
        await _openProductForm(product: product);
      } else {
        // ⭐ اهتزاز قوي عند عدم العثور على المنتج
        ScannerFeedbackService.productNotFound();
        await _openProductForm(barcode: normalized);
      }
    } catch (e) {
      if (mounted) {
        _showSnack(AppColors.error, '${LocalizationHelper.error}: $e');
      }
    } finally {
      _isProcessingBarcode = false;
      _updateScannerPause();
    }
  }

  Future<void> _openProductForm({Product? product, String? barcode}) async {
    final result = await _guardDialog<ProductFormResult>(
      () => showProductFormDialog(context, product: product, barcode: barcode),
    );
    if (!mounted || result == null) return;

    switch (result.action) {
      case ProductFormAction.scan:
        setState(() => _isScannerVisible = true);
        break;
      case ProductFormAction.save:
        final data = result.data;
        if (data == null) return;
        await _saveProduct(product: product, data: data);
        break;
    }
  }

  Future<void> _saveProduct({
    Product? product,
    required ProductFormData data,
  }) async {
    final quantity = data.quantity < 0 ? 0.0 : data.quantity;
    final price = data.price < 0 ? 0.0 : data.price;

    try {
      if (product == null) {
        await _sync.addProduct(
          name: data.name,
          category: 'General',
          price: price,
          quantity: quantity,
          barcode: data.barcode,
          minStockLevel: data.minStockLevel,
          costPrice: data.costPrice,
          unit: data.unit,
        );
        _showSnack(AppColors.success, LocalizationHelper.posProductAdded);
      } else {
        await _sync.updateProduct(
          id: product.id,
          name: data.name,
          category: product.category,
          price: price,
          quantity: quantity,
          barcode: data.barcode,
          minStockLevel: data.minStockLevel,
          costPrice: data.costPrice,
          unit: data.unit,
        );
        _showSnack(AppColors.success, LocalizationHelper.posProductUpdated);
      }
    } catch (e) {
      _showSnack(AppColors.error, '${LocalizationHelper.error}: $e');
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await _guardDialog<bool>(
      () => showConfirmDeleteDialog(context, product),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _db.deleteProduct(product.id);
    } catch (e) {
      _showSnack(AppColors.error, '${LocalizationHelper.error}: $e');
      return;
    }

    if (_sync.isOnline) {
      try {
        await _firebase.deleteProduct(product.id);
      } catch (_) {
        _showSnack(
          AppColors.warning,
          LocalizationHelper.inventoryDeleteServerFailed,
          duration: const Duration(seconds: 3),
        );
      }
    } else {
      _showSnack(
        AppColors.warning,
        LocalizationHelper.inventoryDeleteOffline,
        duration: const Duration(seconds: 3),
      );
    }

    await _loadProducts();

    if (mounted) {
      _showSnack(
        AppColors.success,
        '${product.name} ${LocalizationHelper.inventoryDelete}',
      );
    }
  }

  void _showSnack(
    Color color,
    String message, {
    Duration? duration,
  }) {
    if (!mounted) return;
    final AppSnackType type;
    if (color == AppColors.success) {
      type = AppSnackType.success;
    } else if (color == AppColors.error) {
      type = AppSnackType.error;
    } else if (color == AppColors.warning) {
      type = AppSnackType.warning;
    } else {
      type = AppSnackType.info;
    }
    AppSnackBar.show(
      context,
      message,
      type: type,
      duration: duration ?? const Duration(seconds: 4),
    );
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    final titleColor =
        isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final bodyColor =
        isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;

    return GestureDetector(
      onTap: () => _searchFocusNode.unfocus(),
      child: SafeArea(
        child: Scaffold(
          backgroundColor:
              isDark ? AppColors.darkBackground : AppColors.lightBackground,
          appBar: AppBar(
            title: Text(
              LocalizationHelper.inventoryTitle,
              style: AppTextStyles.headline4(color: titleColor),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: Icon(Icons.arrow_back_rounded, color: accentColor),
            ),
            actions: [
              IconButton(
                onPressed: _toggleScanner,
                tooltip: 'pos.scan_barcode'.tr(),
                icon: Icon(
                  _isScannerVisible
                      ? Icons.stop_rounded
                      : Icons.qr_code_scanner_rounded,
                  color: accentColor,
                ),
              ),
              IconButton(
                onPressed: () => _openProductForm(),
                tooltip: 'inventory.add'.tr(),
                icon: Icon(Icons.add_rounded, color: accentColor),
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
                      Text(
                        LocalizationHelper.loading,
                        style: AppTextStyles.bodyMedium(color: bodyColor),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    _buildStatsRow(isDark, accentColor, titleColor, bodyColor),
                    _buildSearchAndSort(
                        isDark, accentColor, titleColor, bodyColor),
                    if (_isScannerVisible) ...[
                      ValueListenableBuilder<bool>(
                        valueListenable: _scannerPaused,
                        builder: (context, paused, _) => BarcodeScannerView(
                          onBarcodeDetected: _processScannedProduct,
                          onClose: () =>
                              setState(() => _isScannerVisible = false),
                          paused: paused,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Expanded(
                      child: _buildProductsList(
                          isDark, accentColor, titleColor, bodyColor),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ==================== Stats Row ====================

  Widget _buildStatsRow(
      bool isDark, Color accentColor, Color titleColor, Color bodyColor) {
    final stats = _stats;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          _buildStatChip(
            icon: Icons.inventory_2_rounded,
            label:
                '${_products.length} ${LocalizationHelper.inventoryProductsCount}',
            color: accentColor,
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _buildStatChip(
            icon: Icons.shopping_cart_rounded,
            label:
                '${stats['totalQuantity'] ?? 0} ${LocalizationHelper.inventoryItemsCount}',
            color: AppColors.success,
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _buildStatChip(
            icon: Icons.warning_rounded,
            label:
                '${stats['lowStock'] ?? 0} ${LocalizationHelper.inventoryLowStock}',
            color: AppColors.warning,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
            vertical: DesignTokens.space8, horizontal: DesignTokens.space8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: DesignTokens.space4),
            Flexible(
              child: Text(
                label,
                style: AppTextStyles.caption(color: color, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Search and Sort ====================

  Widget _buildSearchAndSort(
      bool isDark, Color accentColor, Color titleColor, Color bodyColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: InventorySearchField(
                  focusNode: _searchFocusNode,
                  onQueryChanged: (value) => _searchQuery = value,
                  onQueryDebounced: (_) {
                    if (mounted) setState(_refilterAndSort);
                  },
                ),
              ),
              const SizedBox(width: DesignTokens.space8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: context.dividerColor),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                ),
                child: PopupMenuButton<String>(
                  icon: Icon(Icons.sort_rounded, color: accentColor, size: 22),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  ),
                  onSelected: (value) {
                    setState(() {
                      _sortBy = value;
                      _refilterAndSort();
                    });
                  },
                  itemBuilder: (context) => _sortOptions
                      .map(
                        (option) => PopupMenuItem<String>(
                          value: option,
                          child: Row(
                            children: [
                              if (_sortBy == option)
                                Icon(Icons.check_rounded,
                                    color: accentColor, size: 18)
                              else
                                const SizedBox(width: 18),
                              const SizedBox(width: 8),
                              Text(
                                option.tr(),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final cat = _categories[i];
                final sel = cat == _selectedCategory;
                return FilterChip(
                  selected: sel,
                  label: Text(
                    LocalizationHelper.categoryLabel(cat),
                    style: TextStyle(
                      fontSize: 12,
                      color: sel
                          ? accentColor
                          : (isDark
                              ? AppColors.textDarkTertiary
                              : AppColors.textLightTertiary),
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  onSelected: (s) {
                    if (s && _selectedCategory == cat) return;
                    setState(() {
                      _selectedCategory = s ? cat : 'All';
                      _refilterAndSort();
                    });
                  },
                  selectedColor: accentColor.withValues(alpha: 0.08),
                  checkmarkColor: accentColor,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Products List ====================

  Widget _buildProductsList(
      bool isDark, Color accentColor, Color titleColor, Color bodyColor) {
    if (_filteredProducts.isEmpty) {
      return _buildEmptyState(
          isDark, accentColor, titleColor, bodyColor);
    }

    return RefreshIndicator(
      onRefresh: _loadProducts,
      color: accentColor,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        itemCount: _filteredProducts.length,
        itemBuilder: (_, i) => _buildProductCard(
            _filteredProducts[i], isDark, accentColor, titleColor, bodyColor),
      ),
    );
  }

  Widget _buildEmptyState(
      bool isDark, Color accentColor, Color titleColor, Color bodyColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.inventory_2_rounded,
              size: 56,
              color: isDark
                  ? AppColors.textDarkTertiary
                  : AppColors.textLightTertiary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            LocalizationHelper.inventoryNoProducts,
            style: AppTextStyles.bodyLarge(color: bodyColor),
          ),
          const SizedBox(height: 6),
          Text(
            _products.isEmpty
                ? LocalizationHelper.inventoryAddFirst
                : LocalizationHelper.inventoryAdjustSearch,
            style: AppTextStyles.bodySmall(
              color: isDark
                  ? AppColors.textDarkTertiary
                  : AppColors.textLightTertiary,
            ),
          ),
          if (_loadFailed) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _loadProducts,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(LocalizationHelper.syncRetry),
              style: OutlinedButton.styleFrom(
                foregroundColor: accentColor,
                side: BorderSide(color: accentColor.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
            ),
          ],
          if (_products.isEmpty && !_loadFailed) ...[
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () => _openProductForm(),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(LocalizationHelper.inventoryAdd),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: isDark ? AppColors.black : AppColors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== Product Card ====================

  Widget _buildProductCard(
    Product product,
    bool isDark,
    Color accentColor,
    Color titleColor,
    Color bodyColor,
  ) {
    final isLowStock =
        product.quantity <= product.minStockLevel && product.quantity > 0;
    final isOutOfStock = product.quantity == 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openProductForm(product: product),
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isOutOfStock
                      ? AppColors.errorLight
                      : isLowStock
                          ? AppColors.warningLight
                          : accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                ),
                child: Icon(
                  Icons.inventory_2_rounded,
                  color: isOutOfStock
                      ? AppColors.error
                      : isLowStock
                          ? AppColors.warning
                          : accentColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: AppTextStyles.bodyMedium(color: titleColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (product.barcode != null &&
                            product.barcode!.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              product.barcode!,
                              style: AppTextStyles.overline(
                                color: isDark
                                    ? AppColors.textDarkTertiary
                                    : AppColors.textLightTertiary,
                                fontSize: 10,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            product.category,
                            style: AppTextStyles.caption(
                              color: accentColor,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${product.price.toStringAsFixed(2)} $_currency',
                          style: AppTextStyles.bodySmall(
                            color: AppColors.success,
                            fontSize: 12,
                          ),
                        ),
                        // ⭐ التكلفة تظهر فقط عند تحديدها (يدوياً أو من شراء)
                        if (product.hasCost) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${LocalizationHelper.inventoryCost} ${product.costPrice!.toStringAsFixed(2)}',
                            style: AppTextStyles.bodySmall(
                              color: isDark
                                  ? AppColors.textDarkTertiary
                                  : AppColors.textLightTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isOutOfStock
                          ? AppColors.errorLight
                          : isLowStock
                              ? AppColors.warningLight
                              : AppColors.successLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${QuantityFormat.quantity(product.quantity)} ${LocalizationHelper.unitLabel(product.unit)}',
                      style: AppTextStyles.caption(
                        color: isOutOfStock
                            ? AppColors.error
                            : isLowStock
                                ? AppColors.warning
                                : AppColors.success,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildActionButton(
                        icon: Icons.edit_rounded,
                        color: accentColor,
                        bgColor: accentColor.withValues(alpha: 0.1),
                        onTap: () => _openProductForm(product: product),
                      ),
                      const SizedBox(width: 4),
                      _buildActionButton(
                        icon: Icons.delete_rounded,
                        color: AppColors.error,
                        bgColor: AppColors.errorLight,
                        onTap: () => _deleteProduct(product),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 17, color: color),
      ),
    );
  }
}