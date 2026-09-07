// lib/widgets/pos/held_orders.dart
// حوارا الطلبات المعلقة: حفظ الطلب الحالي، وعرض/استعادة/حذف الطلبات المحفوظة.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/cart_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../helpers/localization_helper.dart';
import '../../helpers/quantity_format.dart';
import '../../helpers/time_format_helper.dart';

Future<void> showHoldOrderDialog(
  BuildContext context, {
  required CartService cart,
  required String currency,
  required void Function(String message, Color color) showSnackBar,
}) async {
  if (cart.isEmpty) {
    showSnackBar(LocalizationHelper.posEmptyCart, AppColors.warning);
    return;
  }
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final titleColor =
      isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
  final bodyColor =
      isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;

  final ctrl = TextEditingController(
    text: '${LocalizationHelper.posOrderLabel} ${cart.heldOrderCount + 1}',
  );

  showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        title: Text(
          LocalizationHelper.posHoldOrder,
          style: TextStyle(
              color: titleColor, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              LocalizationHelper.posSaveForLater,
              style: TextStyle(color: bodyColor),
            ),
            const SizedBox(height: 8),
            Text(
              '${QuantityFormat.quantity(cart.totalItems)} ${LocalizationHelper.posItems} • ${cart.total.toStringAsFixed(2)} $currency',
              style: AppTextStyles.caption(color: AppColors.primary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: LocalizationHelper.posLabel,
                prefixIcon: const Icon(Icons.label_rounded, size: 18),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              LocalizationHelper.cancel,
              style: TextStyle(color: AppColors.grey500),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              cart.holdOrder(label: ctrl.text);
              Navigator.pop(ctx);
              showSnackBar(
                  LocalizationHelper.posHoldOrder, AppColors.primary);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: AppColors.black,
            ),
            child: Text(LocalizationHelper.posHold),
          ),
        ],
      );
    },
  ).then((_) => ctrl.dispose());
}

Future<bool> _confirmDeleteHeldOrder(BuildContext context, String label) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(LocalizationHelper.posDeleteHeldTitle),
      content: Text(
        '${LocalizationHelper.posDeleteHeldMessage}\n\n"$label"',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(LocalizationHelper.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: Text(LocalizationHelper.delete),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> showHeldOrdersSheet(
  BuildContext context, {
  required CartService cart,
  required String currency,
  required void Function(String message, Color color) showSnackBar,
}) async {
  if (cart.heldOrders.isEmpty) {
    showSnackBar(LocalizationHelper.posNoHeldOrders, AppColors.grey500);
    return;
  }
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final titleColor =
      isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
  final bodyColor =
      isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;

  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor:
          isDark ? AppColors.darkSurface : AppColors.lightSurface,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 450, maxHeight: 550),
        padding: const EdgeInsets.all(18),
        child: Consumer<CartService>(
          builder: (context, cart, child) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${LocalizationHelper.posHeldOrders} (${cart.heldOrders.length})',
                    style: AppTextStyles.headline4(color: titleColor),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.grey400),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: cart.heldOrders.length,
                  separatorBuilder: (_, __) => const Divider(height: 10),
                  itemBuilder: (_, i) {
                    final order = cart.heldOrders[i];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warningLight
                            .withValues(alpha:isDark ? 0.15 : 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.warning.withValues(alpha:0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha:0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.pause_rounded,
                                color: AppColors.warning, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  order.label,
                                  style: AppTextStyles.bodyLarge(
                                      color: titleColor),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${QuantityFormat.quantity(order.totalItems)} ${LocalizationHelper.posItems} • ${order.total.toStringAsFixed(2)} $currency',
                                  style: AppTextStyles.caption(
                                      color: bodyColor, fontSize: 11),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.schedule_rounded,
                                      size: 11,
                                      color: isDark
                                          ? AppColors.textDarkTertiary
                                          : AppColors.textLightTertiary,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      formatTimeAgo(order.createdAt),
                                      style: AppTextStyles.caption(
                                        color: isDark
                                            ? AppColors.textDarkTertiary
                                            : AppColors.textLightTertiary,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  cart.restoreHeldOrder(order.id);
                                },
                                icon: const Icon(Icons.restore_rounded,
                                    color: AppColors.success, size: 22),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () async {
                                  // ⭐ تأكيد قبل حذف الطلب المعلّق
                                  final confirmed =
                                      await _confirmDeleteHeldOrder(
                                          context, order.label);
                                  if (confirmed && context.mounted) {
                                    cart.deleteHeldOrder(order.id);
                                  }
                                },
                                icon: const Icon(Icons.delete_rounded,
                                    color: AppColors.error, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
