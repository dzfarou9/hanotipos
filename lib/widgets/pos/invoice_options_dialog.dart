// lib/widgets/pos/invoice_options_dialog.dart
// حوار خيارات الفاتورة (طباعة/مشاركة/حفظ) لشاشة البيع.

import 'package:flutter/material.dart';
import '../../models/cart_item_model.dart';
import '../../services/printing_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../helpers/localization_helper.dart';

Future<void> showInvoiceOptionsDialog(
  BuildContext context, {
  required List<CartItem> items,
  required double subtotal,
  required double discount,
  required double tax,
  required double taxRate,
  required double total,
  required String paymentMethod,
  required String saleId,
  required DateTime date,
  required void Function(String message, Color color) showSnackBar,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final accentColor = isDark ? AppColors.neonOrange : AppColors.primary;
  final titleColor =
      isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
  final bodyColor =
      isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;

  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor:
          isDark ? AppColors.darkSurface : AppColors.lightSurface,
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.picture_as_pdf_rounded,
                      color: accentColor, size: 24),
                ),
                const SizedBox(width: 12),
                Text(
                  LocalizationHelper.posInvoiceOptions,
                  style: AppTextStyles.headline4(color: titleColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              LocalizationHelper.posInvoiceChooseAction,
              style: AppTextStyles.bodyMedium(color: bodyColor),
            ),
            const SizedBox(height: 20),
            Divider(
              color: isDark
                  ? AppColors.grey700.withValues(alpha:0.3)
                  : AppColors.grey200,
            ),
            const SizedBox(height: 16),
            _buildInvoiceOption(
              context: context,
              icon: Icons.print_rounded,
              title: LocalizationHelper.posInvoicePrint,
              subtitle: LocalizationHelper.posInvoicePrintSubtitle,
              color: AppColors.info,
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await PrintingService.printInvoice(
                    items: items,
                    subtotal: subtotal,
                    discount: discount,
                    tax: tax,
                    taxRate: taxRate,
                    total: total,
                    paymentMethod: paymentMethod,
                    saleId: saleId,
                    date: date,
                  );
                } catch (e) {
                  showSnackBar(
                    '${LocalizationHelper.error} ${LocalizationHelper.posInvoicePrint}',
                    AppColors.error,
                  );
                }
              },
              isDark: isDark,
              accentColor: accentColor,
              titleColor: titleColor,
              bodyColor: bodyColor,
            ),
            const SizedBox(height: 12),
            _buildInvoiceOption(
              context: context,
              icon: Icons.share_rounded,
              title: LocalizationHelper.posInvoiceShare,
              subtitle: LocalizationHelper.posInvoiceShareSubtitle,
              color: AppColors.success,
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await PrintingService.shareInvoice(
                    items: items,
                    subtotal: subtotal,
                    discount: discount,
                    tax: tax,
                    taxRate: taxRate,
                    total: total,
                    paymentMethod: paymentMethod,
                    saleId: saleId,
                    date: date,
                  );
                  showSnackBar(
                      LocalizationHelper.posInvoiceShare, AppColors.success);
                } catch (e) {
                  showSnackBar(
                    '${LocalizationHelper.error} ${LocalizationHelper.posInvoiceShare}',
                    AppColors.error,
                  );
                }
              },
              isDark: isDark,
              accentColor: accentColor,
              titleColor: titleColor,
              bodyColor: bodyColor,
            ),
            const SizedBox(height: 12),
            _buildInvoiceOption(
              context: context,
              icon: Icons.download_rounded,
              title: LocalizationHelper.posInvoiceDownload,
              subtitle: LocalizationHelper.posInvoiceDownloadSubtitle,
              color: AppColors.warning,
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  final saved = await PrintingService.saveInvoice(
                    items: items,
                    subtotal: subtotal,
                    discount: discount,
                    tax: tax,
                    taxRate: taxRate,
                    total: total,
                    paymentMethod: paymentMethod,
                    saleId: saleId,
                    date: date,
                  );
                  if (saved) {
                    showSnackBar(LocalizationHelper.posInvoiceDownload,
                        AppColors.success);
                  }
                } catch (e) {
                  showSnackBar(
                    '${LocalizationHelper.error} ${LocalizationHelper.posInvoiceDownload}',
                    AppColors.error,
                  );
                }
              },
              isDark: isDark,
              accentColor: accentColor,
              titleColor: titleColor,
              bodyColor: bodyColor,
            ),
            const SizedBox(height: 16),
            Divider(
              color: isDark
                  ? AppColors.grey700.withValues(alpha:0.3)
                  : AppColors.grey200,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.grey500,
                  side: BorderSide(color: AppColors.grey400),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  LocalizationHelper.posInvoiceClose,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildInvoiceOption({
  required BuildContext context,
  required IconData icon,
  required String title,
  required String subtitle,
  required Color color,
  required VoidCallback onTap,
  required bool isDark,
  required Color accentColor,
  required Color titleColor,
  required Color bodyColor,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha:0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyMedium(color: titleColor),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style:
                      AppTextStyles.caption(color: bodyColor, fontSize: 11),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: isDark ? AppColors.grey500 : AppColors.grey400,
          ),
        ],
      ),
    ),
  );
}
