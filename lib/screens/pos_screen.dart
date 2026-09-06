// lib/screens/pos_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';
import '../models/product_model.dart';
import '../models/cart_item_model.dart';
import '../models/sale_model.dart';
import '../services/database_service.dart';
import '../services/cart_service.dart';
import '../services/sync_service.dart';
import '../services/firebase_service.dart';
import '../services/scanner_feedback_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/design_tokens.dart';
import '../helpers/localization_helper.dart';
import '../widgets/barcode_scanner_view.dart';
import '../widgets/pos/checkout_confirmation_sheet.dart';
import '../widgets/pos/held_orders.dart';
import '../widgets/pos/invoice_options_dialog.dart';
import '../widgets/pos/payment_method_sheet.dart';
import '../widgets/pos/product_grid_item.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/customers/customer_picker_sheet.dart';

class POSScreen extends StatefulWidget {
  const POSScreen({super.key});

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen> with WidgetsBindingObserver {
  final DatabaseService _db = DatabaseService.instance;
  final SyncService _sync = SyncService();
  final FirebaseService _firebase = FirebaseService();
  final Uuid _uuid = const Uuid();

  List<Product> _products = [];
  String _searchQuery = '';
  String _selectedCategory = 'All';
  List<String> _categories = ['All'];
  bool _isLoadingProducts = true;

  bool _isScannerVisible = false;
  bool _isProcessingBarcode = false;

  final FocusNode _searchFocusNode = FocusNode();

  static const String _currency = 'DZD';

  @override
  void initState() {
    super.initState();
    _loadProductsSilently();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadProductsSilently() async {
    try {
      final products = await _sync.getAllProducts();
      final categories = await _sync.getCategories();

      if (!mounted) return;

      // ⭐ نتجنب إعادة بناء القائمة المفلترة إذا لم تتغير البيانات فعلياً
      final changed = !_sameProducts(_products, products) ||
          _selectedCategory != 'All';
      if (!changed && _filteredProducts.isNotEmpty) return;

      setState(() {
        _products = products;
        _categories = ['All', ...categories];
        _isLoadingProducts = false;
        _rebuildFilteredProducts();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingProducts = false);
      AppConfig.logError('Error loading products', e);
    }
  }

  bool _sameProducts(List<Product> a, List<Product> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].quantity != b[i].quantity ||
          a[i].price != b[i].price ||
          !a[i].updatedAt.isAtSameMomentAs(b[i].updatedAt)) {
        return false;
      }
    }
    return true;
  }

  void _dismissKeyboard() {
    _searchFocusNode.unfocus();
  }

  List<Product> _filteredProducts = [];
  Timer? _searchDebounce;
  final TextEditingController _searchController = TextEditingController();

  void _rebuildFilteredProducts() {
    final query = _searchQuery.toLowerCase();
    _filteredProducts = _products.where((product) {
      if (_selectedCategory != 'All' && product.category != _selectedCategory) {
        return false;
      }
      if (query.isNotEmpty) {
        return product.name.toLowerCase().contains(query) ||
            product.category.toLowerCase().contains(query) ||
            (product.barcode?.toLowerCase().contains(query) ?? false);
      }
      return true;
    }).toList();
  }

  void _updateSearchQuery(String value) {
    _searchDebounce?.cancel();
    // ⭐ لا نعيد بناء الشاشة كاملة مع كل حرف؛ ننتظر debounce ثم نحدّث القائمة
    _searchDebounce = Timer(AppConfig.posSearchDebounce, () {
      if (!mounted) return;
      setState(() {
        _searchQuery = value;
        _rebuildFilteredProducts();
      });
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _rebuildFilteredProducts();
    });
    _searchFocusNode.unfocus();
  }

  // ==================== Scanner Methods ====================

  void _toggleScanner() {
    _dismissKeyboard();
    setState(() => _isScannerVisible = !_isScannerVisible);
  }

