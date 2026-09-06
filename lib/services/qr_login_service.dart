// lib/services/qr_login_service.dart

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

// ⭐ crypto متاح كاعتماد غير مباشر عبر encrypt (نفس الإصدار في pubspec.lock)
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as encrypt;

import '../config/qr_login_config.dart';
import '../helpers/localization_helper.dart';

/// بيانات الاعتماد المستخرجة من رمز QR بعد فك التشفير.
class QrLoginCredentials {
  const QrLoginCredentials({
    required this.phone,
    required this.password,
  });

  final String phone;
  final String password;
}

/// تشفير بيانات الدخول (رقم الهاتف + كلمة المرور) داخل رمز QR وفك تشفيرها.
///
/// الصيغة (الإصدار 5):
/// `HANOTI_QR:5:<salt>:<base64(IV + AES-256-CBC(json))>`
/// حيث `salt` ملح عشوائي (32 حرفاً ست عشرية) يُولَّد مرة واحدة لكل حساب
/// ويُخزَّن في Hive، ومفتاح AES = SHA-256(السر الأساسي + الملح) — أي أن
/// المفتاح يختلف لكل حساب ولم يعد مفتاحاً واحداً ثابتاً في كل APK.
/// الملح يسافر خارج النص المشفر (في الرمز نفسه) لأن جهاز المسح يحتاجه
/// لاشتقاق المفتاح.
///
/// الإصدار 5 رمز دائم: لا يوجد تاريخ انتهاء في الحمولة، والإلغاء يتم
/// بإعادة توليد الملح من شاشة الإعدادات (رمز جديد = كل النسخ القديمة
/// المطبوعة أو المحفوظة تتوقف عن العمل فوراً).
///
/// الإصدار 4 (وكل ما سبقه) يستخدم صلاحية قصيرة/مفتاحاً عالمياً — يُرفض فوراً.
/// البادئة تُمكّن الماسح من التحقق بسرعة أن الرمز خاص بالتطبيق.
///
// TODO(C-1): حل مؤقت — الرمز ما زال يحمل كلمة المرور الحقيقية، ومن يفكّك
//   APK يستطيع استخراج السر الأساسي وقراءة الملح من الصورة، لذا التشفير
//   هنا إخفاء وليس حماية، والرمز الدائم يوسّع نافذة الضرر عند تسرّب
//   صورته. الحل الجذري: توكن لمرة واحدة/قابل للإلغاء يُصدره الخادم
//   (Cloud Functions) بدل كلمة المرور (انظر الشرح الكامل في
//   lib/config/qr_login_config.dart). إعادة توليد الملح هي صمام الأمان
//   حتى ذلك الحين.
class QrLoginService {
  QrLoginService._();

  static const String _scheme = 'HANOTI_QR';
  static const String _version = '5';
  static final RegExp _saltPattern = RegExp(r'^[0-9a-f]{32}$');

  /// يولّد ملحاً عشوائياً جديداً (32 حرفاً ست عشرية) — يُستدعى مرة واحدة
  /// لكل حساب عند أول توليد لرمز QR ويُخزَّن عبر DatabaseService.saveQrSalt.
  /// استدعاؤه مجدداً واستبدال الملح المخزَّن يُلغي كل الرموز القديمة.
  static String generateSalt() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// مفتاح AES-256 لكل حساب: SHA-256(السر الأساسي + الملح).
  static encrypt.Key _deriveKey(String salt) {
    final digest = crypto.sha256
        .convert(utf8.encode(QrLoginConfig.appEncryptionKey + salt));
    return encrypt.Key(Uint8List.fromList(digest.bytes));
  }

  /// يشفر رقم الهاتف وكلمة المرور ويعيد نص الرمز الجاهز للعرض في QR.
  /// الرمز دائم (بلا تاريخ انتهاء)، ويحمل IV عشوائياً مُضمَّناً في
  /// الحمولة نفسها ليتمكن الطرف الآخر من فكّه، وملح الحساب خارج النص
  /// المشفر لاشتقاق المفتاح.
  static String encryptCredentials({
    required String phone,
    required String password,
    required String salt,
  }) {
    if (!_saltPattern.hasMatch(salt)) {
      throw ArgumentError.value(
          salt, 'salt', LocalizationHelper.qrLoginInvalidSalt);
    }
    final json = jsonEncode({
      'phone': phone,
      'password': password,
      'issued_at': DateTime.now().toIso8601String(),
    });
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(_deriveKey(salt)));
    final encrypted = encrypter.encrypt(json, iv: iv);
    // نضمّن IV (16 بايت) أمام النص المشفّر في حمولة base64 واحدة.
    final payload = base64Encode([...iv.bytes, ...encrypted.bytes]);
    return '$_scheme:$_version:$salt:$payload';
  }

  /// يفك تشفير محتوى الرمز ويعيد بيانات الاعتماد، أو null إذا كان الرمز
  /// غير صالح أو لا يخص التطبيق أو من إصدار قديم (v4 وما قبله).
  /// لا يوجد فحص صلاحية — الإصدار 5 دائم، والإلغاء بإعادة توليد الملح.
  static QrLoginCredentials? decryptCredentials(String raw) {
    if (raw.isEmpty) return null;

    // الصيغة: HANOTI_QR:5:<salt>:<base64> — حمولة base64 لا تحتوي ':'
    // أبداً، لذا التقسيم آمن. أي إصدار آخر (مثل 4 و3) يُرفض.
    final parts = raw.split(':');
    if (parts.length != 4 || parts[0] != _scheme || parts[1] != _version) {
      return null;
    }
    final salt = parts[2];
    final payload = parts[3];
    if (!_saltPattern.hasMatch(salt)) return null;

    try {
      final combined = base64Decode(payload);
      if (combined.length <= 16) return null;
      final iv = encrypt.IV(combined.sublist(0, 16));
      final cipherBytes = combined.sublist(16);
      final encrypter = encrypt.Encrypter(encrypt.AES(_deriveKey(salt)));
      final decrypted =
          encrypter.decrypt(encrypt.Encrypted(cipherBytes), iv: iv);
      final data = jsonDecode(decrypted);
      if (data is! Map<String, dynamic>) return null;

      final phone = data['phone'] as String?;
      final password = data['password'] as String?;
      if (phone == null || phone.isEmpty) return null;
      if (password == null || password.isEmpty) return null;

      return QrLoginCredentials(phone: phone, password: password);
    } catch (_) {
      return null;
    }
  }
}
