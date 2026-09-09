// lib/screens/purchase_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import '../helpers/quantity_format.dart';
import '../helpers/platform_helper.dart';
import '../models/purchase_model.dart';
import '../models/supplier_model.dart';
import '../models/product_model.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../services/barcode_input_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/screen_palette.dart';
import '../widgets/app_snackbar.dart';
import '../theme/design_tokens.dart';
import '../widgets/barcode_scanner_view.dart';

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key, this.initialSupplierId});

  final String? initialSupplierId;

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  static const String _currency = 'DZD';

  final SyncService _sync = SyncService();
  final Uuid _uuid = const Uuid();

  List<Supplier> _suppliers = [];
  bool _loadingSuppliers = true;
  String? _supplierId;

  final List<_CartLine> _cartLines = [];
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _invoiceController = TextEditingController();

  bool _scanning = false;
  bool _saving = false;
  StreamSubscription<String>? _usbScanSub;
  bool _isUsbScanMode = false;
  String? _lastUsbScan;

  @override
  void initState() {
    super.initState();
    _loadSuppliers(selectId: widget.initialSupplierId);
  }

  @override
  void dispose() {
    _usbScanSub?.cancel();
    _noteController.dispose();
    _invoiceController.dispose();
    for (final line in _cartLines) {
      line.dispose();
    }
    super.dispose();
  }

  Supplier? get _selectedSupplier {
    final id = _supplierId;
    if (id == null) return null;
    for (final s in _suppliers) {
      if (s.id == id) return s;
    }
    return null;
  }

  double get _total => _cartLines.fold<double>(
      0.0, (sum, line) => sum + line.cost * line.quantity);

  bool get _canSave =>
      _selectedSupplier != null && _cartLines.isNotEmpty && !_saving;

  // ==================== التحميل ====================

  Future<void> _loadSuppliers({String? selectId}) async {
    try {
      final list = await _sync.getSuppliers();
      if (!mounted) return;
      setState(() {
        _suppliers = list;
        _loadingSuppliers = false;
        if (selectId != null && list.any((s) => s.id == selectId)) {
          _supplierId = selectId;
        } else if (_supplierId != null &&
            !list.any((s) => s.id == _supplierId)) {
          _supplierId = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _suppliers = [];
        _loadingSuppliers = false;
      });
    }
  }

  // ==================== السلة ====================

  void _addProduct(Product product) {
    final existing =
        _cartLines.where((l) => l.productId == product.id).toList();
    if (existing.isNotEmpty) {
      final line = existing.first;
      setState(() {
        line.quantity = line.quantity + 1.0;
        line.quantityController.text = QuantityFormat.quantity(line.quantity);
      });
    } else {
      setState(() {
        _cartLines.add(_CartLine(product: product));
      });
    }
    if (_scanning) {
      // ⭐ إغلاق الماسح أولاً حتى يظهر SnackBar فوقه
      setState(() => _scanning = false);
    }
    _showSnack(
      context.successColor,
      '${product.name} ${'purchases.addedToCart'.tr()}',
    );
  }

  void _updateLine(_CartLine line) {
    final qty = double.tryParse(line.quantityController.text) ?? line.quantity;
    final cost =
        double.tryParse(line.costController.text.replaceAll(',', '.')) ??
            line.cost;
    line
      ..quantity = qty < 0 ? 0.0 : qty
      ..cost = cost < 0 ? 0 : cost;
    setState(() {});
  }

  void _removeLine(_CartLine line) {
    setState(() {
      _cartLines.remove(line);
      line.dispose();
    });
  }

  // ==================== مسح الباركود ====================

  void _openScanner() {
    if (PlatformHelper.isWindows) {
      setState(() {
        _isUsbScanMode = !_isUsbScanMode;
        if (_isUsbScanMode) {
          _usbScanSub = BarcodeInputService.instance.scans.listen((code) {
            if (!mounted) return;
            setState(() => _lastUsbScan = code);
            _onBarcodeDetected(code);
          });
        } else {
          _usbScanSub?.cancel();
          _usbScanSub = null;
        }
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _scanning = true);
  }

  void _onBarcodeDetected(String barcode) {
    try {
      final product = DatabaseService.instance.getProductByBarcode(barcode);
      if (!mounted) return;
      if (product == null) {
        // ⭐ باركود غير معروف لكنه معلّق في السلة بالفعل → زيادة كميته
        final pendingLine = _cartLines.where((l) =>
            l.isPending && l.pending!.barcode == barcode).toList();
        if (pendingLine.isNotEmpty) {
          final line = pendingLine.first;
          setState(() {
            line.quantity = line.quantity + 1.0;
            line.quantityController.text = QuantityFormat.quantity(line.quantity);
          });
          if (_scanning) setState(() => _scanning = false);
          _showSnack(
            context.successColor,
            '${line.productName} ${'purchases.addedToCart'.tr()}',
          );
          return;
        }
        // ⭐ إغلاق الماسح أولاً ثم اقتراح إضافة المنتج (يُنشأ مع إتمام الشراء)
        setState(() => _scanning = false);
        _openQuickAddProduct(barcode: barcode);
        return;
      }
      _addProduct(product);
    } catch (e) {
      if (mounted) {
        setState(() => _scanning = false);
        _showSnack(context.errorColor, e.toString());
      }
    }
  }

  // ==================== إضافة منتج سريعاً (غير موجود بالمخزون) ====================

  // ⭐ منتج غير موجود في المخزون: نموذج مصغّر (الاسم والسعر والباركود فقط —
  // بلا كمية ولا حد أدنى). لا يُنشأ المنتج في المخزون الآن؛ يُسجَّل كسطر
  // «معلّق» في السلة، ولا يُحفظ فعلياً عبر SyncService.addProduct إلا بعد
  // إتمام الشراء (نفس مسار Offline First: Hive أولاً ثم رفع Firebase).
  Future<void> _openQuickAddProduct({String? barcode}) async {
    final result = await showDialog<_PendingProduct>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PendingProductDialog(barcode: barcode),
    );
    if (!mounted || result == null) return;

    setState(() {
      _cartLines.add(_CartLine.pendingProduct(result));
    });
    _showSnack(context.successColor, 'purchases.pendingProductAdded'.tr());
  }

  // ==================== اختيار منتج يدوياً ====================

  void _openProductPicker() {
    FocusScope.of(context).unfocus();
    final products = DatabaseService.instance.getAllProducts();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          context.isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ProductPickerSheet(
        products: products,
        accentColor: context.accent,
        titleColor: context.titleColor,
        bodyColor: context.bodyColor,
        onPick: (product) {
          Navigator.pop(context);
          _addProduct(product);
        },
        onAddNewProduct: () => _openQuickAddProduct(),
      ),
    );
  }

  // ==================== إضافة مورد سريعاً ====================

  Future<void> _openQuickAddSupplier() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickSupplierFormSheet(
        onSaved: (supplier) {
          Navigator.pop(context);
          _loadSuppliers(selectId: supplier.id);
        },
      ),
    );
  }

  // ==================== الحفظ ====================

  Future<void> _save() async {
    final supplier = _selectedSupplier;
    if (supplier == null || _cartLines.isEmpty || _saving) return;

    setState(() => _saving = true);
    try {
      // ⭐ المنتجات المعلّقة (غير الموجودة في المخزون) تُنشأ الآن فقط عند
      // إتمام الشراء: بكمية صفرية في المخزون (createPurchase يضيف الكمية
      // المشتراة)، وبنفس مسار Offline First.
      final realIdByLine = <_CartLine, String>{};
      for (final line in _cartLines) {
        final pending = line.pending;
        if (pending == null) continue;
        final created = await _sync.addProduct(
          name: pending.name,
          category: 'General',
          price: pending.price,
          quantity: 0.0,
          barcode: pending.barcode,
          minStockLevel: 10,
          costPrice: line.cost > 0 ? line.cost : null,
        );
        realIdByLine[line] = created.id;
      }

      final items = _cartLines
          .map((line) => PurchaseItem(
                id: _uuid.v4(),
                productId: realIdByLine[line] ?? line.productId,
                productName: line.productName,
                costPrice: line.cost,
                quantity: line.quantity,
                subtotal: line.cost * line.quantity,
              ))
          .toList();

      await _sync.createPurchase(
        supplierId: supplier.id,
        supplierName: supplier.name,
        items: items,
        note: _noteController.text.trim().isNotEmpty
            ? _noteController.text.trim()
            : null,
        invoiceNumber: _invoiceController.text.trim().isNotEmpty
            ? _invoiceController.text.trim()
            : null,
      );

      if (!mounted) return;
      _showSnack(context.successColor, 'purchases.save'.tr());
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnack(context.errorColor, e.toString());
    }
  }

  void _showSnack(Color color, String message) {
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

  // ==================== الواجهة ====================

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final accentColor = context.accent;
    final titleColor = context.titleColor;
    final bodyColor = context.bodyColor;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: Text(
          'purchases.newPurchase'.tr(),
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
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  children: [
                    _buildSupplierSelector(
                        accentColor, titleColor, bodyColor, isDark),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openScanner,
                            icon: Icon(Icons.qr_code_scanner_rounded,
                                size: 18, color: accentColor),
                            label: Text(
                              'purchases.scanBarcode'.tr(),
                              style: AppTextStyles.bodyMedium(
                                  color: titleColor),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: accentColor),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openProductPicker,
                            icon: Icon(Icons.list_alt_rounded,
                                size: 18, color: accentColor),
                            label: Text(
                              'purchases.pickProduct'.tr(),
                              style: AppTextStyles.bodyMedium(
                                  color: titleColor),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: accentColor),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_cartLines.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Column(
                          children: [
                            Icon(Icons.shopping_cart_outlined,
                                size: 48,
                                color: bodyColor.withValues(alpha: 0.4)),
                            const SizedBox(height: 10),
                            Text(
                              'purchases.emptyHint'.tr(),
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodySmall(
                                  color: bodyColor),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._cartLines.map(
                          (line) => _buildCartRow(line, titleColor, bodyColor)),
                    if (_cartLines.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildTotalRow(accentColor, titleColor, bodyColor,
                          isDark),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _invoiceController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'purchases.invoiceNumber'.tr(),
                        prefixIcon: const Icon(Icons.receipt_rounded, size: 20),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _noteController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'purchases.note'.tr(),
                        prefixIcon:
                            const Icon(Icons.notes_rounded, size: 20),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _canSave ? _save : null,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text('purchases.save'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor:
                          isDark ? AppColors.black : AppColors.white,
                      disabledBackgroundColor:
                          accentColor.withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_isUsbScanMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.qr_code_scanner_rounded),
                  title: Text(
                    _lastUsbScan == null
                        ? 'USB scanner ready — scan a barcode'
                        : 'Last scan: $_lastUsbScan',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _usbScanSub?.cancel();
                      _usbScanSub = null;
                      setState(() {
                        _isUsbScanMode = false;
                        _lastUsbScan = null;
                      });
                    },
                  ),
                ),
              ),
            ),
          if (_scanning)
            Positioned.fill(
              child: Container(
                color: Colors.black,
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      BarcodeScannerView(
                        onBarcodeDetected: _onBarcodeDetected,
                        onClose: () => setState(() => _scanning = false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSupplierSelector(
      Color accentColor, Color titleColor, Color bodyColor, bool isDark) {
    if (_loadingSuppliers) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('supplier_$_supplierId'),
            initialValue: _supplierId,
            hint: Text(
              _suppliers.isEmpty
                  ? 'purchases.addSupplierFirst'.tr()
                  : 'purchases.selectSupplier'.tr(),
              style: AppTextStyles.bodyMedium(color: bodyColor),
            ),
            items: _suppliers
                .map((s) => DropdownMenuItem<String>(
                      value: s.id,
                      child: Text(
                        s.name,
                        style: AppTextStyles.bodyMedium(color: titleColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: (value) => setState(() => _supplierId = value),
            decoration: InputDecoration(
              prefixIcon:
                  Icon(Icons.local_shipping_rounded, size: 20, color: accentColor),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
        IconButton(
          onPressed: _openQuickAddSupplier,
          tooltip: 'suppliers.add'.tr(),
          icon: Icon(Icons.person_add_rounded, color: accentColor),
        ),
      ],
    );
  }

  Widget _buildCartRow(
      _CartLine line, Color titleColor, Color bodyColor) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusMd)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    line.productName,
                    style: AppTextStyles.bodyMedium(color: titleColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (line.isPending) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radiusPill),
                    ),
                    child: Text(
                      'purchases.pendingProduct'.tr(),
                      style: AppTextStyles.bodySmall(
                        color: context.warningColor,
                      ),
                    ),
                  ),
                ],
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _removeLine(line),
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 20, color: AppColors.error),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: line.quantityController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      TextInputFormatter.withFunction(
                        (oldValue, newValue) {
                          final t = newValue.text;
                          final dotCount = '.'.allMatches(t).length;
                          final ok = dotCount <= 1 &&
                              RegExp(r'^\d*\.?\d{0,3}$').hasMatch(t);
                          return ok ? newValue : oldValue;
                        },
                      ),
                    ],
                    textAlign: TextAlign.center,
                    onChanged: (_) => _updateLine(line),
                    decoration: InputDecoration(
                      labelText: 'purchases.quantity'.tr(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: line.costController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    onChanged: (_) => _updateLine(line),
                    decoration: InputDecoration(
                      labelText: 'purchases.costPrice'.tr(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 90,
                  child: Text(
                    (line.cost * line.quantity).toStringAsFixed(2),
                    textAlign: TextAlign.end,
                    style: AppTextStyles.bodyMedium(color: bodyColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(Color accentColor, Color titleColor, Color bodyColor,
      bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            'purchases.total'.tr(),
            style: AppTextStyles.headline4(color: titleColor),
          ),
          const Spacer(),
          Text(
            '${_total.toStringAsFixed(2)} $_currency',
            style: AppTextStyles.headline3(color: accentColor),
          ),
        ],
      ),
    );
  }
}

// ==================== سطر السلة ====================

/// منتج معلّق: أدخلته من مسار «غير موجود بالمخزون» ولا يُنشأ فعلياً
/// في المخزون إلا عند إتمام الشراء.
class _PendingProduct {
  const _PendingProduct({
    required this.name,
    required this.price,
    this.barcode,
  });

  final String name;
  final double price;
  final String? barcode;
}

class _CartLine {
  // ⭐ منتج موجود: التكلفة تُملأ مسبقاً من سعر شراء المنتج في المخزون
  // (فارغة إن لم تكن محددة) ويمكن تعديلها — التعديل يُحدِّث المخزون عند الحفظ.
  _CartLine({required Product product})
      : productId = product.id,
        productName = product.name,
        pending = null,
        quantityController = TextEditingController(text: '1'),
        costController = TextEditingController(
            text: product.hasCost ? product.costPrice!.toString() : '') {
    quantity = 1.0;
    cost = product.costPrice ?? 0.0;
  }

  // ⭐ سطر منتج معلّق: productId مؤقت، يُستبدل بمعرّف حقيقي عند الحفظ.
  // التكلفة تبدأ فارغة — سعر البيع ليس تكلفة.
  _CartLine.pendingProduct(_PendingProduct this.pending)
      : productId = '',
        productName = pending.name,
        quantityController = TextEditingController(text: '1'),
        costController = TextEditingController() {
    quantity = 1.0;
    cost = 0.0;
  }

  /// غير null فقط لأسطر المنتجات المعلّقة
  final _PendingProduct? pending;

  bool get isPending => pending != null;

  final String productId;
  final String productName;
  final TextEditingController quantityController;
  final TextEditingController costController;

  double quantity = 1.0;
  double cost = 0.0;

  void dispose() {
    quantityController.dispose();
    costController.dispose();
  }
}

// ==================== اختيار منتج يدوياً ====================

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({
    required this.products,
    required this.accentColor,
    required this.titleColor,
    required this.bodyColor,
    required this.onPick,
    this.onAddNewProduct,
  });

  final List<Product> products;
  final Color accentColor;
  final Color titleColor;
  final Color bodyColor;
  final ValueChanged<Product> onPick;
  final VoidCallback? onAddNewProduct;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  late List<Product> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.products;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    final q = value.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.products
          : widget.products
              .where((p) =>
                  p.name.toLowerCase().contains(q) ||
                  (p.barcode?.toLowerCase().contains(q) ?? false))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: widget.bodyColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'purchases.pickProduct'.tr(),
              style: AppTextStyles.headline4(color: widget.titleColor),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearch,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'purchases.selectProduct'.tr(),
                prefixIcon:
                    Icon(Icons.search_rounded, color: widget.accentColor),
                filled: true,
                fillColor: context.isDark
                    ? AppColors.darkSurfaceAlt
                    : AppColors.lightSurfaceAlt,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'purchases.empty'.tr(),
                        style:
                            AppTextStyles.bodySmall(color: widget.bodyColor),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onAddNewProduct?.call();
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text('purchases.addNewProduct'.tr()),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: widget.accentColor,
                          side: BorderSide(
                            color: widget.accentColor.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final product = _filtered[i];
                      return ListTile(
                        onTap: () => widget.onPick(product),
                        leading: CircleAvatar(
                          backgroundColor:
                              widget.accentColor.withValues(alpha: 0.1),
                          child: Icon(Icons.inventory_2_rounded,
                              size: 18, color: widget.accentColor),
                        ),
                        title: Text(
                          product.name,
                          style:
                              AppTextStyles.bodyMedium(color: widget.titleColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: product.barcode == null ||
                                product.barcode!.isEmpty
                            ? null
                            : Text(
                                product.barcode!,
                                style: AppTextStyles.bodySmall(
                                    color: widget.bodyColor),
                              ),
                        trailing: Icon(Icons.add_circle_outline_rounded,
                            color: widget.accentColor),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ==================== إضافة مورد سريعاً ====================

class _QuickSupplierFormSheet extends StatefulWidget {
  const _QuickSupplierFormSheet({required this.onSaved});

  final ValueChanged<Supplier> onSaved;

  @override
  State<_QuickSupplierFormSheet> createState() =>
      _QuickSupplierFormSheetState();
}

class _QuickSupplierFormSheetState extends State<_QuickSupplierFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final supplier = await SyncService().addSupplier(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim().isNotEmpty
            ? _phoneController.text.trim()
            : null,
        address: _addressController.text.trim().isNotEmpty
            ? _addressController.text.trim()
            : null,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );
      if (!mounted) return;
      widget.onSaved(supplier);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackBar.error(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final accentColor = context.accent;
    final titleColor = context.titleColor;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.person_add_rounded,
                          color: accentColor, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'suppliers.add'.tr(),
                        style: AppTextStyles.headline4(color: titleColor),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.grey400),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'suppliers.name'.tr(),
                    prefixIcon:
                        const Icon(Icons.storefront_rounded, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'suppliers.nameRequired'.tr()
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'suppliers.phone'.tr(),
                    prefixIcon: const Icon(Icons.phone_rounded, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _addressController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'suppliers.address'.tr(),
                    prefixIcon:
                        const Icon(Icons.location_on_rounded, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'suppliers.notes'.tr(),
                    prefixIcon: const Icon(Icons.notes_rounded, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_rounded, size: 18),
                    label: Text('suppliers.add'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor:
                          isDark ? AppColors.black : AppColors.white,
                      disabledBackgroundColor:
                          accentColor.withValues(alpha: 0.5),
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
    );
  }
}

// ==================== نموذج منتج معلّق ====================

/// نموذج مصغّر لمنتج غير موجود في المخزون: الاسم والسعر والباركود فقط.
/// بلا كمية ولا حد أدنى — الكمية تأتي من سطر الشراء نفسه، والمنتج لا
/// يُنشأ في المخزون إلا عند إتمام الشراء.
class _PendingProductDialog extends StatefulWidget {
  const _PendingProductDialog({this.barcode});

  final String? barcode;

  @override
  State<_PendingProductDialog> createState() => _PendingProductDialogState();
}

class _PendingProductDialogState extends State<_PendingProductDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _barcodeController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _priceController = TextEditingController();
    _barcodeController = TextEditingController(text: widget.barcode ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _PendingProduct(
        name: _nameController.text.trim(),
        price: double.parse(_priceController.text.replaceAll(',', '.')),
        barcode: _barcodeController.text.trim().isNotEmpty
            ? _barcodeController.text.trim()
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final accentColor = context.accent;
    final titleColor = context.titleColor;
    final bodyColor = context.bodyColor;

    return AlertDialog(
      backgroundColor:
          isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.add_rounded, color: accentColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'purchases.addNewProduct'.tr(),
              style: AppTextStyles.headline4(color: titleColor),
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'purchases.newProductName'.tr(),
                prefixIcon: const Icon(Icons.inventory_2_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'purchases.newProductNameRequired'.tr()
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _priceController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'purchases.newProductPrice'.tr(),
                prefixIcon:
                    const Icon(Icons.sell_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
              validator: (v) {
                final value =
                    double.tryParse(v?.trim().replaceAll(',', '.') ?? '');
                if (value == null || value <= 0) {
                  return 'purchases.newProductPriceInvalid'.tr();
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _barcodeController,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: 'purchases.newProductBarcode'.tr(),
                prefixIcon:
                    const Icon(Icons.qr_code_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'purchases.pendingProductHint'.tr(),
              style: AppTextStyles.bodySmall(color: bodyColor),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'common.cancel'.tr(),
            style: AppTextStyles.bodyMedium(color: bodyColor),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text('common.add'.tr()),
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: isDark ? AppColors.black : AppColors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            ),
          ),
        ),
      ],
    );
  }
}