  Future<void> _onBarcodeDetected(String barcode) async {
    if (_isProcessingBarcode) return;

    _isProcessingBarcode = true;

    try {
      Product? product = _db.getProductByBarcode(barcode);

      if (product == null && _sync.isOnline) {
        try {
          product = await _firebase.getProductByBarcode(barcode);
        } catch (e) {
          AppConfig.logError('Error fetching product from Firebase', e);
        }
      }

      if (product != null && mounted) {
        // ⭐ اهتزاز متوسط عند العثور على المنتج
        ScannerFeedbackService.productFound();
        if (product.quantity > 0) {
          context.read<CartService>().addProduct(product);
          _showSnackBar('${product.name} ${LocalizationHelper.posAdded}',
              AppColors.success);
          _loadProductsSilently();
        } else {
          _showSnackBar('${product.name} ${LocalizationHelper.posOutOfStock}!',
              AppColors.error);
        }
      } else if (mounted) {
        // ⭐ اهتزاز قوي عند عدم العثور على المنتج
        ScannerFeedbackService.productNotFound();
        _showAddProductDialog(barcode);
      }
    } catch (e) {
      AppConfig.logError('Error processing barcode', e);
      if (mounted) {
        // ⭐ فشل حقيقي في البحث (شبكة/قاعدة بيانات): نعرض خطأ ولا نفتح نافذة
        // "إضافة منتج جديد" (منع تكرار المنتجات بسبب خطأ تقني)
        ScannerFeedbackService.productNotFound();
        _showSnackBar(LocalizationHelper.posScanError, AppColors.error);
      }
    } finally {
      _isProcessingBarcode = false;
    }
  }

