// lib/widgets/pos/payment_method_sheet.dart
// ورقة اختيار طريقة الدفع لشاشة البيع.
//
// عرض فقط: كل منطق العمل (تعيين طريقة الدفع، اختيار العميل، ورقة التأكيد)
// يبقى في شاشة البيع ويُنفَّذ عبر ردود النداء.

import 'package:flutter/material.dart';
import '../../services/cart_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/design_tokens.dart';
import '../../theme/screen_palette.dart';
import '../../helpers/localization_helper.dart';
import '../../helpers/quantity_format.dart';

const String _currency = 'DZD';

/// يعرض ورقة اختيار طريقة الدفع.
///
/// تُغلق الورقة قبل تنفيذ رد النداء المطابق، لذا تتعامل ردود النداء مع
/// سياق الشاشة الأصلية وليس سياق الورقة.
Future<void> showPaymentMethodSheet(
  BuildContext context, {
  required CartService cart,
  required VoidCallback onCash,
  required VoidCallback onCard,
  required VoidCallback onDebt,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    // بدون هذا الخيار تُحدَّد الورقة بـ 9/16 من ارتفاع الشاشة، فتفيض على
    // الشاشات القصيرة أو عند تكبير الخط.
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxWidth: 480,
      maxHeight: MediaQuery.of(context).size.height * 0.9,
    ),
    builder: (ctx) => _PaymentMethodSheet(
      cart: cart,
      onCash: onCash,
      onCard: onCard,
      onDebt: onDebt,
    ),
  );
}

class _PaymentMethodSheet extends StatelessWidget {
  const _PaymentMethodSheet({
    required this.cart,
    required this.onCash,
    required this.onCard,
    required this.onDebt,
  });

  final CartService cart;
  final VoidCallback onCash;
  final VoidCallback onCard;
  final VoidCallback onDebt;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(DesignTokens.radiusLg),
        ),
      ),
      child: SafeArea(
        top: false,
        // قابل للتمرير حتى لا تفيض الورقة عند تكبير خط النظام.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: DesignTokens.space12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.bodyColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.space20,
                  DesignTokens.space16,
                  DesignTokens.space12,
                  0,
                ),
                child: _buildHeader(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.space20,
                  DesignTokens.space16,
                  DesignTokens.space20,
                  0,
                ),
                child: _buildTotal(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.space20,
                  DesignTokens.space16,
                  DesignTokens.space20,
                  DesignTokens.space20,
                ),
                child: Column(
                  children: [
                    _PaymentOption(
                      icon: Icons.payments_rounded,
                      title: LocalizationHelper.posCash,
                      subtitle: LocalizationHelper.posCashSubtitle,
                      color: context.accent,
                      isSelected: cart.paymentMethod == 'Cash',
                      onTap: () {
                        Navigator.pop(context);
                        onCash();
                      },
                    ),
                    const SizedBox(height: DesignTokens.space12),
                    _PaymentOption(
                      icon: Icons.credit_card_rounded,
                      title: LocalizationHelper.posEdahabia,
                      subtitle: LocalizationHelper.posEdahabiaSubtitle,
                      color: context.infoColor,
                      isSelected: cart.paymentMethod == 'Edahabia/CIB',
                      onTap: () {
                        Navigator.pop(context);
                        onCard();
                      },
                    ),
                    const SizedBox(height: DesignTokens.space12),
                    _PaymentOption(
                      icon: Icons.account_balance_wallet_rounded,
                      title: LocalizationHelper.posDebt,
                      subtitle: LocalizationHelper.posDebtSubtitle,
                      color: context.warningColor,
                      isSelected: cart.paymentMethod == 'Debt',
                      onTap: () {
                        Navigator.pop(context);
                        onDebt();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LocalizationHelper.posPaymentMethod,
                style: AppTextStyles.headline4(color: context.titleColor),
              ),
              const SizedBox(height: DesignTokens.space2),
              Text(
                '${QuantityFormat.quantity(cart.totalItems)} ${LocalizationHelper.posItems}',
                style: AppTextStyles.caption(color: context.captionColor),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: AppColors.grey400),
          visualDensity: VisualDensity.compact,
          tooltip: LocalizationHelper.cancel,
        ),
      ],
    );
  }

  Widget _buildTotal(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.space16,
        vertical: DesignTokens.space12,
      ),
      decoration: BoxDecoration(
        color: context.surfaceAlt,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.fromBorderSide(DesignTokens.hairline(context)),
      ),
      child: Row(
        children: [
          Text(
            LocalizationHelper.posTotal,
            style: AppTextStyles.labelMedium(color: context.captionColor),
          ),
          const SizedBox(width: DesignTokens.space12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${cart.total.toStringAsFixed(2)} $_currency',
                style: AppTextStyles.headline3(color: context.titleColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// صف طريقة دفع واحدة: مربع أيقونة ملوّن + عنوان + وصف + مؤشر الاختيار.
class _PaymentOption extends StatelessWidget {
  const _PaymentOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    // التعبئة على الداكن تحتاج شفافية أعلى قليلاً لتبقى مرئية.
    final fillAlpha = isDark ? 0.12 : 0.07;

    return Material(
      color: color.withValues(alpha: fillAlpha),
      borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(DesignTokens.space12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            border: Border.all(
              color: color.withValues(alpha: isSelected ? 0.9 : 0.25),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.22 : 0.14),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: DesignTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.titleMedium(color: context.titleColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: DesignTokens.space2),
                    Text(
                      subtitle,
                      style: AppTextStyles.caption(
                        color: context.captionColor,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DesignTokens.space8),
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: isSelected ? color : AppColors.grey400,
                size: isSelected ? 22 : 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
