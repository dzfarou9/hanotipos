// lib/widgets/pos/checkout_confirmation_sheet.dart
// ورقة تأكيد الدفع وحوار معالجة عملية البيع لشاشة البيع.

import 'package:flutter/material.dart';
import '../../models/cart_item_model.dart';
import '../../services/cart_service.dart';
import '../../services/database_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../helpers/localization_helper.dart';
import '../../helpers/quantity_format.dart';
import 'receipt_formatting.dart';

const String _currency = 'DZD';

Future<void> showCheckoutConfirmationSheet(
  BuildContext context, {
  required CartService cart,
  required DatabaseService db,
  required void Function(String message) onError,
  required VoidCallback onConfirm,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
  final titleColor =
      isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
  final bodyColor =
      isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;
  final cardBg =
      isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      constraints: const BoxConstraints(maxWidth: 480, maxHeight: 650),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.successLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: AppColors.success, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      LocalizationHelper.posConfirmSale,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accentColor.withValues(alpha:0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    Divider(color: accentColor.withValues(alpha:0.3)),
                    const SizedBox(height: 8),
                    buildPosReceiptRow(
                      LocalizationHelper.posDateTime,
                      formatPosDateTime(DateTime.now()),
                      bodyColor,
                    ),
                    const SizedBox(height: 4),
                    buildPosReceiptRow(
                      LocalizationHelper.dashboardPayment,
                      LocalizationHelper.paymentMethod(cart.paymentMethod),
                      bodyColor,
                    ),
                    if (cart.customerName != null) ...[
                      const SizedBox(height: 4),
                      buildPosReceiptRow(
                        LocalizationHelper.customersName,
                        cart.customerName!,
                        bodyColor,
                      ),
                    ],
                    if (cart.paymentMethod == 'Debt') ...[
                      const SizedBox(height: 4),
                      buildPosReceiptRow(
                        LocalizationHelper.customersCredit,
                        '${cart.total.toStringAsFixed(2)} $_currency',
                        accentColor,
                      ),
                    ],
                    const SizedBox(height: 4),
                    buildPosReceiptRow(
                      LocalizationHelper.posItems,
                      '${QuantityFormat.quantity(cart.totalItems)} ${LocalizationHelper.posProductsTitle}',
                      bodyColor,
                    ),
                    const SizedBox(height: 12),
                    Divider(color: accentColor.withValues(alpha:0.3)),
                    const SizedBox(height: 8),
                    Text(
                      LocalizationHelper.posProductsTitle,
                      style: AppTextStyles.bodyMedium(
                          color: titleColor, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: cart.items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final item = cart.items[i];
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha:0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  QuantityFormat.withUnit(item.quantity, LocalizationHelper.unitLabel(item.product.unit)),
                                  style: AppTextStyles.caption(
                                      color: accentColor, fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.product.name,
                                  style: AppTextStyles.bodySmall(
                                          color: bodyColor)
                                      .copyWith(fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${item.subtotal.toStringAsFixed(2)} $_currency',
                                style: AppTextStyles.bodySmall(
                                    color: accentColor, fontSize: 12),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Divider(color: accentColor.withValues(alpha:0.3)),
                    const SizedBox(height: 8),
                    buildPosReceiptRow(
                      LocalizationHelper.posSubtotal,
                      '${cart.subtotal.toStringAsFixed(2)} $_currency',
                      bodyColor,
                    ),
                    if (cart.discount > 0) ...[
                      const SizedBox(height: 4),
                      buildPosReceiptRow(
                        LocalizationHelper.posDiscount,
                        '-${cart.discount.toStringAsFixed(2)} $_currency',
                        AppColors.error,
                      ),
                    ],
                    if (cart.taxRate > 0) ...[
                      const SizedBox(height: 4),
                      buildPosReceiptRow(
                        '${LocalizationHelper.posTax} (${cart.taxRate}%)',
                        '${cart.taxAmount.toStringAsFixed(2)} $_currency',
                        bodyColor,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        border: Border(
                            top: BorderSide(color: accentColor, width: 2)),
                      ),
                    ),
                    buildPosReceiptRow(
                      LocalizationHelper.posTotal,
                      '${cart.total.toStringAsFixed(2)} $_currency',
                      accentColor,
                      isBold: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.grey500,
                      side: const BorderSide(color: AppColors.grey400),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      LocalizationHelper.cancel,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // نسخة من العناصر للتحقق من توفر الكميات
                      final itemsCopy = List<CartItem>.from(cart.items);

                      // ⭐ التحقق من توفر الكميات قبل إغلاق النافذة
                      // (يبقى المستخدم في نفس النافذة عند فشل التحقق)
                      for (var item in itemsCopy) {
                        final product = db.getProductById(item.product.id);
                        if (product == null) {
                          onError(LocalizationHelper.posProductNotFound);
                          return;
                        }
                        if (QuantityFormat.exceedsQty(item.quantity, product.quantity)) {
                          onError(
                            '${product.name}: '
                            '${LocalizationHelper.posOutOfStock}'
                            ' (${QuantityFormat.quantity(product.quantity)})',
                          );
                          return;
                        }
                      }

                      Navigator.pop(ctx);
                      onConfirm();
                    },
                    icon: const Icon(Icons.payment_rounded, size: 16),
                    label: Text(
                      LocalizationHelper.posCompleteSale,
                      style: const TextStyle(fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
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
          ],
        ),
      ),
  );
}

Future<void> showPosProcessingDialog(BuildContext context) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
              LocalizationHelper.posProcessingSale,
              style: AppTextStyles.bodyMedium(
                color: isDark
                    ? AppColors.textDarkPrimary
                    : AppColors.textLightPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              LocalizationHelper.posPleaseWait,
              style: AppTextStyles.caption(
                color: isDark
                    ? AppColors.textDarkTertiary
                    : AppColors.textLightTertiary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
