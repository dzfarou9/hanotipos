// lib/widgets/customers/customer_picker_sheet.dart

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:pos_app/models/customer_model.dart';
import 'package:pos_app/services/database_service.dart';
import 'package:pos_app/services/sync_service.dart';
import 'package:pos_app/theme/app_colors.dart';
import 'package:pos_app/theme/app_text_styles.dart';
import 'package:pos_app/theme/screen_palette.dart';
import 'package:pos_app/theme/design_tokens.dart';
import 'package:pos_app/widgets/app_snackbar.dart';

Future<Customer?> showCustomerPickerSheet(BuildContext context) async {
  final result = await showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CustomerPickerSheet(),
  );
  return result;
}

class _CustomerPickerSheet extends StatefulWidget {
  const _CustomerPickerSheet();

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Customer> _customers = [];
  List<Customer> _filtered = [];

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

  void _load() {
    final list = DatabaseService.instance.getAllCustomers();
    setState(() {
      _customers = list;
      _filtered = _applyFilter(list);
    });
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

  Future<void> _addNewCustomer() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final created = await showModalBottomSheet<Customer>(
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
                        child: Icon(
                          Icons.person_add_rounded,
                          color: accentColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'customers.add'.tr(),
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
                    controller: nameController,
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
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'customers.phone'.tr(),
                      prefixIcon: const Icon(Icons.phone_rounded, size: 20),
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
                        try {
                          final customer = await SyncService().addCustomer(
                            name: nameController.text.trim(),
                            phone: phoneController.text.trim().isNotEmpty
                                ? phoneController.text.trim()
                                : null,
                          );
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext, customer);
                          }
                        } catch (_) {
                          if (sheetContext.mounted) {
                            AppSnackBar.error(
                                sheetContext, 'common.error'.tr());
                          }
                        }
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text('customers.add'.tr()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor:
                            isDark ? AppColors.black : AppColors.white,
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
        );
      },
    );

    nameController.dispose();
    phoneController.dispose();

    if (created != null) {
      _load();
      Navigator.pop(context, created);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final accentColor = context.accent;
    final titleColor = context.titleColor;
    final bodyColor = context.bodyColor;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'customers.selectCustomer'.tr(),
                style: AppTextStyles.headline4(color: titleColor),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
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
            Flexible(
              child: _filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_outline_rounded,
                              size: 48, color: bodyColor.withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          Text(
                            'customers.empty'.tr(),
                            style: AppTextStyles.bodyMedium(color: bodyColor),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      shrinkWrap: true,
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final customer = _filtered[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(DesignTokens.radiusMd),
                          ),
                          child: ListTile(
                            onTap: () => Navigator.pop(context, customer),
                            leading: CircleAvatar(
                              backgroundColor:
                                  accentColor.withValues(alpha: 0.1),
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
                            subtitle: customer.phone != null &&
                                    customer.phone!.isNotEmpty
                                ? Text(
                                    customer.phone!,
                                    style: AppTextStyles.bodySmall(
                                        color: bodyColor),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _addNewCustomer,
                  icon: const Icon(Icons.person_add_rounded, size: 18),
                  label: Text('customers.addNew'.tr()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accentColor,
                    side: BorderSide(color: accentColor),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radiusSm),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}