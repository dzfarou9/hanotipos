// lib/screens/suppliers_screen.dart

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/supplier_model.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/screen_palette.dart';
import '../widgets/app_snackbar.dart';
import '../theme/design_tokens.dart';
import '../widgets/empty_state.dart';
import 'purchase_screen.dart';
import 'purchases_history_screen.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen>
    with SingleTickerProviderStateMixin {
  final SyncService _sync = SyncService();
  final TextEditingController _searchController = TextEditingController();
  List<Supplier> _suppliers = [];
  List<Supplier> _filtered = [];
  bool _loading = true;

  // ⭐ إحصائيات الملخص + عدّاد مشتريات كل مورد
  int _purchaseCount = 0;
  double _totalSpent = 0.0;
  Map<String, int> _purchasesBySupplier = {};
  static const String _currency = 'DZD';

  late final AnimationController _counterController;
  late final Animation<double> _counterAnimation;

  @override
  void initState() {
    super.initState();
    _counterController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _counterAnimation = CurvedAnimation(
      parent: _counterController,
      curve: Curves.easeOutCubic,
    );
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _counterController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _sync.getSuppliers();

      // ⭐ إحصائيات المشتريات: مسحة واحدة، صافي المرتجعات مخصوم
      final purchases = DatabaseService.instance.getAllPurchases();
      final bySupplier = <String, int>{};
      double totalSpent = 0.0;
      int purchaseCount = 0;
      for (final p in purchases) {
        if (p.isReturn) {
          totalSpent -= p.total;
          continue;
        }
        purchaseCount++;
        bySupplier[p.supplierId] = (bySupplier[p.supplierId] ?? 0) + 1;
        totalSpent += p.remainingTotal;
      }

      if (!mounted) return;
      setState(() {
        _suppliers = list;
        _filtered = _applyFilter(list);
        _purchaseCount = purchaseCount;
        _totalSpent = totalSpent;
        _purchasesBySupplier = bySupplier;
        _loading = false;
      });
      _counterController
        ..reset()
        ..forward();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _suppliers = [];
        _filtered = [];
        _purchaseCount = 0;
        _totalSpent = 0.0;
        _purchasesBySupplier = {};
        _loading = false;
      });
    }
  }

  List<Supplier> _applyFilter(List<Supplier> list) {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list
        .where((s) =>
            s.name.toLowerCase().contains(q) || (s.phone ?? '').contains(q))
        .toList();
  }

  void _onSearch(String value) {
    setState(() => _filtered = _applyFilter(_suppliers));
  }

  Future<void> _openSupplierForm({Supplier? supplier}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SupplierFormSheet(
        supplier: supplier,
        onSaved: () {
          Navigator.pop(context);
          _showSnack(context.successColor, 'suppliers.savedLocally'.tr());
          _load();
        },
      ),
    );
  }

  Future<void> _confirmDelete(Supplier supplier) async {
    final isDark = context.isDark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusMd)),
        title: Text(
          'suppliers.deleteTitle'.tr(),
          style: AppTextStyles.headline4(color: dialogContext.titleColor),
        ),
        content: Text(
          'suppliers.deleteMessage'.tr(namedArgs: {'name': supplier.name}),
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
              style: AppTextStyles.bodyMedium(color: dialogContext.errorColor),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _sync.deleteSupplier(supplier.id);
    } catch (_) {
      if (mounted) {
        _showSnack(context.errorColor, 'common.error'.tr());
      }
      return;
    }
    _load();
  }

  void _openSupplierOptions(Supplier supplier) {
    final accentColor = context.accent;
    final titleColor = context.titleColor;
    final bodyColor = context.bodyColor;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: bodyColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                supplier.name,
                style: AppTextStyles.headline4(color: titleColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: Icon(Icons.edit_rounded, color: accentColor),
              title: Text(
                'suppliers.edit'.tr(),
                style: AppTextStyles.bodyMedium(color: bodyColor),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _openSupplierForm(supplier: supplier);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.add_shopping_cart_rounded,
                color: accentColor,
              ),
              title: Text(
                'suppliers.newPurchase'.tr(),
                style: AppTextStyles.bodyMedium(color: bodyColor),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PurchaseScreen(
                      initialSupplierId: supplier.id,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.receipt_long_rounded,
                color: accentColor,
              ),
              title: Text(
                'purchases.title'.tr(),
                style: AppTextStyles.bodyMedium(color: bodyColor),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PurchasesHistoryScreen(
                      initialSupplierId: supplier.id,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_rounded, color: context.errorColor),
              title: Text(
                'suppliers.deleteTitle'.tr(),
                style: AppTextStyles.bodyMedium(color: bodyColor),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDelete(supplier);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final accentColor = context.accent;
    final titleColor = context.titleColor;
    final bodyColor = context.bodyColor;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: Text(
          'suppliers.title'.tr(),
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
      floatingActionButton: FloatingActionButton(
        heroTag: 'suppliers_add_fab',
        onPressed: () => _openSupplierForm(),
        tooltip: 'suppliers.add'.tr(),
        backgroundColor: accentColor,
        foregroundColor: isDark ? AppColors.black : AppColors.white,
        child: const Icon(Icons.add_rounded),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: accentColor))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: _buildSummaryCard(isDark, accentColor),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearch,
                    decoration: InputDecoration(
                      hintText: 'suppliers.search'.tr(),
                      prefixIcon:
                          Icon(Icons.search_rounded, color: accentColor),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: Icon(Icons.close_rounded,
                                  size: 18, color: bodyColor),
                              onPressed: () {
                                _searchController.clear();
                                _onSearch('');
                              },
                            ),
                      filled: true,
                      fillColor: isDark
                          ? AppColors.darkSurfaceAlt
                          : AppColors.lightSurfaceAlt,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _filtered.isEmpty
                      ? EmptyState(
                          icon: Icons.local_shipping_rounded,
                          title: 'suppliers.empty'.tr(),
                          subtitle: _suppliers.isEmpty
                              ? 'suppliers.emptyHint'.tr()
                              : null,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 90),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final supplier = _filtered[i];
                            final purchaseCount =
                                _purchasesBySupplier[supplier.id] ?? 0;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(DesignTokens.radiusLg),
                                side: BorderSide(
                                  color: isDark
                                      ? AppColors.grey700.withValues(alpha: 0.3)
                                      : AppColors.grey200.withValues(alpha: 0.6),
                                  width: 1,
                                ),
                              ),
                              child: ListTile(
                                onTap: () => _openSupplierOptions(supplier),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      accentColor.withValues(alpha: 0.12),
                                  child: Text(
                                    supplier.name.isNotEmpty
                                        ? supplier.name[0].toUpperCase()
                                        : '?',
                                    style: AppTextStyles.bodyMedium(
                                      color: accentColor,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  supplier.name,
                                  style: AppTextStyles.bodyMedium(
                                      color: titleColor),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  supplier.phone ?? '',
                                  style: AppTextStyles.bodySmall(
                                      color: bodyColor),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color:
                                        accentColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(
                                        DesignTokens.radiusPill),
                                  ),
                                  child: Text(
                                    'suppliers.purchasesCount'.tr(namedArgs: {
                                      'count': '$purchaseCount',
                                    }),
                                    style: AppTextStyles.bodySmall(
                                      color: accentColor,
                                    ),
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  // ⭐ بطاقة الملخص: نفس لغة بطاقة الزبائن والترحيب — تدرج زمردي ثلاثي
  // + حلقة زخرفية + لوحتان زجاجيتان (عدد المشتريات وقيمتها).
  Widget _buildSummaryCard(bool isDark, Color accentColor) {
    final onCard = isDark ? AppColors.textDarkPrimary : AppColors.white;
    final onCardSecondary =
        isDark ? AppColors.textDarkSecondary : AppColors.white.withValues(alpha: 0.8);
    final onCardTertiary =
        isDark ? AppColors.textDarkTertiary : AppColors.white.withValues(alpha: 0.65);
    final glassColor =
        (isDark ? AppColors.white : AppColors.black).withValues(alpha: 0.10);
    final glassBorder =
        (isDark ? AppColors.white : AppColors.black).withValues(alpha: 0.16);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  AppColors.darkSurface,
                  AppColors.darkSurfaceAlt,
                  AppColors.darkSurface,
                ]
              : [
                  AppColors.primaryDark,
                  AppColors.primary,
                  AppColors.secondaryDark,
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        border: isDark
            ? Border.all(color: accentColor.withValues(alpha: 0.3), width: 1.5)
            : null,
        boxShadow: DesignTokens.accentGlow(accentColor, opacity: 0.22),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        child: Stack(
          children: [
            Positioned(
              top: -50,
              right: -60,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.white
                        .withValues(alpha: isDark ? 0.05 : 0.08),
                    width: 20,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'suppliers.summaryTotalSpent'.tr(),
                    style: AppTextStyles.caption(
                      color: onCardSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedBuilder(
                    animation: _counterAnimation,
                    builder: (context, child) {
                      final displayValue =
                          _totalSpent * _counterAnimation.value;
                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          '${displayValue.toStringAsFixed(0)} $_currency',
                          style: AppTextStyles.headline1(color: onCard),
                          maxLines: 1,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: glassColor,
                            borderRadius:
                                BorderRadius.circular(DesignTokens.radiusMd),
                            border: Border.all(color: glassBorder, width: 1),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.local_shipping_rounded,
                                color: onCard.withValues(alpha: 0.85),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_suppliers.length}',
                                      style: AppTextStyles.headline4(
                                          color: onCard),
                                      maxLines: 1,
                                    ),
                                    Text(
                                      'suppliers.summarySuppliers'.tr(),
                                      style: AppTextStyles.caption(
                                        color: onCardTertiary,
                                        fontSize: 10,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: glassColor,
                            borderRadius:
                                BorderRadius.circular(DesignTokens.radiusMd),
                            border: Border.all(color: glassBorder, width: 1),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.shopping_cart_rounded,
                                color: onCard.withValues(alpha: 0.85),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$_purchaseCount',
                                      style: AppTextStyles.headline4(
                                          color: onCard),
                                      maxLines: 1,
                                    ),
                                    Text(
                                      'suppliers.summaryPurchases'.tr(),
                                      style: AppTextStyles.caption(
                                        color: onCardTertiary,
                                        fontSize: 10,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierFormSheet extends StatefulWidget {
  const _SupplierFormSheet({this.supplier, required this.onSaved});

  final Supplier? supplier;
  final VoidCallback onSaved;

  @override
  State<_SupplierFormSheet> createState() => _SupplierFormSheetState();
}

class _SupplierFormSheetState extends State<_SupplierFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _notesController;
  bool _saving = false;

  bool get _isEditing => widget.supplier != null;

  @override
  void initState() {
    super.initState();
    final supplier = widget.supplier;
    _nameController = TextEditingController(text: supplier?.name ?? '');
    _phoneController = TextEditingController(text: supplier?.phone ?? '');
    _addressController = TextEditingController(text: supplier?.address ?? '');
    _notesController = TextEditingController(text: supplier?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;
    setState(() => _saving = true);

    try {
      if (_isEditing) {
        await SyncService().updateSupplier(
          id: widget.supplier!.id,
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim().isNotEmpty
              ? _phoneController.text.trim()
              : null,
          address: _addressController.text.trim().isNotEmpty
              ? _addressController.text.trim()
              : null,
          notes: _notesController.text.trim().isNotEmpty
              ? _notesController.text.trim()
              : null,
        );
      } else {
        await SyncService().addSupplier(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim().isNotEmpty
              ? _phoneController.text.trim()
              : null,
          address: _addressController.text.trim().isNotEmpty
              ? _addressController.text.trim()
              : null,
          notes: _notesController.text.trim().isNotEmpty
              ? _notesController.text.trim()
              : null,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackBar.error(context, 'common.error'.tr());
      return;
    }

    if (!mounted) return;
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final accentColor = context.accent;
    final titleColor = context.titleColor;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _isEditing ? Icons.edit_rounded : Icons.add_rounded,
                        color: accentColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isEditing
                            ? 'suppliers.edit'.tr()
                            : 'suppliers.add'.tr(),
                        style: AppTextStyles.headline4(color: titleColor),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.grey400),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'suppliers.name'.tr(),
                    prefixIcon:
                        const Icon(Icons.storefront_rounded, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'suppliers.nameRequired'.tr()
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'suppliers.phone'.tr(),
                    prefixIcon: const Icon(Icons.phone_rounded, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _addressController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'suppliers.address'.tr(),
                    prefixIcon:
                        const Icon(Icons.location_on_rounded, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'suppliers.notes'.tr(),
                    prefixIcon:
                        const Icon(Icons.notes_rounded, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _isEditing ? Icons.save_rounded : Icons.add_rounded,
                            size: 18,
                          ),
                    label: Text(
                        _isEditing ? 'common.save'.tr() : 'suppliers.add'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor:
                          isDark ? AppColors.black : AppColors.white,
                      disabledBackgroundColor:
                          accentColor.withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
