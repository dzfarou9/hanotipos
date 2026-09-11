// lib/screens/customers_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/skeleton.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:pos_app/models/customer_model.dart';
import 'package:pos_app/services/database_service.dart';
import 'package:pos_app/services/sync_service.dart';
import 'package:pos_app/helpers/debt_ledger_helper.dart';
import 'package:pos_app/models/debt_transaction_model.dart';
import 'package:pos_app/theme/app_colors.dart';
import 'package:pos_app/theme/app_text_styles.dart';
import 'package:pos_app/theme/screen_palette.dart';
import 'package:pos_app/widgets/app_snackbar.dart';
import 'package:pos_app/theme/design_tokens.dart';
import 'package:pos_app/widgets/empty_state.dart';
import 'package:pos_app/screens/customer_detail_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen>
    with SingleTickerProviderStateMixin {
  final SyncService _sync = SyncService();
  final TextEditingController _searchController = TextEditingController();
  List<Customer> _customers = [];
  List<Customer> _filtered = [];
  bool _loading = true;

  // â­ Ø¥Ø­ØµØ§Ø¦ÙŠØ§Øª Ø§Ù„Ù…Ù„Ø®Øµ
  double _totalOwed = 0.0;
  int _openDebts = 0;
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
    SyncService().dataChangeNotifier.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _counterController.dispose();
    SyncService().dataChangeNotifier.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    _load();
  }

  Future<void> _load() async {
    try {
      final list = DatabaseService.instance.getAllCustomers();

      // â­ Ø¥Ø­ØµØ§Ø¦ÙŠØ§Øª Ø§Ù„Ù…Ù„Ø®Øµ ØªÙØ­Ø³Ø¨ ÙÙŠ Ù…Ø³Ø­Ø© ÙˆØ§Ø­Ø¯Ø© Ø¹Ù„Ù‰ ÙƒÙ„ ØµÙÙˆÙ Ø§Ù„Ø¯ÙØªØ±:
      // ØªØ¬Ù…ÙŠØ¹ Ø§Ù„ØµÙÙˆÙ Ø­Ø³Ø¨ Ø§Ù„Ø²Ø¨ÙˆÙ†ØŒ Ø¯ÙØªØ± Ù„ÙƒÙ„ Ø²Ø¨ÙˆÙ†ØŒ Ø«Ù…:
      //  - Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø§Ù„Ù…Ø³ØªØ­Ù‚ = Ù…Ø¬Ù…ÙˆØ¹ Ø§Ù„Ø£Ø±ØµØ¯Ø© Ø§Ù„Ù…ÙˆØ¬Ø¨Ø© (Ù†ÙØ³ Ù…Ù†Ø·Ù‚ computeTotalDebt)
      //  - Ø§Ù„Ø¯ÙŠÙˆÙ† Ø§Ù„Ù…ÙØªÙˆØ­Ø© = Ø¹Ø¯Ù‘Ø§Ø¯ ØºÙŠØ± Ø§Ù„Ù…Ø³Ø¯Ø¯ ÙˆØ§Ù„Ù…Ø³Ø¯Ø¯ Ø¬Ø²Ø¦ÙŠØ§Ù‹
      final allRows = DatabaseService.instance.getAllDebtTransactions();
      final byCustomer = <String, List<DebtTransaction>>{};
      for (final row in allRows) {
        byCustomer.putIfAbsent(row.customerId, () => <DebtTransaction>[]).add(row);
      }
      double totalOwed = 0.0;
      int openDebts = 0;
      for (final rows in byCustomer.values) {
        final ledger = buildCustomerLedger(rows);
        if (ledger.balance > 0.001) totalOwed += ledger.balance;
        openDebts += ledger.unpaidCount + ledger.partiallyPaidCount;
      }

      if (!mounted) return;
      setState(() {
        _customers = list;
        _filtered = _applyFilter(list);
        _totalOwed = totalOwed;
        _openDebts = openDebts;
        _loading = false;
      });
      _counterController
        ..reset()
        ..forward();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _customers = [];
        _filtered = [];
        _totalOwed = 0.0;
        _openDebts = 0;
        _loading = false;
      });
    }
  }

  List<Customer> _applyFilter(List<Customer> list) {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list
        .where((c) =>
            c.name.toLowerCase().contains(q) || (c.phone ?? '').contains(q))
        .toList();
  }

  void _onSearch(String value) {
    setState(() => _filtered = _applyFilter(_customers));
  }

  Future<void> _openCustomerForm({Customer? customer}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomerFormSheet(
        customer: customer,
        onSaved: () {
          Navigator.pop(context);
          _showSnack(context.successColor, 'customers.savedLocally'.tr());
          _load();
        },
      ),
    );
  }

  Future<void> _confirmDelete(Customer customer) async {
    final isDark = context.isDark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusMd)),
        title: Text(
          'customers.deleteTitle'.tr(),
          style: AppTextStyles.headline4(color: dialogContext.titleColor),
        ),
        content: Text(
          'customers.deleteMessage'.tr(namedArgs: {'name': customer.name}),
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
      await _sync.deleteCustomer(customer.id);
    } catch (_) {
      if (mounted) {
        _showSnack(context.errorColor, 'common.error'.tr());
      }
      return;
    }
    _load();
  }

  void _openCustomerOptions(Customer customer) {
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
                customer.name,
                style: AppTextStyles.headline4(color: titleColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: Icon(Icons.edit_rounded, color: accentColor),
              title: Text(
                'customers.edit'.tr(),
                style: AppTextStyles.bodyMedium(color: bodyColor),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _openCustomerForm(customer: customer);
              },
            ),
            ListTile(
              leading: Icon(Icons.visibility_rounded, color: accentColor),
              title: Text(
                'customers.viewDetails'.tr(),
                style: AppTextStyles.bodyMedium(color: bodyColor),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CustomerDetailScreen(customer: customer),
                  ),
                ).then((_) => _load());
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_rounded, color: context.errorColor),
              title: Text(
                'customers.deleteTitle'.tr(),
                style: AppTextStyles.bodyMedium(color: bodyColor),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDelete(customer);
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
          'customers.title'.tr(),
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
        heroTag: 'customers_add_fab',
        onPressed: () => _openCustomerForm(),
        tooltip: 'customers.add'.tr(),
        backgroundColor: accentColor,
        foregroundColor: isDark ? AppColors.black : AppColors.white,
        child: const Icon(Icons.add_rounded),
      ),
      body: _loading
          ? const SkeletonLoadingView()
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
                      hintText: 'customers.search'.tr(),
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
                          icon: Icons.people_rounded,
                          title: 'customers.empty'.tr(),
                          subtitle: _customers.isEmpty
                              ? 'customers.emptyHint'.tr()
                              : null,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 90),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final customer = _filtered[i];
                            final ledger = DatabaseService.instance
                                .getCustomerLedger(customer.id);
                            final owes = ledger.balance > 0.001;
                            final balanceColor =
                                owes ? context.errorColor : context.successColor;
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
                                onTap: () => _openCustomerOptions(customer),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      accentColor.withValues(alpha: 0.12),
                                  child: Text(
                                    customer.name.isNotEmpty
                                        ? customer.name[0].toUpperCase()
                                        : '?',
                                    style: AppTextStyles.bodyMedium(
                                      color: accentColor,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  customer.name,
                                  style: AppTextStyles.bodyMedium(
                                      color: titleColor),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  customer.phone ?? '',
                                  style: AppTextStyles.bodySmall(
                                      color: bodyColor),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: balanceColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(
                                        DesignTokens.radiusPill),
                                  ),
                                  child: Text(
                                    '${ledger.balance.toStringAsFixed(0)} $_currency',
                                    style: AppTextStyles.bodySmall(
                                      color: balanceColor,
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

  // â­ Ø¨Ø·Ø§Ù‚Ø© Ø§Ù„Ù…Ù„Ø®Øµ: ØªØ¯Ø±Ø¬ Ø²Ù…Ø±Ø¯ÙŠ Ø¨Ø«Ù„Ø§Ø« Ø¯Ø±Ø¬Ø§Øª + Ø­Ù„Ù‚Ø© Ø²Ø®Ø±ÙÙŠØ©ØŒ Ø¨Ù†ÙØ³ Ù„ØºØ© Ø¨Ø·Ø§Ù‚Ø©
  // Ø§Ù„ØªØ±Ø­ÙŠØ¨ ÙÙŠ Ù„ÙˆØ­Ø© Ø§Ù„ØªØ­ÙƒÙ…. Ø§Ù„Ø¥ÙŠØ±Ø§Ø¯ Ø§Ù„ÙƒØ¨ÙŠØ± Ø¨Ø¹Ø¯Ù‘Ø§Ø¯ Ù…ØªØ­Ø±Ùƒ ÙˆÙ„ÙˆØ­ØªØ§Ù† Ø²Ø¬Ø§Ø¬ÙŠØªØ§Ù†.
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
                    'customers.summaryTotalOwed'.tr(),
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
                          _totalOwed * _counterAnimation.value;
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
                                Icons.receipt_long_rounded,
                                color: onCard.withValues(alpha: 0.85),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$_openDebts',
                                      style: AppTextStyles.headline4(
                                          color: onCard),
                                      maxLines: 1,
                                    ),
                                    Text(
                                      'customers.summaryOpenDebts'.tr(),
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
                                Icons.people_rounded,
                                color: onCard.withValues(alpha: 0.85),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_customers.length}',
                                      style: AppTextStyles.headline4(
                                          color: onCard),
                                      maxLines: 1,
                                    ),
                                    Text(
                                      'customers.summaryCustomers'.tr(),
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

class _CustomerFormSheet extends StatefulWidget {
  const _CustomerFormSheet({this.customer, required this.onSaved});

  final Customer? customer;
  final VoidCallback onSaved;

  @override
  State<_CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends State<_CustomerFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _notesController;
  bool _saving = false;

  bool get _isEditing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    _nameController = TextEditingController(text: customer?.name ?? '');
    _phoneController = TextEditingController(text: customer?.phone ?? '');
    _addressController = TextEditingController(text: customer?.address ?? '');
    _notesController = TextEditingController(text: customer?.notes ?? '');
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
        await SyncService().updateCustomer(
          id: widget.customer!.id,
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
        await SyncService().addCustomer(
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
                            ? 'customers.edit'.tr()
                            : 'customers.add'.tr(),
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
                    labelText: 'customers.name'.tr(),
                    prefixIcon:
                        const Icon(Icons.person_rounded, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'customers.nameRequired'.tr()
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'customers.phone'.tr(),
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
                    labelText: 'customers.address'.tr(),
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
                    labelText: 'customers.notes'.tr(),
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
                        _isEditing ? 'common.save'.tr() : 'customers.add'.tr()),
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