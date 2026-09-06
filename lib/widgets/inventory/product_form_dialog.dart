// lib/widgets/inventory/product_form_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../helpers/localization_helper.dart';
import '../../models/product_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

const String _currency = 'DZD';

/// Outcome of the product form.
enum ProductFormAction { save, scan }

/// Payload returned when the user confirms the form.
class ProductFormData {
  const ProductFormData({
    required this.name,
    required this.price,
    required this.quantity,
    required this.barcode,
    required this.minStockLevel,
    this.costPrice,
  });

  final String name;
  final double price;
  final int quantity;
  final String? barcode;
  final int minStockLevel;

  /// سعر الشراء (التكلفة) — null يعني «غير محدد».
  final double? costPrice;
}

/// Result of the product form dialog.
class ProductFormResult {
  const ProductFormResult({required this.action, this.data});

  final ProductFormAction action;
  final ProductFormData? data;
}

/// Opens the add/edit product dialog.
///
/// - [product] non-null: edit mode (prefilled).
/// - [barcode] non-null: prefills the barcode field (scan -> add as new).
/// Returns [ProductFormResult.action] == [ProductFormAction.scan] when the
/// user taps the in-form scanner button, so the caller can open the scanner.
Future<ProductFormResult?> showProductFormDialog(
  BuildContext context, {
  Product? product,
  String? barcode,
}) {
  return showDialog<ProductFormResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProductFormDialog(product: product, barcode: barcode),
  );
}

class _ProductFormDialog extends StatefulWidget {
  const _ProductFormDialog({this.product, this.barcode});

  final Product? product;
  final String? barcode;

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _barcodeController;
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _costController;
  late final TextEditingController _quantityController;
  late final TextEditingController _minStockController;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _barcodeController =
        TextEditingController(text: widget.barcode ?? product?.barcode ?? '');
    _nameController = TextEditingController(text: product?.name ?? '');
    _priceController = TextEditingController(text: product?.price.toString() ?? '');
    _costController = TextEditingController(
        text: (product?.costPrice ?? 0) > 0
            ? product!.costPrice!.toString()
            : '');
    _quantityController =
        TextEditingController(text: product?.quantity.toString() ?? '');
    _minStockController =
        TextEditingController(text: product?.minStockLevel.toString() ?? '10');
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _quantityController.dispose();
    _minStockController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final costText = _costController.text.trim();
    final cost = costText.isEmpty ? null : double.tryParse(costText);

    Navigator.pop(
      context,
      ProductFormResult(
        action: ProductFormAction.save,
        data: ProductFormData(
          name: _nameController.text.trim(),
          price: double.parse(_priceController.text),
          quantity: int.parse(_quantityController.text),
          barcode: _barcodeController.text.trim().isNotEmpty
              ? _barcodeController.text.trim()
              : null,
          minStockLevel: int.parse(_minStockController.text),
          costPrice: (cost != null && cost > 0) ? cost : null,
        ),
      ),
    );
  }

  void _requestScan() {
    Navigator.pop(context, const ProductFormResult(action: ProductFormAction.scan));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    final titleColor =
        isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _isEditing ? Icons.edit_rounded : Icons.add_rounded,
                          color: accentColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isEditing
                            ? LocalizationHelper.posEditProduct
                            : LocalizationHelper.posAddProduct,
                        style: AppTextStyles.headline4(color: titleColor),
                      ),
                    ]),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.grey400),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _barcodeController,
                      decoration: InputDecoration(
                        labelText: LocalizationHelper.posBarcode,
                        prefixIcon:
                            const Icon(Icons.qr_code_rounded, size: 20),
                        hintText: LocalizationHelper.posEnterOrScan,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        accentColor,
                        accentColor.withValues(alpha: 0.7),
                      ]),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: _requestScan,
                      icon: Icon(
                        Icons.qr_code_scanner_rounded,
                        color: isDark ? AppColors.black : AppColors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: LocalizationHelper.posProductName,
                    prefixIcon: const Icon(Icons.inventory_2_rounded, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? LocalizationHelper.inventoryNameRequired
                      : null,
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        TextInputFormatter.withFunction(
                          (oldValue, newValue) {
                            return RegExp(r'^\d*\.?\d{0,2}$')
                                    .hasMatch(newValue.text)
                                ? newValue
                                : oldValue;
                          },
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: '${LocalizationHelper.posPrice} ($_currency)',
                        prefixIcon:
                            const Icon(Icons.attach_money_rounded, size: 20),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return LocalizationHelper.inventoryPriceRequired;
                        }
                        final value = double.tryParse(v);
                        if (value == null || value <= 0) {
                          return LocalizationHelper.error;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _quantityController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: LocalizationHelper.posQuantity,
                        prefixIcon: const Icon(
                            Icons.production_quantity_limits, size: 20),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return LocalizationHelper.inventoryQuantityRequired;
                        }
                        final value = int.tryParse(v);
                        if (value == null || value < 0) {
                          return LocalizationHelper.error;
                        }
                        return null;
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                // ⭐ سعر الشراء (اختياري): يُحدَّث تلقائياً مع كل عملية شراء
                TextFormField(
                  controller: _costController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (oldValue, newValue) {
                        return RegExp(r'^\d*\.?\d{0,2}$')
                                .hasMatch(newValue.text)
                            ? newValue
                            : oldValue;
                      },
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText:
                        '${LocalizationHelper.inventoryCostPrice} ($_currency)',
                    prefixIcon:
                        const Icon(Icons.shopping_bag_rounded, size: 20),
                    helperText: LocalizationHelper.inventoryCostPriceHint,
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
                const SizedBox(height: 14),
                TextFormField(
                  controller: _minStockController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    labelText: LocalizationHelper.inventoryMinStock,
                    prefixIcon: const Icon(Icons.warning_rounded, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return LocalizationHelper.inventoryMinStockRequired;
                    }
                    final value = int.tryParse(v);
                    if (value == null || value < 0) {
                      return LocalizationHelper.error;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _submit,
                    icon: Icon(
                      _isEditing ? Icons.save_rounded : Icons.add_rounded,
                      size: 18,
                    ),
                    label: Text(_isEditing
                        ? LocalizationHelper.posUpdate
                        : LocalizationHelper.posAdd),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: isDark ? AppColors.black : AppColors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
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