  void _showAddProductDialog(String barcode) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final bodyColor =
        isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusMd)),
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
              ),
              child: const Icon(Icons.search_off_rounded,
                  color: AppColors.warning, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              LocalizationHelper.posProductNotFound,
              style: TextStyle(
                color: titleColor,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Text(
          '${LocalizationHelper.posBarcode} "$barcode" ${LocalizationHelper.posAddAsNew}',
          style: TextStyle(color: bodyColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              LocalizationHelper.cancel,
              style: TextStyle(color: AppColors.grey500),
            ),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _onBarcodeDetected(barcode); // Retry scan
            },
            child: Text(
              LocalizationHelper.posRetryScan,
              style: TextStyle(color: AppColors.primary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openAddProductForm(barcode);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
            ),
            child: Text(LocalizationHelper.posAddNew),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddProductForm(String barcode) async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final costController = TextEditingController();
    final quantityController = TextEditingController(text: '1');
    final formKey = GlobalKey<FormState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    final titleColor =
        isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusLg)),
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(20),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        LocalizationHelper.posAddProduct,
                        style: AppTextStyles.headline4(color: titleColor),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded,
                            color: AppColors.grey400),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${LocalizationHelper.posBarcode}: $barcode',
                    style: AppTextStyles.bodyMedium(color: AppColors.grey500),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: LocalizationHelper.posProductName,
                      prefixIcon:
                          const Icon(Icons.inventory_2_rounded, size: 20),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? LocalizationHelper.inventoryNameRequired
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: priceController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText:
                                '${LocalizationHelper.posPrice} ($_currency)',
                            prefixIcon: const Icon(Icons.attach_money_rounded,
                                size: 20),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty)
                              return LocalizationHelper.inventoryPriceRequired;
                            if (double.tryParse(v) == null)
                              return LocalizationHelper.error;
                            if (double.tryParse(v)! <= 0)
                              return LocalizationHelper.error;
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: quantityController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: LocalizationHelper.posQuantity,
                            prefixIcon: const Icon(
                                Icons.production_quantity_limits,
                                size: 20),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty)
                              return LocalizationHelper.inventoryQuantityRequired;
                            if (int.tryParse(v) == null)
                              return LocalizationHelper.error;
                            if (int.tryParse(v)! <= 0)
                              return LocalizationHelper.error;
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // ⭐ سعر الشراء (اختياري)
                  TextFormField(
                    controller: costController,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      labelText:
                          '${LocalizationHelper.inventoryCostPrice} ($_currency)',
                      prefixIcon:
                          const Icon(Icons.shopping_bag_rounded, size: 20),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final value = double.tryParse(v.trim());
                      if (value == null || value < 0) {
                        return LocalizationHelper.error;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (formKey.currentState!.validate()) {
                          Navigator.pop(ctx);
                          final costText = costController.text.trim();
                          final cost = costText.isEmpty
                              ? null
                              : double.tryParse(costText);
                          await _addNewProductFromPOS(
                            name: nameController.text,
                            price: double.parse(priceController.text),
                            quantity: int.parse(quantityController.text),
                            barcode: barcode,
                            costPrice:
                                (cost != null && cost > 0) ? cost : null,
                          );
                        }
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(LocalizationHelper.posAdd),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor:
                            isDark ? AppColors.black : AppColors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    nameController.dispose();
    priceController.dispose();
    costController.dispose();
    quantityController.dispose();
  }

  Future<void> _addNewProductFromPOS({
    required String name,
    required double price,
    required int quantity,
    required String barcode,
    double? costPrice,
  }) async {
    // ⭐ مؤشر تحميل أثناء إضافة المنتج (يُغلق عند الانتهاء أو الفشل)
    showPosProcessingDialog(context);
    try {
      final userId = _db.getUserId();
      if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);

      final productId = _uuid.v4();

      // ⭐ Offline First: حفظ في Hive أولاً (isSynced = false)
      await _db.addProductWithId(
        id: productId,
        name: name,
        category: 'General',
        price: price,
        quantity: quantity,
        barcode: barcode.isNotEmpty ? barcode : null,
        userId: userId,
        costPrice: costPrice,
        isSynced: false,
      );

      // ⭐ محاولة المزامنة مع Firebase إذا كان هناك اتصال
      if (_sync.isOnline) {
        try {
          await _firebase.addProduct(
            id: productId,
            name: name,
            category: 'General',
            price: price,
            quantity: quantity,
            barcode: barcode.isNotEmpty ? barcode : null,
            costPrice: costPrice,
          );
          await _db.markProductAsSynced(productId);
          AppConfig.log('Product synced to Firebase: $name');
        } catch (e) {

          AppConfig.logError('Failed to sync product to Firebase', e);
          // ⭐ ستبقى isSynced = false وسيتم رفعها في المزامنة القادمة
        }
      }

      await _loadProductsSilently();

      final product = _db.getProductById(productId);
      if (product != null && mounted) {
        context.read<CartService>().addProduct(product);
      }

      // ⭐ إغلاق مؤشر التحميل
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
      }

      if (mounted && product != null) {
        _showSnackBar(LocalizationHelper.posProductAdded, AppColors.success);
      }
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        _showSnackBar(
          '${LocalizationHelper.error} ${LocalizationHelper.posAddProduct}',
          AppColors.error,
        );
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    // ⭐ توحيد التنبيهات عبر AppSnackBar مع الحفاظ على نفس التوقيع
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
      duration: const Duration(seconds: 2),
    );
  }

  // ==================== Checkout ====================

  void _processCheckout(CartService cart) {
    showPaymentMethodSheet(
      context,
      cart: cart,
      onCash: () {
        cart.setPaymentMethod('Cash');
        _openCheckoutConfirmation(cart);
      },
      onCard: () {
        cart.setPaymentMethod('Edahabia/CIB');
        _openCheckoutConfirmation(cart);
      },
      onDebt: () => _startDebtCheckout(cart),
    );
  }

  void _openCheckoutConfirmation(
    CartService cart, {
    String? customerId,
    double paidNow = 0.0,
  }) {
    showCheckoutConfirmationSheet(
      context,
      cart: cart,
      db: _db,
      onError: (message) => _showSnackBar(message, AppColors.error),
      onConfirm: () =>
          _confirmSale(cart, customerId: customerId, paidNow: paidNow),
    );
  }

  /// مسار البيع بالدين: اختيار العميل ثم المبلغ المدفوع الآن ثم التأكيد.
  Future<void> _startDebtCheckout(CartService cart) async {
    final customer = await showCustomerPickerSheet(context);
    if (customer == null || !mounted) return;

    cart.setPaymentMethod('Debt');
    cart.setCustomer(customer.name, customer.id);

    final paidNow = await _showPaidNowDialog(context, cart.total);
    if (!mounted) return;

    _openCheckoutConfirmation(
      cart,
      customerId: customer.id,
      paidNow: paidNow ?? 0.0,
    );
  }

  // ==================== Confirm Sale ====================

  Future<void> _confirmSale(CartService cart, {String? customerId, double paidNow = 0.0}) async {
                        final itemsCopy = List<CartItem>.from(cart.items);
                        final subtotalCopy = cart.subtotal;
                        final discountCopy = cart.discount;
                        final taxCopy = cart.taxAmount;
                        final taxRateCopy = cart.taxRate;
                        final totalCopy = cart.total;
                        final paymentMethodCopy = cart.paymentMethod;
                        final dateCopy = DateTime.now();

                        showPosProcessingDialog(context);

                        try {
                          final userId = _db.getUserId();
                          if (userId == null || userId.isEmpty) {
                            throw Exception(LocalizationHelper.posLoginAgain);
                          }

                          final saleItems = itemsCopy
                              .map((item) => SaleItem(
                                    id: _uuid.v4(),
                                    productId: item.product.id,
                                    productName: item.product.name,
                                    price: item.product.price,
                                    quantity: item.quantity,
                                    subtotal: item.subtotal,
                                  ))
                              .toList();

                          // ⭐ Offline First: تحديث الكميات في Hive أولاً (isSynced = false)
                          AppConfig.log('Updating product quantities in Hive...');
                          for (var item in itemsCopy) {
                            final product = _db.getProductById(item.product.id);
                            if (product != null) {
                              final newQuantity =
                                  product.quantity - item.quantity;
                              await _db.updateQuantity(product.id, newQuantity);
                            }
                          }

                          // ⭐ Offline First: إضافة المبيعة إلى Hive (isSynced = false)
                          AppConfig.log('Adding sale to Hive...');
                          final sale = await _sync.addSale(
                            items: saleItems,
                            subtotal: subtotalCopy,
                            discount: discountCopy,
                            tax: taxCopy,
                            total: totalCopy,
                            paymentMethod: paymentMethodCopy,
                            customerId: customerId,
                            paidNow: paidNow,
                          );
                          AppConfig.log('Sale saved to Hive: ${sale.id}');

                          // ⭐ Offline First: محاولة المزامنة الفورية (إذا كان هناك اتصال)
                          // لا ننتظرها حتى لا تتأخر شاشة إتمام البيع على الشبكات البطيئة
                          if (_sync.isOnline) {
                            _sync.syncNow().catchError((e) {
                              AppConfig.logError('Immediate sync failed', e);
                              // ⭐ سيتم المزامنة في الخلفية لاحقاً
                            });
                          }

                          cart.clearCart();
                          await _loadProductsSilently();

                          try {
                            Navigator.pop(context);
                          } catch (_) {}

                          showInvoiceOptionsDialog(
                            context,
                            items: itemsCopy,
                            subtotal: subtotalCopy,
                            discount: discountCopy,
                            tax: taxCopy,
                            taxRate: taxRateCopy,
                            total: totalCopy,
                            paymentMethod: paymentMethodCopy,
                            saleId: sale.id,
                            date: dateCopy,
                            showSnackBar: _showSnackBar,
                          );

                          if (mounted) {
                            _showSnackBar(LocalizationHelper.posSaleCompleted,
                                AppColors.success);
                          }
                        } catch (e) {
                          try {
                            Navigator.pop(context);
                          } catch (_) {}

                          AppConfig.logError('Error completing sale', e);
                          if (mounted) {
                            _showSnackBar(
                              '${LocalizationHelper.error} ${LocalizationHelper.posCompleteSale}',
                              AppColors.error,
                            );
                          }
                        }
  }

  Future<double?> _showPaidNowDialog(BuildContext context, double total) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(LocalizationHelper.customersPaidNow,
          style: AppTextStyles.titleLarge(color: isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(LocalizationHelper.customersCredit,
                style: AppTextStyles.bodyMedium(color: isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '${LocalizationHelper.customersPaymentAmount} (0 - ${total.toStringAsFixed(2)})',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final val = double.tryParse(v);
                  if (val == null) {
                    return LocalizationHelper.posPaidNowInvalidNumber;
                  }
                  if (val < 0) return LocalizationHelper.posPaidNowNegative;
                  if (val > total) {
                    return LocalizationHelper.posPaidNowExceedsTotal(
                        total.toStringAsFixed(2));
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0.0),
            child: Text(LocalizationHelper.posPaidNowPayLater),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final val = double.tryParse(controller.text);
                Navigator.pop(ctx, (val != null && val > 0) ? val : 0.0);
              }
            },
            child: Text(LocalizationHelper.posPaidNowConfirm),
          ),
        ],
      ),
    );
    return result;
  }

  // ==================== Cart Preview ====================

  Widget _buildCartPreview(BuildContext context, CartService cart) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(color: accentColor.withValues(alpha:0.4), width: 2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha:0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
                    ),
                    child: Icon(Icons.shopping_cart_rounded,
                        color: accentColor, size: 14),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${LocalizationHelper.posCart} (${cart.totalItems})',
                    style: AppTextStyles.bodyMedium(),
                  ),
                ],
              ),
              Text(
                '${cart.total.toStringAsFixed(2)} $_currency',
                style: AppTextStyles.bodyLarge(color: accentColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cart.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final item = cart.items[i];
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha:0.06),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
                    border: Border.all(color: accentColor.withValues(alpha:0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => cart.decrementQuantity(i),
                          child: Center(
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha:0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.remove_rounded,
                                  size: 14, color: AppColors.error),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${item.product.name} x${item.quantity}',
                        style: AppTextStyles.caption(fontSize: 10),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => cart.incrementQuantity(i),
                          child: Center(
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha:0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.add_rounded,
                                  size: 14, color: AppColors.success),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => showHoldOrderDialog(context,
                      cart: cart,
                      currency: _currency,
                      showSnackBar: _showSnackBar),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    side: const BorderSide(color: AppColors.warning),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(
                    LocalizationHelper.posHold,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () => _processCheckout(cart),
                  icon: const Icon(Icons.payment_rounded, size: 14),
                  label: Text(
                    '${LocalizationHelper.posCheckout} ${cart.total.toStringAsFixed(2)} $_currency',
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: isDark ? AppColors.black : AppColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    minimumSize: const Size(0, 36),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== Cart Dialog ====================

  void _showCartDialog(BuildContext context, CartService cart) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    final titleColor =
        isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final bodyColor =
        isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 650),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Consumer<CartService>(
            builder: (ctx, cart, child) {
              if (cart.items.isEmpty) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shopping_cart_rounded,
                        size: 60, color: AppColors.grey300),
                    const SizedBox(height: 12),
                    Text(
                      LocalizationHelper.posEmptyCart,
                      style: AppTextStyles.bodyLarge(color: bodyColor),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(LocalizationHelper.posStartShopping),
                    ),
                  ],
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        LocalizationHelper.posCart,
                        style: AppTextStyles.headline4(color: titleColor),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded,
                            color: AppColors.grey400),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: cart.items.length,
                      separatorBuilder: (_, __) => const Divider(height: 8),
                      itemBuilder: (ctx, i) {
                        final item = cart.items[i];
                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha:0.04),
                            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                            border:
                                Border.all(color: accentColor.withValues(alpha:0.1)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha:0.1),
                                  borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
                                ),
                                child: Icon(Icons.inventory_2_rounded,
                                    color: accentColor, size: 18),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.product.name,
                                      style: AppTextStyles.bodyMedium(
                                              color: titleColor)
                                          .copyWith(fontSize: 13),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${item.product.price.toStringAsFixed(2)} $_currency',
                                      style: AppTextStyles.caption(
                                          color: AppColors.success,
                                          fontSize: 10),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: accentColor.withValues(alpha:0.05),
                                        borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
                                        border: Border.all(
                                            color:
                                                accentColor.withValues(alpha:0.2)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          InkWell(
                                            onTap: () =>
                                                cart.decrementQuantity(i),
                                            borderRadius:
                                                const BorderRadius.only(
                                              topLeft: Radius.circular(8),
                                              bottomLeft: Radius.circular(8),
                                            ),
                                            child: Container(
                                              width: 44,
                                              height: 44,
                                              alignment: Alignment.center,
                                              child: const Icon(
                                                  Icons.remove_rounded,
                                                  size: 16,
                                                  color: AppColors.error),
                                            ),
                                          ),
                                          Container(
                                            width: 44,
                                            height: 44,
                                            alignment: Alignment.center,
                                            child: Text(
                                              '${item.quantity}',
                                              style: AppTextStyles.caption(
                                                  fontSize: 12),
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () =>
                                                cart.incrementQuantity(i),
                                            borderRadius:
                                                const BorderRadius.only(
                                              topRight: Radius.circular(8),
                                              bottomRight: Radius.circular(8),
                                            ),
                                            child: Container(
                                              width: 44,
                                              height: 44,
                                              alignment: Alignment.center,
                                              child: const Icon(
                                                  Icons.add_rounded,
                                                  size: 16,
                                                  color: AppColors.success),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      // ⭐ حذف مع إمكانية التراجع (Undo) لتجنّب الأخطاء
                                      final removedIndex = i;
                                      final removedItem = item;
                                      cart.removeItem(removedIndex);
                                      ScaffoldMessenger.of(context)
                                          .hideCurrentSnackBar();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          behavior:
                                              SnackBarBehavior.floating,
                                          backgroundColor: isDark
                                              ? AppColors.darkSurfaceAlt
                                              : AppColors.grey900,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                DesignTokens.radiusMd),
                                          ),
                                          content: Text(
                                            LocalizationHelper
                                                .posItemRemoved,
                                            style: AppTextStyles.bodyMedium(
                                                color: AppColors.white),
                                          ),
                                          action: SnackBarAction(
                                            label: LocalizationHelper.undo,
                                            textColor: AppColors.neonOrange,
                                            onPressed: () => cart.reinsertItem(
                                                removedIndex, removedItem),
                                          ),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: AppColors.errorLight,
                                        borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
                                      ),
                                      child: const Icon(Icons.delete_rounded,
                                          size: 16, color: AppColors.error),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${item.subtotal.toStringAsFixed(2)} $_currency',
                                    style: AppTextStyles.bodyMedium(
                                            color: accentColor)
                                        .copyWith(fontSize: 13),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? accentColor.withValues(alpha:0.06)
                          : AppColors.secondaryVeryLight.withValues(alpha:0.3),
                      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                      border: Border.all(
                        color: isDark
                            ? accentColor.withValues(alpha:0.15)
                            : AppColors.secondary.withValues(alpha:0.15),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildSummaryRow(
                          LocalizationHelper.posSubtotal,
                          '${cart.subtotal.toStringAsFixed(2)} $_currency',
                          bodyColor,
                        ),
                        if (cart.discount > 0)
                          _buildSummaryRow(
                            LocalizationHelper.posDiscount,
                            '-${cart.discount.toStringAsFixed(2)} $_currency',
                            AppColors.error,
                          ),
                        if (cart.taxRate > 0)
                          _buildSummaryRow(
                            '${LocalizationHelper.posTax} (${cart.taxRate}%)',
                            '${cart.taxAmount.toStringAsFixed(2)} $_currency',
                            bodyColor,
                          ),
                        Divider(
                            height: 14, color: accentColor.withValues(alpha:0.3)),
                        _buildSummaryRow(
                          LocalizationHelper.posTotal,
                          '${cart.total.toStringAsFixed(2)} $_currency',
                          accentColor,
                          isBold: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            showHoldOrderDialog(context,
                                cart: cart,
                                currency: _currency,
                                showSnackBar: _showSnackBar);
                          },
                          icon: const Icon(Icons.pause_rounded, size: 14),
                          label: Text(
                            LocalizationHelper.posHold,
                            style: const TextStyle(fontSize: 11),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.warning,
                            side: const BorderSide(color: AppColors.warning),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            minimumSize: const Size(0, 40),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _processCheckout(cart);
                          },
                          icon: const Icon(Icons.payment_rounded, size: 14),
                          label: Text(
                            '${LocalizationHelper.posCheckout} ${cart.total.toStringAsFixed(2)} $_currency',
                            style: const TextStyle(fontSize: 11),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor:
                                isDark ? AppColors.black : AppColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            minimumSize: const Size(0, 40),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
    );
  }

  Widget _buildSummaryRow(String label, String value, Color color,
      {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: (isBold
                    ? AppTextStyles.bodyLarge(color: color)
                    : AppTextStyles.bodySmall(color: color))
                .copyWith(fontSize: isBold ? 15 : 12),
          ),
          Flexible(
            child: Text(
              value,
              style: (isBold
                      ? AppTextStyles.bodyLarge(color: color)
                      : AppTextStyles.bodySmall(color: color))
                  .copyWith(fontSize: isBold ? 15 : 12),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  Text(
                    LocalizationHelper.posTitle,
                    style: AppTextStyles.headline3(
                      color: isDark
                          ? AppColors.textDarkPrimary
                          : AppColors.textLightPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (!_isScannerVisible) ...[
                    Consumer<CartService>(
                      builder: (context, cart, child) => cart.hasHeldOrders
                          ? Stack(
                              children: [
                                IconButton(
                                  onPressed: () => showHeldOrdersSheet(context,
                                      cart: cart,
                                      currency: _currency,
                                      showSnackBar: _showSnackBar),
                                  icon: const Icon(
                                      Icons.pause_circle_rounded,
                                      size: 24),
                                  color: AppColors.warning,
                                ),
                                Positioned(
                                  right: 2,
                                  top: 2,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: AppColors.error,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '${cart.heldOrderCount}',
                                      style: AppTextStyles.overline(
                                        color: AppColors.white,
                                        fontSize: 8,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                    Consumer<CartService>(
                      builder: (context, cart, child) => Stack(
                        children: [
                          IconButton(
                            onPressed: () => _showCartDialog(context, cart),
                            icon: const Icon(
                                Icons.shopping_cart_rounded,
                                size: 24),
                            color: accentColor,
                          ),
                          if (cart.totalItems > 0)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: AppColors.error,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${cart.totalItems}',
                                  style: AppTextStyles.overline(
                                    color: AppColors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _updateSearchQuery,
                      decoration: InputDecoration(
                        hintText: LocalizationHelper.posSearchHint,
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _searchController,
                          builder: (_, value, __) => value.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded,
                                      size: 20),
                                  onPressed: _clearSearch,
                                )
                              : const SizedBox.shrink(),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isScannerVisible
                            ? [
                                AppColors.error,
                                AppColors.error.withValues(alpha:0.7)
                              ]
                            : [accentColor, accentColor.withValues(alpha:0.7)],
                      ),
                      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                      boxShadow: [
                        BoxShadow(
                          color: (_isScannerVisible
                                  ? AppColors.error
                                  : accentColor)
                              .withValues(alpha:0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: _toggleScanner,
                      tooltip: LocalizationHelper.posScanBarcode,
                      icon: Icon(
                        _isScannerVisible
                            ? Icons.stop_rounded
                            : Icons.qr_code_scanner_rounded,
                        color: isDark ? AppColors.black : AppColors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_isScannerVisible) ...[
              BarcodeScannerView(
                onBarcodeDetected: _onBarcodeDetected,
                onClose: () => setState(() => _isScannerVisible = false),
              ),
              const SizedBox(height: 8),
              Consumer<CartService>(
                builder: (context, cart, child) => cart.isNotEmpty
                    ? _buildCartPreview(context, cart)
                    : const SizedBox.shrink(),
              ),
            ],
            if (!_isScannerVisible) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
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
                            fontSize: 10,
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
                            _rebuildFilteredProducts();
                          });
                        },
                        selectedColor: accentColor.withValues(alpha:0.08),
                        checkmarkColor: accentColor,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _isLoadingProducts && _products.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : _products.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.inventory_2_rounded,
                                  size: 60,
                                  color: isDark
                                      ? AppColors.textDarkTertiary
                                      : AppColors.grey300,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  LocalizationHelper.posNoProducts,
                                  style: AppTextStyles.bodyMedium(
                                    color: isDark
                                        ? AppColors.textDarkSecondary
                                        : AppColors.grey400,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _filteredProducts.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(
                                        color: accentColor.withValues(alpha:0.08),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.search_off_rounded,
                                        size: 56,
                                        color: isDark
                                            ? AppColors.textDarkTertiary
                                            : AppColors.textLightTertiary,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      LocalizationHelper.posNoResults,
                                      style: AppTextStyles.bodyLarge(
                                        color: isDark
                                            ? AppColors.textDarkSecondary
                                            : AppColors.textLightSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      LocalizationHelper.posNoResultsSub,
                                      style: AppTextStyles.bodySmall(
                                        color: isDark
                                            ? AppColors.textDarkTertiary
                                            : AppColors.textLightTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final crossAxisCount =
                                      constraints.maxWidth < 480
                                          ? 3
                                          : constraints.maxWidth < 720
                                              ? 4
                                              : 5;
                                  return RefreshIndicator(
                                    onRefresh: _loadProductsSilently,
                                    color: accentColor,
                                    child: GridView.builder(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: crossAxisCount,
                                        childAspectRatio: 0.85,
                                        crossAxisSpacing: 10,
                                        mainAxisSpacing: 10,
                                      ),
                                      itemCount: _filteredProducts.length,
                                      itemBuilder: (_, i) {
                                        final product = _filteredProducts[i];
                                        return POSProductGridItem(
                                          product: product,
                                          currency: _currency,
                                          onTap: () {
                                            if (product.quantity > 0) {
                                              context
                                                  .read<CartService>()
                                                  .addProduct(product);
                                              _showSnackBar(
                                                  '${product.name} ${LocalizationHelper.posAdded}',
                                                  AppColors.success);
                                            } else {
                                              // ⭐ تغذية راجعة واضحة عند منتج نفد مخزونه
                                              ScannerFeedbackService
                                                  .outOfStock();
                                              _showSnackBar(
                                                  LocalizationHelper
                                                      .posOutOfStockFeedback,
                                                  AppColors.error);
                                            }
                                          },
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
