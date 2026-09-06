// lib/widgets/inventory/confirm_delete_dialog.dart

import 'package:flutter/material.dart';
import '../../helpers/localization_helper.dart';
import '../../models/product_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Confirmation dialog before deleting a product.
///
/// Returns `true` when the user confirms the deletion.
Future<bool?> showConfirmDeleteDialog(BuildContext context, Product product) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final titleColor =
          isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
      final bodyColor =
          isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;

      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.delete_rounded,
                color: AppColors.error, size: 20),
          ),
          const SizedBox(width: 10),
          Text(
            LocalizationHelper.inventoryDeleteTitle,
            style: TextStyle(
              color: titleColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${LocalizationHelper.inventoryDeleteConfirm} "${product.name}"?',
              style: TextStyle(color: bodyColor),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.warning_rounded,
                    color: AppColors.error, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    LocalizationHelper.inventoryDeleteWarning,
                    style: AppTextStyles.caption(color: AppColors.error),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Text(
              LocalizationHelper.inventoryDeleteLocalServer,
              style: const TextStyle(
                color: AppColors.warning,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              LocalizationHelper.cancel,
              style: const TextStyle(color: AppColors.grey500),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(LocalizationHelper.inventoryDelete),
          ),
        ],
      );
    },
  );
}