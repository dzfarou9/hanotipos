import 'package:flutter/material.dart';
import '../helpers/localization_helper.dart';
import '../helpers/quantity_format.dart';
import '../models/product_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/design_tokens.dart';
import '../theme/screen_palette.dart';
import 'empty_state.dart';

/// Bottom sheet يعرض المنتجات منخفضة المخزون ونافدة المخزون.
class LowStockProductsSheet extends StatelessWidget {
  final List<Product> lowStock;
  final List<Product> outOfStock;

  const LowStockProductsSheet({
    super.key,
    required this.lowStock,
    required this.outOfStock,
  });

  static const String _currency = 'DZD';

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final titleColor = context.titleColor;
    final bodyColor = context.bodyColor;

    final allEmpty = lowStock.isEmpty && outOfStock.isEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: DesignTokens.space12),
      constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(DesignTokens.radiusLg),
        ),
      ),
      padding: const EdgeInsets.all(DesignTokens.space20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, titleColor, bodyColor),
          if (!allEmpty) ...[
            const SizedBox(height: DesignTokens.space12),
            _buildSummary(context, bodyColor),
          ],
          const SizedBox(height: DesignTokens.space12),
          if (allEmpty)
            Flexible(
              child: SizedBox(
                height: 240,
                child: EmptyState(
                  icon: Icons.check_circle_outline_rounded,
                  title: LocalizationHelper.dashboardInStock,
                ),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (outOfStock.isNotEmpty) ...[
                    _buildSectionHeader(
                      context,
                      icon: Icons.block_rounded,
                      title: LocalizationHelper.dashboardOutOfStock,
                      color: context.errorColor,
                    ),
                    const SizedBox(height: DesignTokens.space8),
                    ...outOfStock.map(
                      (p) => _ProductTile(
                        product: p,
                        status: _LowStockStatus.outOfStock,
                      ),
                    ),
                    const SizedBox(height: DesignTokens.space16),
                  ],
                  if (lowStock.isNotEmpty) ...[
                    _buildSectionHeader(
                      context,
                      icon: Icons.warning_amber_rounded,
                      title: LocalizationHelper.dashboardLowStockTitle,
                      color: context.warningColor,
                    ),
                    const SizedBox(height: DesignTokens.space8),
                    ...lowStock.map(
                      (p) => _ProductTile(
                        product: p,
                        status: _LowStockStatus.lowStock,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color titleColor, Color bodyColor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(DesignTokens.space8),
          decoration: BoxDecoration(
            color: context.warningColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          ),
          child: Icon(
            Icons.inventory_rounded,
            color: context.warningColor,
            size: 22,
          ),
        ),
        const SizedBox(width: DesignTokens.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LocalizationHelper.dashboardLowStockTitle,
                style: AppTextStyles.headline4(color: titleColor),
              ),
              Text(
                LocalizationHelper.dashboardLowStock,
                style: AppTextStyles.caption(color: bodyColor),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, color: AppColors.grey400),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context, Color bodyColor) {
    final total = lowStock.length + outOfStock.length;
    return Wrap(
      spacing: DesignTokens.space8,
      runSpacing: DesignTokens.space8,
      children: [
        _summaryChip(
          context,
          color: context.errorColor,
          icon: Icons.block_rounded,
          label: '${outOfStock.length}',
        ),
        _summaryChip(
          context,
          color: context.warningColor,
          icon: Icons.warning_amber_rounded,
          label: '${lowStock.length}',
        ),
        _summaryChip(
          context,
          color: context.accent,
          icon: Icons.inventory_2_rounded,
          label: '$total',
        ),
      ],
    );
  }

  Widget _summaryChip(
    BuildContext context, {
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.caption(color: color).copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(
          title,
          style: AppTextStyles.labelMedium(color: color),
        ),
      ],
    );
  }
}

enum _LowStockStatus { lowStock, outOfStock }

class _ProductTile extends StatelessWidget {
  final Product product;
  final _LowStockStatus status;

  const _ProductTile({required this.product, required this.status});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final accentColor = context.accent;
    final titleColor = context.titleColor;

    final isOutOfStock = status == _LowStockStatus.outOfStock;
    final tileColor = isOutOfStock ? context.errorColor : context.warningColor;

    return Container(
      margin: const EdgeInsets.only(bottom: DesignTokens.space8),
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.space12,
        vertical: DesignTokens.space8,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(color: tileColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isOutOfStock
                  ? AppColors.errorLight
                  : AppColors.warningLight,
              borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
            ),
            child: Icon(
              Icons.inventory_2_rounded,
              color: tileColor,
              size: 20,
            ),
          ),
          const SizedBox(width: DesignTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: AppTextStyles.bodyMedium(color: titleColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${product.price.toStringAsFixed(2)} ${LowStockProductsSheet._currency}',
                  style: AppTextStyles.caption(color: accentColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: DesignTokens.space8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tileColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
              border: Border.all(color: tileColor.withValues(alpha: 0.35)),
            ),
            child: Text(
              '${LocalizationHelper.printingQty}: ${QuantityFormat.withUnit(product.quantity, LocalizationHelper.unitLabel(product.unit))}',
              style: AppTextStyles.caption(color: tileColor).copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}