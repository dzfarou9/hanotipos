// lib/widgets/pos/receipt_formatting.dart
// أدوات تنسيق إيصالات البيع مشتركة بين شاشة البيع والحوارات.

import 'package:flutter/material.dart';
import '../../theme/app_text_styles.dart';

String formatPosDateTime(DateTime dt) =>
    '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

Widget buildPosReceiptRow(String label, String value, Color color,
    {bool isBold = false}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: (isBold
                ? AppTextStyles.bodyLarge(color: color)
                : AppTextStyles.bodySmall(color: color))
            .copyWith(fontSize: isBold ? 15 : 12),
      ),
      Flexible(
        child: Text(
          value,
          style: (isBold
                  ? AppTextStyles.bodyLarge(color: color)
                  : AppTextStyles.bodySmall(color: color))
              .copyWith(fontSize: isBold ? 15 : 12),
          textAlign: TextAlign.right,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}
