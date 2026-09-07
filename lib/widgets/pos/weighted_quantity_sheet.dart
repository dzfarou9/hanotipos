// lib/widgets/pos/weighted_quantity_sheet.dart

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../helpers/localization_helper.dart';
import '../../helpers/quantity_format.dart';
import '../../models/product_model.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/design_tokens.dart';

/// ورقة إدخال الكمية للمنتجات الموزونة (kg/litre): لوحة عشرية،
/// سعر الوحدة، الإجمالي الحي، وأزرار سريعة (0.25/0.5/1).
/// يعيد الكمية المقبولة أو null عند الإلغاء.
Future<double?> showWeightedQuantitySheet(
  BuildContext context, {
  required Product product,
  required String currency,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(DesignTokens.radiusLg)),
    ),
    builder: (ctx) => _WeightedQuantitySheet(
      product: product,
      currency: currency,
    ),
  );
}

class _WeightedQuantitySheet extends StatefulWidget {
  final Product product;
  final String currency;
  const _WeightedQuantitySheet({
    required this.product,
    required this.currency,
  });

  @override
  State<_WeightedQuantitySheet> createState() => _WeightedQuantitySheetState();
}

class _WeightedQuantitySheetState extends State<_WeightedQuantitySheet> {
  final _controller = TextEditingController(text: '');

  double get _qty => double.tryParse(_controller.text) ?? 0.0;
  bool get _overStock =>
      QuantityFormat.exceedsQty(_qty, widget.product.quantity);
  bool get _valid => QuantityFormat.greaterThanQty(_qty, 0) && !_overStock;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setQty(double v) {
    setState(() => _controller.text = QuantityFormat.quantity(v));
  }

  @override
  Widget build(BuildContext context) {
    final unitLabel = LocalizationHelper.unitLabel(widget.product.unit);
    final titleColor = AppTextStyles.dialogTitleColor(context);
    final bodyColor = AppTextStyles.dialogBodyColor(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.product.name,
            style: AppTextStyles.headline4(color: titleColor),
          ),
          const SizedBox(height: 4),
          Text(
            'pos.weighted_price_per'
                .tr(namedArgs: {
                  'price': widget.product.price.toStringAsFixed(0),
                  'unit': unitLabel,
                }),
            style: AppTextStyles.bodyMedium(color: bodyColor),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('weighted_qty_field'),
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            decoration: InputDecoration(
              suffixText: unitLabel,
              errorText: _overStock
                  ? '${LocalizationHelper.posOutOfStockFeedback} (${QuantityFormat.quantity(widget.product.quantity)} $unitLabel)'
                  : null,
            ),
            style: AppTextStyles.headline3(color: titleColor),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final v in const [0.25, 0.5, 1.0])
                OutlinedButton(
                  key: Key('weighted_chip_$v'),
                  onPressed: () => _setQty(v),
                  child: Text(QuantityFormat.quantity(v)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                LocalizationHelper.posTotal,
                style: AppTextStyles.bodyMedium(color: bodyColor),
              ),
              Text(
                '${(_qty * widget.product.price).toStringAsFixed(2)} ${widget.currency}',
                style: AppTextStyles.headline3(color: titleColor),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('weighted_add_btn'),
            onPressed: _valid
                ? () => Navigator.pop(context, QuantityFormat.round(_qty))
                : null,
            child: Text('pos.weighted_add'.tr()),
          ),
        ],
      ),
    );
  }
}
