// lib/helpers/platform_helper.dart

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class PlatformHelper {
  static bool? _override;

  static bool get isWindows => _override ?? (!kIsWeb && Platform.isWindows);

  /// `true`/`false` للتحكم القسري في الاختبارات، `null` للإلغاء.
  static void overrideForTest(bool? value) {
    _override = value;
  }

  static void resetOverride() {
    _override = null;
  }
}
