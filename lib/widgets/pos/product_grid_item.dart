// lib/widgets/pos/product_grid_item.dart

import 'package:flutter/material.dart';
import '../../models/product_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../helpers/localization_helper.dart';
import '../../helpers/quantity_format.dart';

/// بطاقة منتج في شبكة شاشة البيع.
class POSProductGridItem extends StatelessWidget {
  final Product product;
  final String currency;
  final VoidCallback onTap;

  const POSProductGridItem({
    super.key,
    required this.product,
    required this.currency,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLowStock =
        product.quantity <= product.minStockLevel && product.quantity > 0;
    final isOutOfStock = QuantityFormat.isZeroQty(product.quantity);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isOutOfStock
                ? AppColors.errorLight
                : AppColors.grey200.withValues(alpha:0.4),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isOutOfStock
                    ? AppColors.errorLight
                    : isLowStock
                        ? AppColors.warningLight
                        : accentColor.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.inventory_2_rounded,
                color: isOutOfStock
                    ? AppColors.error
                    : isLowStock
                        ? AppColors.warning
                        : accentColor,
                size: 20,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                product.name,
                style: AppTextStyles.bodyMedium().copyWith(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${product.price.toStringAsFixed(2)} $currency',
              style: AppTextStyles.bodyLarge(color: accentColor)
                  .copyWith(fontSize: 13),
            ),
            if (isOutOfStock)
              Text(
                LocalizationHelper.posOutOfStock,
                style:
                    AppTextStyles.caption(color: AppColors.error, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}
