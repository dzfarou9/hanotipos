// lib/screens/customer_detail_screen.dart

import 'package:flutter/material.dart';
import '../widgets/skeleton.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:pos_app/models/customer_model.dart';
import 'package:pos_app/models/debt_transaction_model.dart';
import 'package:pos_app/services/database_service.dart';
import 'package:pos_app/services/sync_service.dart';
import 'package:pos_app/helpers/debt_ledger_helper.dart';
import 'package:pos_app/theme/app_colors.dart';
import 'package:pos_app/theme/app_text_styles.dart';
import 'package:pos_app/theme/screen_palette.dart';
import 'package:pos_app/theme/design_tokens.dart';
import 'package:pos_app/widgets/app_snackbar.dart';
import 'package:pos_app/widgets/empty_state.dart';

class CustomerDetailScreen extends StatefulWidget {
  final Customer customer;
  const CustomerDetailScreen({super.key, required this.customer});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen>
    with SingleTickerProviderStateMixin {
  static const String _currency = 'DZD';

  late TabController _tabController;
  late Customer _customer;
  CustomerLedger? _ledger;
  List<DebtTransaction> _transactions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _customer = widget.customer;
    _load();
    SyncService().dataChangeNotifier.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    SyncService().dataChangeNotifier.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    _load();
  }

  void _load() {
    final updated = DatabaseService.instance.getCustomerById(_customer.id);
    if (updated != null) {
      _customer = updated;
    }
    final ledger = DatabaseService.instance.getCustomerLedger(_customer.id);
    final txns = DatabaseService.instance.getDebtTransactionsByCustomer(_customer.id);
    if (!mounted) return;
    setState(() {
      _ledger = ledger;
      _transactions = txns;
      _loading = false;
    });
  }

  Future<void> _confirmDelete() async {
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
          'customers.deleteMessage'.tr(namedArgs: {'name': _customer.name}),
          style: AppTextStyles.bodyMedium(color: dialogContext.bodyColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'common.cancel'.tr(),
              style: AppTextStyles.bodyMedium(color: dialogContext.bodyColor),
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
      await SyncService().deleteCustomer(_customer.id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        AppSnackBar.error(context, 'common.error'.tr());
      }
    }
  }

