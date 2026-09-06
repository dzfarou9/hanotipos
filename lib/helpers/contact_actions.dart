// lib/helpers/contact_actions.dart

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// بيانات التواصل الرسمية للتطبيق.
class ContactInfo {
  static const String email = 'hanotisupport@gmail.com';
  static const String whatsapp = '0799146862';
  static const String website = 'https://hanoti.rf.gd';

  /// رقم الواتساب بصيغة دولية للتوجيه إلى wa.me
  static const String whatsappInternational = '213799146862';
}

/// إجراءات فتح قنوات التواصل.
class ContactActions {
  /// فتح تطبيق البريد لمراسلة الدعم.
  static Future<void> sendEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: ContactInfo.email,
    );
    await _launch(uri);
  }

  /// فتح محادثة الواتساب مع الدعم.
  static Future<void> openWhatsApp() async {
    final uri = Uri(
      scheme: 'https',
      host: 'wa.me',
      path: ContactInfo.whatsappInternational,
    );
    await _launch(uri);
  }

  /// فتح الموقع الإلكتروني.
  static Future<void> openWebsite() async {
    final uri = Uri.parse(ContactInfo.website);
    await _launch(uri);
  }

  static Future<void> _launch(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } else {
      debugPrint('Cannot launch URL: $uri');
    }
  }
}