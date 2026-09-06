// lib/services/sales_cache.dart

import 'package:hive/hive.dart';
import '../models/sale_model.dart';

/// ⭐ كاش للقائمة المرتبة للمبيعات لتجنب إعادة القراءة والفرز من Hive
/// في كل مرة. يُبطل الكاش عند أي كتابة في قاعدة البيانات.
class SalesCache {
  SalesCache(this._box);

  final Box<Sale> _box;
  List<Sale>? _cached;

  /// القائمة كاملة مرتبة من الأحدث إلى الأقدم (تقرأ مرة واحدة ثم تُخزن).
  List<Sale> getAllSorted() {
    final cached = _cached;
    if (cached != null) return cached;

    final all = _box.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _cached = all;
    return all;
  }

  void invalidate() {
    _cached = null;
  }
}