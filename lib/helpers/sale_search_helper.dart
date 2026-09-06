// lib/helpers/sale_search_helper.dart

import '../models/sale_model.dart';

/// ⭐ بناء نص بحث صغير الحروف (رقم الفاتورة + اسم العميل + أسماء المنتجات)
/// مرة واحدة لكل مبيعة لتسريع البحث (بدل تكرار تحويل الأحرف لكل ضغطة).
String buildSaleSearchText(Sale sale) {
  final buffer = StringBuffer(sale.id.toLowerCase());

  final customerName = sale.customerName;
  if (customerName != null && customerName.isNotEmpty) {
    buffer.write(' ');
    buffer.write(customerName.toLowerCase());
  }

  for (final item in sale.items) {
    buffer.write(' ');
    buffer.write(item.productName.toLowerCase());
  }

  return buffer.toString();
}