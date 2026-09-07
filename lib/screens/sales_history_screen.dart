// lib/screens/sales_history_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';
import '../models/sale_model.dart';
import '../services/sync_service.dart';
import '../services/database_service.dart';
import '../services/firebase_service.dart';
import '../services/printing_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/design_tokens.dart';
import '../helpers/localization_helper.dart';
import '../helpers/quantity_format.dart';
import '../widgets/app_snackbar.dart';
import '../helpers/sale_search_helper.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key, this.activeTabIndex});

  // ⭐ فهرس التبويب النشط في الشاشة الرئيسية، لمعرفة متى نعود لهذه الشاشة
  final ValueListenable<int>? activeTabIndex;

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final SyncService _sync = SyncService();
  final DatabaseService _db = DatabaseService.instance;
  final FirebaseService _firebase = FirebaseService();
  final Uuid _uuid = const Uuid();

  List<Sale> _sales = [];
  List<Sale> _filteredSales = [];
  bool _isLoading = true;
  bool _isLoadingSales = false;
  String _searchQuery = '';
  Timer? _searchDebounce;
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'all';
  bool _isReturning = false;

  // ⭐ كاش نص البحث الصغير الحروف لكل مبيعة (لتسريع البحث بدل فحص كل عنصر)
  Map<String, String> _searchTextById = {};

  // ⭐ عدد المبيعات والمرتجعات (تُحسب مرة واحدة بعد التحميل بدل كل إعادة بناء)
  int _salesCount = 0;
  int _returnsCount = 0;

  // ⭐ آخر عدد مبيعات تم تحميله (لتجنب إعادة التحميل الكامل عند دخول التبويب)
  int? _lastLoadedSaleCount;

  // ⭐ تقسيم الصفحات: عدد المبيعات المعروضة في كل صفحة
  static const int _pageSize = 8;
  int _visibleCount = _pageSize;

  static const String _currency = 'DZD';


  @override
  void initState() {
    super.initState();
    widget.activeTabIndex?.addListener(_onActiveTabChanged);
    _loadSales();
  }

  @override
  void dispose() {
    widget.activeTabIndex?.removeListener(_onActiveTabChanged);
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ⭐ إعادة التحميل تلقائياً عند الدخول إلى الشاشة (تبويب سجل المبيعات)
  void _onActiveTabChanged() {
    if (!mounted) return;
    if (widget.activeTabIndex?.value != 2) return;

    // ⭐ لا نعيد التحميل الكامل إلا إذا تغيّر عدد المبيعات (جديدة/مرتجعات/حذف)
    final currentCount = _db.getSaleCount();
    if (_sales.isEmpty ||
        _lastLoadedSaleCount == null ||
        currentCount != _lastLoadedSaleCount) {
      _loadSales();
    }
  }

  Future<void> _loadSales() async {
    if (_isLoadingSales) return;
    _isLoadingSales = true;

    // ⭐ نُظهر مؤشر التحميل فقط عند أول دخول، وبعدها تحديث صامت
    final showSpinner = _sales.isEmpty;
    if (showSpinner) setState(() => _isLoading = true);

    try {
      // ⭐ جلب كل المبيعات (بدون سقف) لضمان اكتمال البيانات
      final sales = await _sync.getAllSales();

      if (!mounted) return;
      setState(() {
        _sales = sales;
        _isLoading = false;
      });

      // ⭐ بناء كاش البحث والإحصائيات مرة واحدة بعد التحميل
      _searchTextById = {
        for (final sale in sales) sale.id: buildSaleSearchText(sale),
      };
      var salesCount = 0;
      var returnsCount = 0;
      for (final sale in sales) {
        if (sale.isReturn) {
          returnsCount++;
        } else {
          salesCount++;
        }
      }
      _salesCount = salesCount;
      _returnsCount = returnsCount;
      _lastLoadedSaleCount = sales.length;

      _applyFilters();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppSnackBar.error(context, '${LocalizationHelper.error}: $e');
    } finally {
      _isLoadingSales = false;
    }
  }

  void _applyFilters() {
    final hasActiveFilter =
        _selectedFilter != 'all' || _searchQuery.trim().isNotEmpty;

    // ⭐ بدون فلتر/بحث نستخدم نفس القائمة مباشرة (لا نسخة كاملة ثانية)
    final List<Sale> filtered;
    if (!hasActiveFilter) {
      filtered = _sales;
    } else {
      final query = _searchQuery.toLowerCase().trim();
      filtered = _sales.where((sale) {
        if (_selectedFilter == 'sale' && sale.isReturn) return false;
        if (_selectedFilter == 'return' && !sale.isReturn) return false;

        if (query.isNotEmpty) {
          // ⭐ بحث سريع عبر النص المُعد مسبقاً (بدل تكرار تحويل الأحرف)
          final haystack = _searchTextById[sale.id];
          if (haystack == null || !haystack.contains(query)) return false;
        }

        return true;
      }).toList();
    }

    setState(() {
      // ⭐ عند تغيير البحث/الفلتر نعود للصفحة الأولى
      _visibleCount = _pageSize;
      _filteredSales = filtered;
    });
  }

  Future<void> _processReturn(Sale sale) async {
    // ⭐ منع الإرجاع المزدوج فوراً قبل أي عمليات أخرى
    if (_isReturning) return;
    _isReturning = true;

    void resetGuard() {
      if (mounted) {
        setState(() => _isReturning = false);
      } else {
        _isReturning = false;
      }
    }

    if (!sale.canReturn) {
      _showSnackBar('sales_history.cannot_return'.tr(), AppColors.warning);
      resetGuard();
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    final titleColor =
        isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final bodyColor =
        isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;

    final availableItems = sale.availableForReturn;

    if (availableItems.isEmpty) {
      _showSnackBar('sales_history.all_returned'.tr(), AppColors.warning);
      resetGuard();
      return;
    }

    // ⭐ controllers حقول الكمية والكميات المختارة للعناصر الموزونة
    // (خارج الحوار كي تبقى حالة الكميات عند إعادة بناء الـbuilder)
    final returnQtyControllers = <String, TextEditingController>{};
    final returnSelectedQty = <String, double>{};

    final selectedItems = await showDialog<List<SaleItem>>(
      context: context,
      builder: (ctx) => _buildReturnDialog(
        ctx,
        sale,
        availableItems,
        isDark,
        accentColor,
        titleColor,
        bodyColor,
        returnQtyControllers,
        returnSelectedQty,
      ),
    );

    // ⭐ تحرير controllers بعد إغلاق الحوار
    for (var c in returnQtyControllers.values) {
      c.dispose();
    }

    if (selectedItems == null || selectedItems.isEmpty) {
      resetGuard();
      return;
    }
    if (!mounted) {
      resetGuard();
      return;
    }

    // ⭐ حساب مبلغ الإرجاع بنسبة الخصم والضريبة (منع رد مبلغ أكبر مما دفعه العميل)
    // استخدام remainingTotal (المبلغ الصافي بعد المرتجعات السابقة) بدلاً من total
    final returnSubtotalRaw =
        selectedItems.fold(0.0, (sum, item) => sum + item.subtotal);
    final refundRatio =
        sale.subtotal > 0 ? returnSubtotalRaw / sale.subtotal : 0.0;
    final returnTotal = sale.remainingTotal * refundRatio;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.warning_rounded,
                  color: AppColors.warning, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              LocalizationHelper.salesHistoryReturnTitle,
              style: TextStyle(
                  color: titleColor, fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: Text(
          LocalizationHelper.salesHistoryReturnConfirm
              .replaceAll('{count}', selectedItems.length.toString()),
          style: TextStyle(color: bodyColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(LocalizationHelper.cancel,
                style: TextStyle(color: AppColors.grey500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: isDark ? AppColors.black : AppColors.white,
            ),
            child: Text(LocalizationHelper.confirm),
          ),
        ],
      ),
    );

    if (confirm != true) {
      resetGuard();
      return;
    }
    if (!mounted) {
      resetGuard();
      return;
    }

    // ⭐ مؤشر تقدم أثناء معالجة الإرجاع
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusMd)),
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        child: Container(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: accentColor),
              const SizedBox(height: 16),
              Text(
                LocalizationHelper.salesHistoryReturning,
                style: TextStyle(color: titleColor),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final userId = _db.getUserId();
      if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);

      final returnedItems = selectedItems
          .map((item) => SaleItem(
                id: _uuid.v4(),
                productId: item.productId,
                productName: item.productName,
                price: item.price,
                quantity: item.quantity,
                subtotal: item.subtotal,
              ))
          .toList();

      await _sync.updateSaleWithReturn(
        saleId: sale.id,
        returnedItems: returnedItems,
        returnTotal: returnTotal,
      );

      print('✅ Sale updated with return: ${sale.id}');

      // ⭐ حساب الكميات الجديدة مرة واحدة قبل التحديث المحلي
      final quantityUpdates = <String, double>{};
      for (var item in selectedItems) {
        final product = _db.getProductById(item.productId);
        if (product != null) {
          quantityUpdates[product.id] = product.quantity + item.quantity;
        }
      }

      // ⭐ تحديث كميات المنتجات محلياً أولاً (متوازي)
      await Future.wait(
        quantityUpdates.entries.map((e) => _db.updateQuantity(e.key, e.value)),
      );

      // ⭐ تحديث Firebase بالتوازي (بدلاً من التسلسل البطيء)
      if (_sync.isOnline) {
        final firebaseUpdates = <Future<void>>[];
        for (var entry in quantityUpdates.entries) {
          final product = _db.getProductById(entry.key);
          if (product == null) continue;
          final newQuantity = entry.value;
          firebaseUpdates.add(() async {
            try {
              await _firebase.updateProduct(
                id: product.id,
                name: product.name,
                category: product.category,
                price: product.price,
                quantity: newQuantity,
                description: product.description,
                barcode: product.barcode,
                minStockLevel: product.minStockLevel,
              );
              await _db.markProductAsSynced(product.id);
              print(
                  '✅ Product quantity updated in Firebase: ${product.name} -> $newQuantity');
            } catch (e) {
              print('⚠️ Failed to update product in Firebase: $e');
            }
          }());
        }
        await Future.wait(firebaseUpdates);
      }

      // ⭐ إغلاق مؤشر التقدم
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
      }

      await _loadSales();
      resetGuard();

      _showSnackBar(
        LocalizationHelper.salesHistoryReturnSuccess
            .replaceAll('{count}', selectedItems.length.toString()),
        AppColors.success,
      );
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
      }
      resetGuard();
      _showSnackBar(
        '${LocalizationHelper.salesHistoryReturnError}: $e',
        AppColors.error,
      );
    }
  }

  void _showSnackBar(String message, Color color) {
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
    AppSnackBar.show(context, message, type: type);
  }

  // ⭐ مقتطف آمن لرقم الفاتورة (منع الانهيار مع معرفات قصيرة)
  static String _shortId(String id) =>
      id.length >= 8 ? id.substring(0, 8) : id;

  Widget _buildReturnDialog(
    BuildContext context,
    Sale sale,
    List<SaleItem> availableItems,
    bool isDark,
    Color accentColor,
    Color titleColor,
    Color bodyColor,
    Map<String, TextEditingController> qtyControllers,
    Map<String, double> selectedQtyMap,
  ) {
    // ⭐ المنتجات الموزونة (kg/litre) تسمح بإدخال كمية مرتجعة جزئية
    final Set<String> weightedItemIds = {};
    final Set<String> qtyErrorIds = {};
    for (var item in availableItems) {
      // ⭐ يُعاد بناء الحوار؛ لا تُهمل الكميات التي أدخلها المستخدم
      if (!selectedQtyMap.containsKey(item.id)) {
        selectedQtyMap[item.id] = item.quantity;
      }
      final product = _db.getProductById(item.productId);
      if (product?.isWeighted == true) {
        weightedItemIds.add(item.id);
        // ⭐ قد يُعاد بناء الحوار؛ لا تُنشئ controller جديداً لموجود
        if (!qtyControllers.containsKey(item.id)) {
          qtyControllers[item.id] = TextEditingController(
              text: QuantityFormat.quantity(item.quantity));
        }
      }
    }

    String qtyErrorText(SaleItem item) =>
        '${'sales_history.available_quantity'.tr()}: ${QuantityFormat.quantity(item.quantity)}';

    return StatefulBuilder(
      builder: (ctx, setStateDialog) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusMd)),
          backgroundColor:
              isDark ? AppColors.darkSurface : AppColors.lightSurface,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450, maxHeight: 550),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      LocalizationHelper.salesHistorySelectProducts,
                      style: AppTextStyles.headline4(color: titleColor),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx, null),
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.grey400),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${LocalizationHelper.salesHistorySelectProductsSub} (${availableItems.length})',
                  style: AppTextStyles.bodyMedium(color: bodyColor),
                ),
                const SizedBox(height: 16),
                Divider(
                    color: isDark
                        ? AppColors.grey700.withValues(alpha: 0.3)
                        : AppColors.grey200),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: availableItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final item = availableItems[i];
                      final isWeighted = weightedItemIds.contains(item.id);
                      final isSelected = (selectedQtyMap[item.id] ?? 0) > 0;

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? accentColor.withValues(alpha: 0.06)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                          border: Border.all(
                            color: isSelected
                                ? accentColor.withValues(alpha: 0.3)
                                : (isDark
                                    ? AppColors.grey700.withValues(alpha: 0.3)
                                    : AppColors.grey200),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 36,
                              height: 36,
                              child: Checkbox(
                                value: isSelected,
                                onChanged: (value) {
                                  setStateDialog(() {
                                    // ⭐ التبديل بين الكمية الكاملة والصفر
                                    selectedQtyMap[item.id] =
                                        (value ?? false) ? item.quantity : 0.0;
                                    if (isWeighted) {
                                      qtyControllers[item.id]?.text =
                                          QuantityFormat.quantity(
                                              selectedQtyMap[item.id] ?? 0.0);
                                    }
                                    qtyErrorIds.remove(item.id);
                                  });
                                },
                                activeColor: accentColor,
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      item.productName,
                                      style: AppTextStyles.bodyMedium(
                                          color: titleColor),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          '${'sales_history.available_quantity'.tr()}: ${QuantityFormat.quantity(item.quantity)}',
                                          style: AppTextStyles.caption(
                                              color: bodyColor, fontSize: 10),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          '${item.price.toStringAsFixed(2)} $_currency',
                                          style: AppTextStyles.caption(
                                              color: accentColor, fontSize: 10),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (isWeighted) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 90,
                                child: TextField(
                                  key: Key('return_qty_${item.id}'),
                                  controller: qtyControllers[item.id],
                                  keyboardType: const TextInputType.numberWithOptions(
                                      decimal: true),
                                  inputFormatters: [
                                    TextInputFormatter.withFunction(
                                      (oldValue, newValue) {
                                        final t = newValue.text;
                                        final dotCount =
                                            '.'.allMatches(t).length;
                                        final ok = dotCount <= 1 &&
                                            RegExp(r'^\d*\.?\d{0,3}$')
                                                .hasMatch(t);
                                        return ok ? newValue : oldValue;
                                      },
                                    ),
                                  ],
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.bodyMedium(
                                      color: titleColor),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText:
                                        'sales_history.return_qty_hint'.tr(),
                                    hintStyle: AppTextStyles.caption(
                                        color: AppColors.grey400, fontSize: 9),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 8),
                                    errorText: qtyErrorIds.contains(item.id)
                                        ? qtyErrorText(item)
                                        : null,
                                    errorStyle: AppTextStyles.caption(
                                        color: AppColors.error, fontSize: 9),
                                    errorMaxLines: 2,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          DesignTokens.radiusSm),
                                    ),
                                  ),
                                  onChanged: (text) {
                                    final qty =
                                        QuantityFormat.round(
                                            double.tryParse(text) ?? 0.0);
                                    setStateDialog(() {
                                      selectedQtyMap[item.id] = qty;
                                      qtyErrorIds.remove(item.id);
                                    });
                                  },
                                ),
                              ),
                            ],
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 65,
                              child: Text(
                                item.subtotal.toStringAsFixed(2),
                                style: AppTextStyles.bodyMedium(
                                    color: accentColor, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Divider(
                    color: isDark
                        ? AppColors.grey700.withValues(alpha: 0.3)
                        : AppColors.grey200),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.grey500,
                          side: BorderSide(color: AppColors.grey400),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(DesignTokens.radiusSm)),
                        ),
                        child: Text(LocalizationHelper.cancel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          // ⭐ بناء العناصر المختارة مع التحقق من الكميات
                          final selected = <SaleItem>[];
                          var hasError = false;
                          for (var item in availableItems) {
                            final qty = QuantityFormat.round(
                                selectedQtyMap[item.id] ?? 0.0);
                            if (QuantityFormat.isZeroQty(qty)) continue;
                            if (QuantityFormat.exceedsQty(qty, item.quantity)) {
                              qtyErrorIds.add(item.id);
                              hasError = true;
                              continue;
                            }
                            selected.add(SaleItem(
                              id: item.id,
                              productId: item.productId,
                              productName: item.productName,
                              price: item.price,
                              quantity: qty,
                              subtotal: item.price * qty,
                            ));
                          }
                          if (hasError) {
                            setStateDialog(() {});
                            return;
                          }
                          Navigator.pop(ctx, selected);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          foregroundColor:
                              isDark ? AppColors.black : AppColors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(DesignTokens.radiusSm)),
                        ),
                        child: Text(LocalizationHelper.confirm),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showInvoicePreview(Sale sale) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    final titleColor =
        isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final bodyColor =
        isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;
    final cardBg =
        isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        // ⭐ حالة مشغول: تُبقي الأزرار معطلة أثناء الطباعة/المشاركة
        bool busy = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor:
                  isDark ? AppColors.darkSurface : AppColors.lightSurface,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480, maxHeight: 650),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPreviewHeader(ctx, titleColor, accentColor, isDark),
                    const SizedBox(height: 16),
                    Flexible(
                      child: _buildPreviewBody(
                          sale, isDark, accentColor, titleColor, bodyColor, cardBg),
                    ),
                    const SizedBox(height: 12),
                    _buildPreviewFooter(
                      ctx,
                      sale,
                      busy,
                      isDark,
                      accentColor,
                      bodyColor,
                      (value) => setDialogState(() => busy = value),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handlePreviewPrint(
    Sale sale,
    BuildContext ctx,
    ValueChanged<bool> onBusyChanged,
  ) async {
    onBusyChanged(true);
    try {
      await PrintingService.printSaleInvoice(
        items: sale.items,
        subtotal: sale.subtotal,
        discount: sale.discount,
        tax: sale.tax,
        total: sale.total,
        paymentMethod: sale.paymentMethod,
        saleId: sale.id,
        date: sale.createdAt,
        customerName: sale.customerName,
        customerPhone: sale.customerPhone,
      );
    } catch (e) {
      _showSnackBar(
        e is ReceiptPrintException
            ? e.message
            : '${LocalizationHelper.error}: $e',
        AppColors.error,
      );
    } finally {
      if (ctx.mounted) onBusyChanged(false);
    }
  }

  Future<void> _handlePreviewShare(
    Sale sale,
    BuildContext ctx,
    ValueChanged<bool> onBusyChanged,
  ) async {
    onBusyChanged(true);
    try {
      await PrintingService.shareSaleInvoice(
        items: sale.items,
        subtotal: sale.subtotal,
        discount: sale.discount,
        tax: sale.tax,
        total: sale.total,
        paymentMethod: sale.paymentMethod,
        saleId: sale.id,
        date: sale.createdAt,
        customerName: sale.customerName,
        customerPhone: sale.customerPhone,
      );
    } catch (e) {
      _showSnackBar(
        '${LocalizationHelper.error}: $e',
        AppColors.error,
      );
    } finally {
      if (ctx.mounted) onBusyChanged(false);
    }
  }

  Widget _buildPreviewHeader(
    BuildContext ctx,
    Color titleColor,
    Color accentColor,
    bool isDark,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.infoLight,
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              ),
              child: const Icon(Icons.receipt_long_rounded,
                  color: AppColors.info, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              LocalizationHelper.salesHistoryPreviewTitle,
              style: TextStyle(
                  color: titleColor, fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        IconButton(
          onPressed: () => Navigator.pop(ctx),
          icon: const Icon(Icons.close_rounded, color: AppColors.grey400),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Widget _buildPreviewBody(
    Sale sale,
    bool isDark,
    Color accentColor,
    Color titleColor,
    Color bodyColor,
    Color cardBg,
  ) {
    final hasReturn =
        sale.returnedItems != null && sale.returnedItems!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPreviewHeaderInfo(sale, isDark, accentColor, bodyColor),
          const SizedBox(height: 12),
          Divider(color: accentColor.withValues(alpha: 0.3)),
          const SizedBox(height: 8),
          Flexible(
            child: _buildPreviewProductsList(
                sale, isDark, accentColor, titleColor, bodyColor),
          ),
          const SizedBox(height: 12),
          Divider(color: accentColor.withValues(alpha: 0.3)),
          const SizedBox(height: 8),
          _buildPreviewTotals(sale, isDark, accentColor, bodyColor),
          if (hasReturn) _buildPreviewReturnBadge(sale),
        ],
      ),
    );
  }

  Widget _buildPreviewHeaderInfo(
    Sale sale,
    bool isDark,
    Color accentColor,
    Color bodyColor,
  ) {
    return Column(
      children: [
        Center(
          child: Text(
            LocalizationHelper.appName,
            style: TextStyle(
              color: accentColor,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Center(
          child: Text(
            LocalizationHelper.appTagline,
            style: AppTextStyles.caption(
              color: isDark
                  ? AppColors.textDarkTertiary
                  : AppColors.textLightTertiary,
              fontSize: 10,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Divider(color: accentColor.withValues(alpha: 0.3)),
        const SizedBox(height: 8),
        _buildReceiptRow(LocalizationHelper.salesHistoryDate,
            _formatDateTime(sale.createdAt), bodyColor),
        const SizedBox(height: 4),
        _buildReceiptRow(LocalizationHelper.salesHistoryPayment,
            LocalizationHelper.paymentMethod(sale.paymentMethod), bodyColor),
        const SizedBox(height: 4),
        _buildReceiptRow(LocalizationHelper.salesHistoryInvoice,
            '#${_shortId(sale.id).toUpperCase()}', bodyColor),
        if (sale.customerName != null && sale.customerName!.isNotEmpty)
          _buildReceiptRow(LocalizationHelper.salesHistoryCustomer,
              sale.customerName!, bodyColor),
        if (sale.returnedItems != null && sale.returnedItems!.isNotEmpty)
          _buildReceiptRow(
            'sales_history.return_total'.tr(),
            '${sale.returnTotal?.toStringAsFixed(2)} $_currency',
            AppColors.warning,
          ),
        if (sale.isFullyReturned)
          _buildReceiptRow(
            'sales_history.status'.tr(),
            'sales_history.fully_returned'.tr(),
            AppColors.warning,
          ),
      ],
    );
  }

  Widget _buildPreviewProductsList(
    Sale sale,
    bool isDark,
    Color accentColor,
    Color titleColor,
    Color bodyColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${LocalizationHelper.posProductsTitle} (${sale.items.length})',
          style: AppTextStyles.bodyMedium(color: titleColor, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: sale.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final item = sale.items[i];
              final isReturned = sale.returnedItems
                      ?.any((r) => r.productId == item.productId) ??
                  false;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isReturned
                          ? AppColors.warning.withValues(alpha: 0.2)
                          : accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      QuantityFormat.quantity(item.quantity),
                      style: AppTextStyles.caption(
                        color: isReturned ? AppColors.warning : accentColor,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      isReturned
                          ? '${item.productName} (${'sales_history.returned'.tr()})'
                          : item.productName,
                      style: AppTextStyles.bodySmall(
                        color: isReturned ? AppColors.warning : bodyColor,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${item.subtotal.toStringAsFixed(2)} $_currency',
                      style: AppTextStyles.bodySmall(
                        color: isReturned ? AppColors.warning : accentColor,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewTotals(
    Sale sale,
    bool isDark,
    Color accentColor,
    Color bodyColor,
  ) {
    return Column(
      children: [
        _buildReceiptRow(LocalizationHelper.salesHistorySubtotal,
            '${sale.subtotal.toStringAsFixed(2)} $_currency', bodyColor),
        if (sale.discount > 0) ...[
          const SizedBox(height: 4),
          _buildReceiptRow(
              LocalizationHelper.salesHistoryDiscount,
              '-${sale.discount.toStringAsFixed(2)} $_currency',
              AppColors.error),
        ],
        if (sale.tax > 0) ...[
          const SizedBox(height: 4),
          _buildReceiptRow(LocalizationHelper.salesHistoryTax,
              '${sale.tax.toStringAsFixed(2)} $_currency', bodyColor),
        ],
        if (sale.returnTotal != null && sale.returnTotal! > 0) ...[
          const SizedBox(height: 4),
          _buildReceiptRow(
            'sales_history.return_total'.tr(),
            '-${sale.returnTotal!.toStringAsFixed(2)} $_currency',
            AppColors.warning,
          ),
          const SizedBox(height: 4),
          _buildReceiptRow(
            'sales_history.remaining_amount'.tr(),
            '${sale.remainingTotal.toStringAsFixed(2)} $_currency',
            accentColor,
            isBold: true,
          ),
        ],
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: accentColor, width: 2)),
          ),
        ),
        _buildReceiptRow(LocalizationHelper.salesHistoryTotalAmount,
            '${sale.total.toStringAsFixed(2)} $_currency', accentColor,
            isBold: true),
      ],
    );
  }

  Widget _buildPreviewReturnBadge(Sale sale) {
    final isFullyReturned = sale.isFullyReturned;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isFullyReturned ? AppColors.errorLight : AppColors.warningLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isFullyReturned
              ? AppColors.error.withValues(alpha: 0.3)
              : AppColors.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFullyReturned ? Icons.check_circle_rounded : Icons.reply_rounded,
            color: isFullyReturned ? AppColors.error : AppColors.warning,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            isFullyReturned
                ? 'sales_history.fully_returned'.tr()
                : 'sales_history.partially_returned'.tr(),
            style: AppTextStyles.caption(
              color: isFullyReturned ? AppColors.error : AppColors.warning,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewFooter(
    BuildContext ctx,
    Sale sale,
    bool busy,
    bool isDark,
    Color accentColor,
    Color bodyColor,
    ValueChanged<bool> onBusyChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => _handlePreviewShare(sale, ctx, onBusyChanged),
            icon: Icon(Icons.share_rounded,
                size: 16, color: busy ? AppColors.grey400 : accentColor),
            label: Text(
              LocalizationHelper.posInvoiceShare,
              style: TextStyle(
                fontSize: 11,
                color: busy ? AppColors.grey400 : accentColor,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: accentColor,
              side: BorderSide(
                  color: accentColor.withValues(alpha: busy ? 0.2 : 0.4)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: busy
                ? null
                : () => _handlePreviewPrint(sale, ctx, onBusyChanged),
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_rounded, size: 16),
            label: Text(
              LocalizationHelper.posInvoicePrint,
              style: const TextStyle(fontSize: 11),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: isDark ? AppColors.black : AppColors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: busy ? null : () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.grey500,
              side: const BorderSide(color: AppColors.grey400),
              padding: const EdgeInsets.symmetric(vertical: 10),
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm)),
            ),
            child: Text(
              LocalizationHelper.profileClose,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptRow(String label, String value, Color color,
      {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          flex: 1,
          child: Text(
            label,
            style: (isBold
                    ? AppTextStyles.bodyLarge(color: color)
                    : AppTextStyles.bodySmall(color: color))
                .copyWith(fontSize: isBold ? 15 : 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 2,
          child: Text(
            value,
            style: (isBold
                    ? AppTextStyles.bodyLarge(color: color)
                    : AppTextStyles.bodySmall(color: color))
                .copyWith(fontSize: isBold ? 15 : 12),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    final titleColor =
        isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final bodyColor =
        isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          LocalizationHelper.salesHistoryTitle,
          style: AppTextStyles.headline4(color: titleColor),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadSales,
            tooltip: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
            icon: Icon(Icons.refresh_rounded, color: accentColor),
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState(accentColor, bodyColor)
          : Column(
              children: [
                _buildSearchBar(),
                const SizedBox(height: 12),
                _buildFilterRow(accentColor, isDark),
                const SizedBox(height: 12),
                _buildStatsRow(bodyColor, isDark),
                const SizedBox(height: 8),
                Expanded(
                  child: _filteredSales.isEmpty
                      ? _buildEmptyState(accentColor, bodyColor, isDark,
                          noResults: _sales.isNotEmpty)
                      : RefreshIndicator(
                          onRefresh: _loadSales,
                          color: accentColor,
                          child: ListView.separated(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              8,
                              16,
                              MediaQuery.of(context).padding.bottom + 120,
                            ),
                            itemCount: _filteredSales.length <= _visibleCount
                                ? _filteredSales.length
                                : _visibleCount + 1,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              if (i == _visibleCount) {
                                return _buildLoadMoreItem(
                                    accentColor, bodyColor, isDark);
                              }
                              final sale = _filteredSales[i];
                              return _buildSaleCard(
                                sale,
                                isDark,
                                accentColor,
                                titleColor,
                                bodyColor,
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildLoadingState(Color accentColor, Color bodyColor) {
    return Center(
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
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(AppConfig.salesHistorySearchDebounce, () {
      if (!mounted) return;
      _searchQuery = value;
      _applyFilters();
    });
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: LocalizationHelper.salesHistorySearchHint,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow(Color accentColor, bool isDark) {
    final List<Map<String, String>> filters = [
      {'key': 'all', 'label': LocalizationHelper.salesHistoryFilterAll},
      {'key': 'sale', 'label': LocalizationHelper.salesHistoryFilterSales},
      {'key': 'return', 'label': LocalizationHelper.salesHistoryFilterReturns},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: filters.map((option) {
          final isSelected = _selectedFilter == option['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                _selectedFilter = option['key']!;
                _applyFilters();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accentColor
                      : (isDark
                          ? AppColors.darkSurfaceAlt
                          : AppColors.lightSurfaceAlt),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? accentColor
                        : (isDark
                            ? AppColors.grey700.withValues(alpha: 0.3)
                            : AppColors.grey300),
                    width: isSelected ? 0 : 1,
                  ),
                ),
                child: Text(
                  option['label']!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? (isDark ? AppColors.black : AppColors.white)
                        : (isDark
                            ? AppColors.textDarkSecondary
                            : AppColors.textLightSecondary),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatsRow(Color bodyColor, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${LocalizationHelper.salesHistoryTotal}: $_shownCount / ${_filteredSales.length}',
            style: AppTextStyles.bodyMedium(color: bodyColor),
          ),
          Flexible(
            child: Text(
              '$_salesCount ${LocalizationHelper.salesHistorySales} • $_returnsCount ${LocalizationHelper.salesHistoryReturns}',
              textAlign: TextAlign.end,
              style: AppTextStyles.caption(
                color: isDark
                    ? AppColors.textDarkTertiary
                    : AppColors.textLightTertiary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color accentColor, Color bodyColor, bool isDark,
      {bool noResults = false}) {
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
              noResults ? Icons.search_off_rounded : Icons.receipt_long_rounded,
              size: 56,
              color: isDark
                  ? AppColors.textDarkTertiary
                  : AppColors.textLightTertiary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            noResults
                ? LocalizationHelper.salesHistoryNoResults
                : LocalizationHelper.salesHistoryEmpty,
            style: AppTextStyles.bodyLarge(color: bodyColor),
          ),
          const SizedBox(height: 6),
          Text(
            noResults
                ? LocalizationHelper.salesHistoryNoResultsSub
                : LocalizationHelper.salesHistoryEmptySub,
            style: AppTextStyles.bodySmall(
              color: isDark
                  ? AppColors.textDarkTertiary
                  : AppColors.textLightTertiary,
            ),
          ),
        ],
      ),
    );
  }

  int get _shownCount => _filteredSales.length <= _visibleCount
      ? _filteredSales.length
      : _visibleCount;

  void _loadMore() {
    setState(() {
      _visibleCount = (_visibleCount + _pageSize < _filteredSales.length)
          ? _visibleCount + _pageSize
          : _filteredSales.length;
    });
  }

  Widget _buildLoadMoreItem(Color accentColor, Color bodyColor, bool isDark) {
    final remaining = _filteredSales.length - _visibleCount;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: OutlinedButton.icon(
        onPressed: _loadMore,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
        label: Text(
          '${LocalizationHelper.salesHistoryLoadMore} ($remaining)',
          style: const TextStyle(fontSize: 12),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: accentColor,
          side: BorderSide(color: accentColor.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(vertical: 10),
          minimumSize: const Size(double.infinity, 40),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm)),
        ),
      ),
    );
  }

  Widget _buildSaleCard(
    Sale sale,
    bool isDark,
    Color accentColor,
    Color titleColor,
    Color bodyColor,
  ) {
    final isReturn = sale.isReturn;
    final hasReturn =
        sale.returnedItems != null && sale.returnedItems!.isNotEmpty;
    final isFullyReturned = sale.isFullyReturned;

    final cardColor = isReturn || isFullyReturned
        ? AppColors.warningLight.withValues(alpha: isDark ? 0.15 : 0.3)
        : hasReturn
            ? AppColors.infoLight.withValues(alpha: isDark ? 0.1 : 0.2)
            : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt);

    return Card(
      margin: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          border: Border.all(
            color: isReturn || isFullyReturned
                ? AppColors.warning.withValues(alpha: 0.3)
                : hasReturn
                    ? AppColors.info.withValues(alpha: 0.3)
                    : (isDark
                        ? AppColors.grey700.withValues(alpha: 0.3)
                        : AppColors.grey200.withValues(alpha: 0.5)),
            width: (isReturn || isFullyReturned) ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCardHeader(sale, isReturn, hasReturn, isFullyReturned,
                  isDark, accentColor, titleColor),
              const SizedBox(height: 8),
              _buildCardProducts(sale, accentColor, bodyColor, hasReturn),
              const SizedBox(height: 8),
              _buildCardFooter(sale, isReturn, accentColor),
              const SizedBox(height: 10),
              _buildCardButtons(sale, isReturn, isDark, accentColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardHeader(
    Sale sale,
    bool isReturn,
    bool hasReturn,
    bool isFullyReturned,
    bool isDark,
    Color accentColor,
    Color titleColor,
  ) {
    String statusText = '';
    Color statusColor = accentColor;
    IconData statusIcon =
        isReturn ? Icons.reply_rounded : Icons.receipt_long_rounded;

    if (isReturn) {
      statusText = LocalizationHelper.salesHistoryReturn;
      statusColor = AppColors.warning;
    } else if (isFullyReturned) {
      statusText = 'sales_history.fully_returned'.tr();
      statusColor = AppColors.error;
    } else if (hasReturn) {
      statusText = 'sales_history.partially_returned'.tr();
      statusColor = AppColors.info;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                statusIcon,
                color: statusColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${_shortId(sale.id).toUpperCase()}',
                  style: AppTextStyles.bodyMedium(color: titleColor),
                ),
                if (statusText.isNotEmpty)
                  Text(
                    statusText,
                    style: AppTextStyles.caption(
                      color: statusColor,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ],
        ),
        Text(
          _formatDate(sale.createdAt),
          style: AppTextStyles.caption(
            color: isDark
                ? AppColors.textDarkTertiary
                : AppColors.textLightTertiary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildCardProducts(
    Sale sale,
    Color accentColor,
    Color bodyColor,
    bool hasReturn,
  ) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: sale.items.map((item) {
        final isReturned = hasReturn &&
            (sale.returnedItems?.any((r) => r.productId == item.productId) ??
                false);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isReturned
                ? AppColors.warning.withValues(alpha: 0.15)
                : accentColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            isReturned
                ? '${item.productName} (${QuantityFormat.quantity(item.quantity)}) ✕ ${'sales_history.returned'.tr()}'
                : '${item.productName} (${QuantityFormat.quantity(item.quantity)})',
            style: AppTextStyles.caption(
              color: isReturned ? AppColors.warning : bodyColor,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCardFooter(
    Sale sale,
    bool isReturn,
    Color accentColor,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  LocalizationHelper.paymentMethod(sale.paymentMethod),
                  style: AppTextStyles.caption(
                      color: AppColors.success, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (sale.customerName != null && sale.customerName!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.infoLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      sale.customerName!,
                      style: AppTextStyles.caption(
                          color: AppColors.info, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              if (sale.returnTotal != null && sale.returnTotal! > 0) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warningLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${'sales_history.return_total'.tr()}: ${sale.returnTotal!.toStringAsFixed(2)}',
                      style: AppTextStyles.caption(
                          color: AppColors.warning, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${sale.total.toStringAsFixed(2)} $_currency',
          style: AppTextStyles.bodyLarge(
            color: isReturn ? AppColors.warning : accentColor,
          ),
        ),
      ],
    );
  }

  Widget _buildCardButtons(
    Sale sale,
    bool isReturn,
    bool isDark,
    Color accentColor,
  ) {
    final canReturn = sale.canReturn && !isReturn;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: canReturn ? () => _processReturn(sale) : null,
            icon: Icon(
              Icons.reply_rounded,
              size: 16,
              color: canReturn ? AppColors.warning : AppColors.grey400,
            ),
            label: Text(
              isReturn || !canReturn
                  ? LocalizationHelper.salesHistoryReturn
                  : LocalizationHelper.salesHistoryReturnProduct,
              style: TextStyle(
                fontSize: 11,
                color: canReturn ? AppColors.warning : AppColors.grey400,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  canReturn ? AppColors.warning : AppColors.grey400,
              side: BorderSide(
                color: canReturn
                    ? AppColors.warning.withValues(alpha: 0.5)
                    : AppColors.grey400,
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
              minimumSize: const Size(0, 34),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _showInvoicePreview(sale),
            icon: const Icon(Icons.visibility_rounded, size: 16),
            label: Text(
              LocalizationHelper.salesHistoryPreview,
              style: const TextStyle(fontSize: 11),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: isDark ? AppColors.black : AppColors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
              minimumSize: const Size(0, 34),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }
}
