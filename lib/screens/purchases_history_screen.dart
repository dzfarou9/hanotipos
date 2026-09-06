// lib/screens/purchases_history_screen.dart

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/purchase_model.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../helpers/localization_helper.dart';
import '../widgets/app_snackbar.dart';
import '../theme/design_tokens.dart';
import '../theme/screen_palette.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_chip.dart';
import 'supplier_return_screen.dart';

/// سجل المشتريات: قائمة عمليات الشراء والمرتجعات مع التفاصيل والحذف
/// ومدخل الإرجاع للمورد.
class PurchasesHistoryScreen extends StatefulWidget {
  const PurchasesHistoryScreen({super.key, this.initialSupplierId});

  final String? initialSupplierId;

  @override
  State<PurchasesHistoryScreen> createState() =>
      _PurchasesHistoryScreenState();
}

class _PurchasesHistoryScreenState extends State<PurchasesHistoryScreen> {
  // بنفسجي المرتجع هو نفس لون «مرتجع لمورد» في حركات المخزون سابقاً.
  // ⭐ تركوازي الثانوية: يميز شارة «شراء» عن أخضر الهوية الذي صار قريباً منها
  static const Color _purchaseColor = AppColors.secondary;
  static const Color _returnColor = Color(0xFF8B5CF6);

  static const String _currency = 'DZD';