  Future<void> _recordPayment() async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = sheetContext.isDark;
        final accentColor = sheetContext.accent;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Form(
              key: formKey,
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
                        child: const Icon(
                          Icons.payment_rounded,
                          color: AppColors.success,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'customers.recordPayment'.tr(),
                          style: AppTextStyles.headline4(
                              color: sheetContext.titleColor),
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
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'customers.paymentAmount'.tr(),
                      prefixIcon:
                          const Icon(Icons.monetization_on_rounded, size: 20),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'customers.amountRequired'.tr();
                      }
                      final amount = double.tryParse(v.trim());
                      if (amount == null || amount <= 0) {
                        return 'customers.invalidAmount'.tr();
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'customers.paymentNote'.tr(),
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
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final amount = double.parse(
                            amountController.text.trim());
                        try {
                          await SyncService().addPayment(
                            customerId: _customer.id,
                            amount: amount,
                            note: noteController.text.trim().isNotEmpty
                                ? noteController.text.trim()
                                : null,
                          );
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext, true);
                          }
                        } catch (_) {
                          if (sheetContext.mounted) {
                            AppSnackBar.error(sheetContext, 'common.error'.tr());
                          }
                        }
                      },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text('common.confirm'.tr()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: AppColors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(DesignTokens.radiusSm),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    amountController.dispose();
    noteController.dispose();

    if (result == true) {
      _load();
      if (mounted) {
        AppSnackBar.success(context, 'customers.paymentRecorded'.tr());
      }
    }
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
          _customer.name,
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
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: titleColor),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  _showEditForm();
                  break;
                case 'delete':
                  _confirmDelete();
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_rounded, size: 18, color: accentColor),
                    const SizedBox(width: 8),
                    Text('common.edit'.tr()),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_rounded, size: 18, color: context.errorColor),
                    const SizedBox(width: 8),
                    Text('common.delete'.tr()),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const SkeletonLoadingView()
          : Column(
              children: [
                _buildSummary(),
                TabBar(
                  controller: _tabController,
                  indicatorColor: accentColor,
                  labelColor: accentColor,
                  unselectedLabelColor: bodyColor,
                  tabs: [
                    Tab(text: 'customers.debts'.tr()),
                    Tab(text: 'customers.history'.tr()),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildDebtsTab(),
                      _buildHistoryTab(),
                    ],
                  ),
                ),
                if (_ledger != null && _ledger!.balance > 0)
                  _buildPaymentButton(),
              ],
            ),
    );
  }

  Widget _buildSummary() {
    final ledger = _ledger;
    if (ledger == null) return const SizedBox.shrink();
    final isDark = context.isDark;
    final accentColor = context.accent;
    final owes = ledger.balance > 0.001;
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
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'customers.balance'.tr(),
                          style: AppTextStyles.caption(
                            color: onCardSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (_customer.phone != null &&
                          _customer.phone!.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.phone_rounded,
                                size: 13, color: onCardTertiary),
                            const SizedBox(width: 5),
                            Text(
                              _customer.phone!,
                              style: AppTextStyles.caption(
                                color: onCardTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      '${ledger.balance.toStringAsFixed(0)} $_currency',
                      style: AppTextStyles.headline1(
                        color: owes ? onCard : AppColors.successOnDark,
                      ),
                      maxLines: 1,
                    ),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'customers.totalDebt'.tr(),
                                style: AppTextStyles.caption(
                                  color: onCardTertiary,
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${ledger.totalDebt.toStringAsFixed(0)} $_currency',
                                  style: AppTextStyles.bodyMedium(
                                      color: onCard),
                                  maxLines: 1,
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'customers.totalPaid'.tr(),
                                style: AppTextStyles.caption(
                                  color: onCardTertiary,
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${ledger.totalPaid.toStringAsFixed(0)} $_currency',
                                  style: AppTextStyles.bodyMedium(
                                      color: onCard),
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // â­ Ø´Ø±ÙŠØ­Ø© Ø§Ù„Ø­Ø§Ù„Ø©: Ù„ÙˆÙ† ØªÙˆØ¶ÙŠØ­ÙŠ Ø£Ø¹Ù„Ù‰ Ø§Ù„Ø±ØµÙŠØ¯
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: owes
                          ? AppColors.error.withValues(alpha: 0.22)
                          : AppColors.success.withValues(alpha: 0.22),
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radiusPill),
                    ),
                    child: Text(
                      owes
                          ? 'customers.unpaid'.tr()
                          : 'customers.paid'.tr(),
                      style: AppTextStyles.caption(
                        color: isDark
                            ? (owes
                                ? AppColors.errorOnDark
                                : AppColors.successOnDark)
                            : AppColors.white,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebtsTab() {
    final ledger = _ledger;
    if (ledger == null || ledger.debts.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_rounded,
        title: 'customers.noDebts'.tr(),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: ledger.debts.length,
      itemBuilder: (_, i) {
        final entry = ledger.debts[i];
        final stateColor = switch (entry.state) {
          DebtState.paid => context.successColor,
          DebtState.partiallyPaid => context.warningColor,
          DebtState.unpaid => context.errorColor,
        };
        final stateLabel = switch (entry.state) {
          DebtState.paid => 'customers.paid'.tr(),
          DebtState.partiallyPaid => 'customers.partiallyPaid'.tr(),
          DebtState.unpaid => 'customers.unpaid'.tr(),
        };

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${'customers.debt'.tr()} #${i + 1}',
                        style: AppTextStyles.bodyMedium(color: context.titleColor),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: stateColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        stateLabel,
                        style: AppTextStyles.bodySmall(color: stateColor),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildDebtRow(
                        label: 'customers.amount'.tr(),
                        value: entry.debt.amount.toStringAsFixed(2),
                      ),
                    ),
                    Expanded(
                      child: _buildDebtRow(
                        label: 'customers.paid'.tr(),
                        value: entry.paidAmount.toStringAsFixed(2),
                        color: context.successColor,
                      ),
                    ),
                    Expanded(
                      child: _buildDebtRow(
                        label: 'customers.remaining'.tr(),
                        value: entry.remainingAmount.toStringAsFixed(2),
                        color: stateColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // â­ Ø´Ø±ÙŠØ· Ø³Ø¯Ø§Ø¯: Ù†Ø³Ø¨Ø© Ø§Ù„Ù…Ø¯ÙÙˆØ¹ Ù…Ù† Ø§Ù„Ø¯ÙŠÙ†
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: entry.debt.amount > 0
                        ? (entry.paidAmount / entry.debt.amount)
                            .clamp(0.0, 1.0)
                        : 0.0,
                    minHeight: 5,
                    backgroundColor: stateColor.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(stateColor),
                  ),
                ),
                if (entry.debt.note != null && entry.debt.note!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      entry.debt.note!,
                      style: AppTextStyles.bodySmall(color: context.bodyColor),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDebtRow({
    required String label,
    required String value,
    Color? color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.bodySmall(color: context.bodyColor),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTextStyles.bodyMedium(color: color ?? context.titleColor),
        ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    if (_transactions.isEmpty) {
      return EmptyState(
        icon: Icons.history_rounded,
        title: 'customers.noTransactions'.tr(),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: _transactions.length,
      itemBuilder: (_, i) {
        final tx = _transactions[i];
        final isDebt = tx.type == DebtTransactionType.debt;
        final isPayment = tx.type == DebtTransactionType.payment;
        final sign = isDebt ? '+' : (isPayment ? '-' : 'Â±');
        final color = isDebt ? context.errorColor : context.successColor;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(
                isDebt ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                color: color,
                size: 18,
              ),
            ),
            title: Text(
              '$sign ${tx.amount.abs().toStringAsFixed(2)}',
              style: AppTextStyles.bodyMedium(color: color),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tx.note != null && tx.note!.isNotEmpty)
                  Text(
                    tx.note!,
                    style: AppTextStyles.bodySmall(color: context.bodyColor),
                  ),
                Text(
                  DateFormat('yyyy-MM-dd HH:mm').format(tx.createdAt),
                  style: AppTextStyles.bodySmall(color: context.captionColor),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaymentButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _recordPayment,
            icon: const Icon(Icons.payment_rounded),
            label: Text('customers.recordPayment'.tr()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: AppColors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditForm() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomerEditSheet(
        customer: _customer,
        onSaved: () {
          Navigator.pop(context);
          _load();
          AppSnackBar.success(context, 'customers.savedLocally'.tr());
        },
      ),
    );
  }
}

class _CustomerEditSheet extends StatefulWidget {
  final Customer customer;
  final VoidCallback onSaved;

  const _CustomerEditSheet({required this.customer, required this.onSaved});

  @override
  State<_CustomerEditSheet> createState() => _CustomerEditSheetState();
}

class _CustomerEditSheetState extends State<_CustomerEditSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _notesController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer.name);
    _phoneController = TextEditingController(text: widget.customer.phone ?? '');
    _addressController = TextEditingController(text: widget.customer.address ?? '');
    _notesController = TextEditingController(text: widget.customer.notes ?? '');
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
      await SyncService().updateCustomer(
        id: widget.customer.id,
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
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
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
                        Icons.edit_rounded,
                        color: accentColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'common.edit'.tr(),
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
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text('common.save'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor:
                          isDark ? AppColors.black : AppColors.white,
                      disabledBackgroundColor:
                          accentColor.withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radiusSm),
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