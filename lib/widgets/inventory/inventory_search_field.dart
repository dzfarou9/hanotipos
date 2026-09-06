// lib/widgets/inventory/inventory_search_field.dart

import 'dart:async';

import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../helpers/localization_helper.dart';

/// حقل بحث معزول يملك حالة النص وزر المسح بنفسه.
///
/// الكتابة لا تعيد بناء الشاشة كاملة — يخطر الوالد فقط عبر [onQueryChanged]
/// (لكل ضغطة، لتحديث النص بدون إعادة بناء) و [onQueryDebounced]
/// (بعد توقف الكتابة 250ms، لتنفيذ إعادة الفلترة).
class InventorySearchField extends StatefulWidget {
  const InventorySearchField({
    super.key,
    required this.focusNode,
    required this.onQueryChanged,
    required this.onQueryDebounced,
    this.debounceDuration = AppConfig.inventorySearchDebounce,
  });

  final FocusNode focusNode;

  /// يُستدعى فور كل تغيير نصي (لتحديث حالة البحث بدون إعادة بناء الشاشة).
  final ValueChanged<String> onQueryChanged;

  /// يُستدعى بعد توقف الكتابة [debounceDuration] (لإعادة الفلترة فعلياً).
  final ValueChanged<String> onQueryDebounced;

  final Duration debounceDuration;

  @override
  State<InventorySearchField> createState() => _InventorySearchFieldState();
}

class _InventorySearchFieldState extends State<InventorySearchField> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // ⭐ إعادة بناء فرعية فقط لإظهار/إخفاء زر المسح
    setState(() {});
    widget.onQueryChanged(value);
    _debounce?.cancel();
    _debounce = Timer(widget.debounceDuration, () {
      if (mounted) widget.onQueryDebounced(value);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {});
    widget.onQueryChanged('');
    widget.onQueryDebounced('');
    widget.focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      focusNode: widget.focusNode,
      controller: _controller,
      onChanged: _onChanged,
      decoration: InputDecoration(
        hintText: LocalizationHelper.inventorySearchHint,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: _clear,
              )
            : null,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}