  final SyncService _sync = SyncService();
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  List<Purchase> _purchases = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // بحث بالمورد أو رقم الفاتورة
  List<Purchase> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _purchases;
    return _purchases
        .where((p) =>
            p.supplierName.toLowerCase().contains(q) ||
            (p.invoiceNumber ?? '').toLowerCase().contains(q))
        .toList();
  }

  Future<void> _load() async {
    try {
      final supplierId = widget.initialSupplierId;
      final list = supplierId != null
          ? DatabaseService.instance.getPurchasesBySupplier(supplierId)
          : await _sync.getPurchases();
      if (!mounted) return;
      setState(() {
        _purchases = list;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _purchases = [];
        _isLoading = false;
      });
    }
  }

  Color _typeColor(Purchase purchase) =>
      purchase.isReturn ? _returnColor : _purchaseColor;

  String _typeLabel(Purchase purchase) =>
      purchase.isReturn ? 'purchases.return'.tr() : 'purchases.purchase'.tr();

  IconData _typeIcon(Purchase purchase) => purchase.isReturn
      ? Icons.reply_rounded
      : Icons.shopping_bag_rounded;

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

  // ⭐ حذف العملية: إغلاق الشيت أولاً ثم تأكيد ثم تنفيذ الحذف.
  // فشل سياسة المخزون يظهر كـ SnackBar دون انهيار.
  Future<void> _confirmDelete(Purchase purchase) async {
    final isDark = context.isDark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusMd)),
        title: Text(
          'purchases.deleteTitle'.tr(),
          style: AppTextStyles.headline4(color: dialogContext.titleColor),
        ),
        content: Text(
          purchase.isReturn
              ? 'purchases.deleteMessageReturn'.tr()
              : 'purchases.deleteMessagePurchase'.tr(),
          style: AppTextStyles.bodyMedium(color: dialogContext.bodyColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'common.cancel'.tr(),
              style: AppTextStyles.bodyMedium(
                color: dialogContext.bodyColor,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'common.delete'.tr(),
              style:
                  AppTextStyles.bodyMedium(color: dialogContext.errorColor),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _sync.deletePurchaseById(purchase.id);
    } catch (e) {
      if (mounted) {
        _showSnack(context.errorColor, e.toString());
      }
      return;
    }
    if (mounted) {
      _showSnack(context.successColor, 'common.success'.tr());
    }
    _load();
  }

  void _openDetails(Purchase purchase) {
    final isDark = context.isDark;
    final accentColor = context.accent;
    final titleColor = context.titleColor;
    final bodyColor = context.bodyColor;
    final typeColor = _typeColor(purchase);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: bodyColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'purchases.details'.tr(),
                      style: AppTextStyles.headline4(color: titleColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.grey400),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusChip(
                    label: _typeLabel(purchase),
                    color: typeColor,
                    icon: _typeIcon(purchase),
                  ),
                  if (purchase.isFullyReturned)
                    StatusChip(
                      label: 'purchases.fullyReturned'.tr(),
                      color: _returnColor,
                      icon: Icons.reply_rounded,
                    )
                  else if (purchase.returnedItems?.isNotEmpty ?? false)
                    StatusChip(
                      label: 'purchases.partiallyReturned'.tr(),
                      color: const Color(0xFFF59E0B),
                      icon: Icons.reply_rounded,
                    ),
                  StatusChip(
                    label: '#${_shortId(purchase.id)}',
                    color: accentColor,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildDetailRow(
                LocalizationHelper.suppliersTitle,
                purchase.supplierName.isEmpty
                    ? '-'
                    : purchase.supplierName,
                bodyColor,
              ),
              const SizedBox(height: 8),
              _buildDetailRow(
                LocalizationHelper.dashboardDate,
                _formatFullDate(purchase.createdAt),
                bodyColor,
              ),
              if ((purchase.invoiceNumber ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildDetailRow('purchases.invoiceNumber'.tr(),
                    purchase.invoiceNumber!, bodyColor),
              ],
              const SizedBox(height: 8),
              _buildDetailRow(
                'purchases.total'.tr(),
                '${purchase.total.toStringAsFixed(2)} $_currency',
                accentColor,
              ),
              if (purchase.returnTotal != null &&
                  purchase.returnTotal! > 0) ...[
                const SizedBox(height: 8),
                _buildDetailRow(
                  'purchases.returnToSupplier'.tr(),
                  '-${purchase.returnTotal!.toStringAsFixed(2)} $_currency',
                  _returnColor,
                ),
                const SizedBox(height: 8),
                _buildDetailRow(
                  'purchases.availableForReturn'.tr(),
                  '${purchase.remainingTotal.toStringAsFixed(2)} $_currency',
                  accentColor,
                ),
              ],
              if (purchase.note != null && purchase.note!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildDetailRow('purchases.note'.tr(), purchase.note!,
                    bodyColor),
              ],
              const SizedBox(height: 12),
              Divider(color: context.dividerColor),
              const SizedBox(height: 8),
              Text(
                '${'purchases.items'.tr()} (${purchase.items.length})',
                style: AppTextStyles.bodyLarge(color: titleColor),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: purchase.items.length,
                  itemBuilder: (_, i) {
                    final item = purchase.items[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              item.productName,
                              style:
                                  AppTextStyles.bodyMedium(color: titleColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${item.quantity} × ${item.costPrice.toStringAsFixed(2)}',
                              style:
                                  AppTextStyles.caption(color: bodyColor),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${item.subtotal.toStringAsFixed(2)} $_currency',
                              style: AppTextStyles.caption(
                                  color: bodyColor, fontSize: 12),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              // زر الإرجاع يظهر فقط للأصلية القابلة للإرجاع
              if (purchase.canBeReturned)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              SupplierReturnScreen(originalPurchase: purchase),
                        ),
                      );
                      _load();
                    },
                    icon: const Icon(Icons.reply_rounded, size: 18),
                    label: Text('purchases.returnToSupplier'.tr()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      side:
                          BorderSide(color: accentColor.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              if (purchase.canBeReturned) const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _confirmDelete(purchase);
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text('common.delete'.tr()),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.errorColor,
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
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          flex: 1,
          child: Text(
            label,
            style: AppTextStyles.bodySmall(color: AppColors.grey500),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            value,
            style: AppTextStyles.bodyMedium(color: color),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ⭐ تاريخ نسبي: "اليوم" / "أمس" / dd/MM/yyyy.
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    if (day == today) return LocalizationHelper.dashboardToday;
    if (day == today.subtract(const Duration(days: 1))) {
      return LocalizationHelper.dashboardYesterday;
    }
    return _formatFullDate(date);
  }

  String _formatFullDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _shortId(String id) {
    return id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = context.accent;
    final titleColor = context.titleColor;

    return Scaffold(
      backgroundColor: context.scaffoldColor,
      appBar: AppBar(
        title: Text(
          'purchases.title'.tr(),
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
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: accentColor))
          : RefreshIndicator(
              onRefresh: _load,
              color: accentColor,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'purchases.searchHint'.tr(),
                        prefixIcon: const Icon(Icons.search_rounded, size: 22),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.close_rounded,
                                    size: 20),
                              ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _purchases.isEmpty
                        ? EmptyState(
                            icon: Icons.shopping_bag_rounded,
                            title: 'purchases.empty'.tr(),
                            subtitle: 'purchases.emptyHint'.tr(),
                          )
                        : _filtered.isEmpty
                            ? EmptyState(
                                icon: Icons.search_off_rounded,
                                title: 'purchases.noResults'.tr(),
                                subtitle: 'purchases.noResultsSub'.tr(),
                              )
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 4, 20, 24),
                                itemCount: _filtered.length,
                                itemBuilder: (_, i) =>
                                    _buildPurchaseCard(_filtered[i]),
                              ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPurchaseCard(Purchase purchase) {
    final typeColor = _typeColor(purchase);
    final titleColor = context.titleColor;
    final bodyColor = context.bodyColor;
    final captionColor = context.captionColor;
    final hasReturns = (purchase.returnedItems?.isNotEmpty ?? false);
    final displayTotal =
        hasReturns ? purchase.remainingTotal : purchase.total;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusMd)),
      child: InkWell(
        onTap: () => _openDetails(purchase),
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusChip(
                    label: _typeLabel(purchase),
                    color: typeColor,
                    icon: _typeIcon(purchase),
                  ),
                  if (hasReturns) ...[
                    const SizedBox(width: 6),
                    StatusChip(
                      label: purchase.isFullyReturned
                          ? 'purchases.fullyReturned'.tr()
                          : 'purchases.partiallyReturned'.tr(),
                      color: purchase.isFullyReturned
                          ? _returnColor
                          : const Color(0xFFF59E0B),
                      icon: Icons.reply_rounded,
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '${displayTotal.toStringAsFixed(2)} $_currency',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                purchase.supplierName.isEmpty ? '-' : purchase.supplierName,
                style: AppTextStyles.bodyMedium(color: titleColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatDate(purchase.createdAt),
                      style: AppTextStyles.caption(
                          color: captionColor, fontSize: 11),
                    ),
                  ),
                  if ((purchase.invoiceNumber ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        '#${purchase.invoiceNumber}',
                        style: AppTextStyles.caption(
                            color: bodyColor, fontSize: 11),
                      ),
                    ),
                  Text(
                    '${purchase.items.length} ${'purchases.items'.tr()}',
                    style: AppTextStyles.caption(
                        color: bodyColor, fontSize: 11),
                  ),
                ],
              ),
              if (purchase.note != null && purchase.note!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  purchase.note!,
                  style: AppTextStyles.caption(
                      color: captionColor, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
