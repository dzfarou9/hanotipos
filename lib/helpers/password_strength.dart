// lib/helpers/password_strength.dart

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

int calculatePasswordStrength(String password) {
  if (password.isEmpty) return 0;

  // ⭐ كلمة مرور مكوّنة من حرف واحد متكرر تعتبر ضعيفة جداً
  if (RegExp(r'^(.)\1+$').hasMatch(password)) {
    return password.length >= 8 ? 1 : 0;
  }

  int score = 0;
  if (password.length >= 8) score++;
  if (password.contains(RegExp(r'[A-Z]'))) score++;
  if (password.contains(RegExp(r'[a-z]'))) score++;
  if (password.contains(RegExp(r'[0-9]'))) score++;
  if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) score++;

  // ⭐ طول أقل من 8 أحرف لا يسمح بأكثر من نقطتين
  if (password.length < 8 && score > 2) score = 2;

  // ⭐ لا يصل إلى 3+ نقاط إلا مع وجود أكثر من فئة حرف واحدة
  final characterClasses =
      (password.contains(RegExp(r'[A-Z]')) ? 1 : 0) +
          (password.contains(RegExp(r'[a-z]')) ? 1 : 0) +
          (password.contains(RegExp(r'[0-9]')) ? 1 : 0) +
          (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]')) ? 1 : 0);
  if (characterClasses <= 1 && score > 2) score = 2;

  return score.clamp(0, 5);
}

Color getPasswordStrengthColor(int strength) {
  switch (strength) {
    case 0:
      return Colors.grey;
    case 1:
      return Colors.red;
    case 2:
      return Colors.orange;
    case 3:
      return Colors.yellow.shade700;
    case 4:
      return Colors.green;
    case 5:
      return Colors.greenAccent.shade700;
    default:
      return Colors.grey;
  }
}

String getPasswordStrengthLabel(int strength) {
  switch (strength) {
    case 0:
      return 'common.very_weak'.tr();
    case 1:
      return 'common.weak'.tr();
    case 2:
      return 'common.medium'.tr();
    case 3:
      return 'common.good'.tr();
    case 4:
      return 'common.strong'.tr();
    case 5:
      return 'common.very_strong'.tr();
    default:
      return '';
  }
}

Widget buildPasswordStrengthIndicator(String password, int strength) {
  if (password.isEmpty) return const SizedBox.shrink();

  final color = getPasswordStrengthColor(strength);
  final label = getPasswordStrengthLabel(strength);

  return Column(
    children: [
      const SizedBox(height: 8),
      Row(
        children: List.generate(5, (index) {
          return Expanded(
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: index < strength ? color : Colors.grey.withValues(alpha:0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerRight,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      const SizedBox(height: 8),
    ],
  );
}