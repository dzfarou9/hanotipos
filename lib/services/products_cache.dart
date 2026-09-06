// lib/services/products_cache.dart

import 'package:hive/hive.dart';
import '../models/product_model.dart';

/// ⭐ كاش للقائمة المرتبة للمنتجات لتجنب إعادة القراءة والفرز من Hive
/// في كل مرة. يُبطل الكاش عند أي كتابة في قاعدة البيانات.
class ProductsCache {
  ProductsCache(this._box);

  final Box<Product> _box;
  List<Product>? _cached;

  /// القائمة كاملة مرتبة من الأحدث إلى الأقدم (تقرأ مرة واحدة ثم تُخزن).
  List<Product> getAllSorted() {
    final cached = _cached;
    if (cached != null) return cached;

    final all = _box.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _cached = all;
    return all;
  }

  void invalidate() {
    _cached = null;
  }
}