// lib/screens/supplier_return_screen.dart

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../helpers/quantity_format.dart';
import '../models/purchase_model.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/screen_palette.dart';
import '../widgets/app_snackbar.dart';
import '../theme/design_tokens.dart';

/// شاشة الإرجاع للمورد: عرض أصناف الشراء الأصلي فقط مع سقف إرجاع
/// لكل منتج (المشترى − المرتجع سابقاً)، وكمية افتراضية تساوي كامل السقف.
class SupplierReturnScreen extends StatefulWidget {
  final Purchase originalPurchase;

  const SupplierReturnScreen({super.key, required this.originalPurchase});

  @override
  State<SupplierReturnScreen> createState() => _SupplierReturnScreenState();
}

class _Row {
  final String productId;
  final String productName;
  final double costPrice;
  final double cap;

  _Row({
    required this.productId,
    required this.productName,
    required this.costPrice,
    required this.cap,
  });
}

class _SupplierReturnScreenState extends State<SupplierReturnScreen> {
  static const String _currency = 'DZD';

  final SyncService _sync = SyncService();
  final Uuid _uuid = const Uuid();
  final TextEditingController _noteController = TextEditingController();

  late final List<_Row> _rows;
  late final Map<String, double> _returnQty;
  final Map<String, TextEditingController> _qtyControllers = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // ⭐ المتاح للإرجاع = المشترى − المرتجع المحفوظ داخل السجل − المرتجعات
    // القديمة المستقلة، عبر availableForReturn في النموذج.
    final legacyReturned = <String, double>{};
    for (final r in DatabaseService.instance
        .getReturnPurchasesFor(widget.originalPurchase.id)) {
      for (final item in r.items) {
        legacyReturned[item.productId] =
            (legacyReturned[item.productId] ?? 0.0) + item.quantity;
      }
    }

    final available = widget.originalPurchase
        .availableForReturn(extraReturned: legacyReturned);

    _rows = available
        .map((item) => _Row(
              productId: item.productId,
              productName: item.productName,
              costPrice: item.costPrice,
              cap: item.quantity,
            ))
        .toList();

    // الافتراضي: كامل السقف المتاح لكل منتج.
    _returnQty = {for (final row in _rows) row.productId: row.cap};
    for (final row in _rows) {
      _qtyControllers[row.productId] =
          TextEditingController(text: QuantityFormat.quantity(row.cap));
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
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

  void _setQty(_Row row, double value) {
    var clamped = value;
    if (value < 0 || QuantityFormat.isZeroQty(value)) clamped = 0.0;
    if (QuantityFormat.exceedsQty(clamped, row.cap)) clamped = row.cap;
    if (_returnQty[row.productId] == clamped) return;
    setState(() {
      _returnQty[row.productId] = clamped;
      _qtyControllers[row.productId]!.text = QuantityFormat.quantity(clamped);
    });
  }

  int get _selectedCount =>
      _returnQty.values.where((q) => QuantityFormat.greaterThanQty(q, 0)).length;

  double get _returnTotal {
    var total = 0.0;
    for (final row in _rows) {
      total += row.costPrice * (_returnQty[row.productId] ?? 0);
    }
    return total;
  }

  Future<void> _saveReturn() async {
    final items = <PurchaseItem>[];
    for (final row in _rows) {
      final qty = _returnQty[row.productId] ?? 0.0;
      if (QuantityFormat.greaterThanQty(qty, 0)) {
        items.add(PurchaseItem(
          id: _uuid.v4(),
          productId: row.productId,
          productName: row.productName,
          costPrice: row.costPrice,
          quantity: QuantityFormat.round(qty),
          subtotal: row.costPrice * qty,
        ));
      }
    }

    setState(() => _isSaving = true);
    try {
      await _sync.createSupplierReturn(
        originalPurchaseId: widget.originalPurchase.id,
        returnItems: items,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );
      if (!mounted) return;
      _showSnack(context.successColor, 'purchases.returnSaved'.tr());
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showSnack(context.errorColor, e.toString());
    }
  }

  Widget _buildItemRow(_Row row) {
    final titleColor = context.titleColor;
    final bodyColor = context.bodyColor;
    final captionColor = context.captionColor;
    final disabled = QuantityFormat.isZeroQty(row.cap);
    final qty = _returnQty[row.productId] ?? 0.0;

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              disabled ? captionColor.withValues(alpha: 0.06) : null,
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.productName,
                    style: AppTextStyles.bodyMedium(color: titleColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${'purchases.availableForReturn'.tr()}: ${QuantityFormat.quantity(row.cap)}',
                  style: AppTextStyles.caption(
                      color: disabled ? context.errorColor : bodyColor,
                      fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildStepperButton(
                  icon: Icons.remove_rounded,
                  enabled: !disabled && QuantityFormat.greaterThanQty(qty, 0),
                  onPressed: () => _setQty(row, qty - 1.0),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _qtyControllers[row.productId],
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
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
                      enabled: !disabled,
                      onChanged: (value) {
                        final parsed = double.tryParse(value) ?? 0.0;
                        var clamped = parsed;
                        if (parsed < 0 || QuantityFormat.isZeroQty(parsed)) {
                          clamped = 0.0;
                        }
                        if (QuantityFormat.exceedsQty(clamped, row.cap)) {
                          clamped = row.cap;
                        }
                        setState(
                            () => _returnQty[row.productId] = clamped);
                        if (parsed != clamped) {
                          _qtyControllers[row.productId]!.text =
                              QuantityFormat.quantity(clamped);
                        }
                      },
                      style: AppTextStyles.bodyMedium(color: titleColor),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildStepperButton(
                  icon: Icons.add_rounded,
                  enabled: !disabled &&
                      QuantityFormat.exceedsQty(row.cap, qty),
                  onPressed: () => _setQty(row, qty + 1.0),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${row.costPrice.toStringAsFixed(2)} $_currency × '
              '${QuantityFormat.quantity(qty)} = '
              '${(row.costPrice * qty).toStringAsFixed(2)} $_currency',
              style:
                  AppTextStyles.caption(color: captionColor, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepperButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    final accentColor = context.accent;
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton.outlined(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          foregroundColor: accentColor,
          side: BorderSide(color: accentColor.withValues(alpha: 0.4)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = context.accent;
    final titleColor = context.titleColor;
    final bodyColor = context.bodyColor;
    final hasSelection = _selectedCount > 0 && !_isSaving;

    return Scaffold(
      backgroundColor: context.scaffoldColor,
      appBar: AppBar(
        title: Text(
          'purchases.returnToSupplier'.tr(),
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          ..._rows.map(_buildItemRow),
          const SizedBox(height: 8),
          TextField(
            controller: _noteController,
            maxLines: 2,
            style: AppTextStyles.bodyMedium(color: bodyColor),
            decoration: InputDecoration(
              hintText: 'purchases.note'.tr(),
              hintStyle: AppTextStyles.bodySmall(color: context.captionColor),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${'purchases.total'.tr()} ($_selectedCount)',
                style: AppTextStyles.bodyLarge(color: titleColor),
              ),
              Text(
                '${_returnTotal.toStringAsFixed(2)} $_currency',
                style: AppTextStyles.bodyLarge(
                    color: accentColor, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: hasSelection ? _saveReturn : null,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.white))
                  : const Icon(Icons.reply_rounded, size: 18),
              label: Text('purchases.saveReturn'.tr()),
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
