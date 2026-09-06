// lib/config/app_config.dart

/// Centralized app configuration.
/// Avoids hardcoded values and provides production-safe logging.
class AppConfig {
  AppConfig._();

  // ==================== Currency ====================
  static const String currencyCode = 'DZD';
  static const String currencySymbol = 'د.ج';

  // ==================== Network ====================
  static const Duration defaultTimeout = Duration(seconds: 15);
  static const int maxRetries = 3;
  static const Duration baseRetryDelay = Duration(milliseconds: 500);

  // ==================== Sync ====================
  static const Duration pullCooldown = Duration(minutes: 5);
  static const Duration initialSyncTimeout = Duration(seconds: 10);

  // ==================== Barcode Scanner ====================
  static const Duration scanCooldown = Duration(milliseconds: 500);
  static const Duration minFrameInterval = Duration(milliseconds: 150);
  static const int emptyFramesToReArm = 3;

  // ==================== Search Debounce ====================
  static const Duration posSearchDebounce = Duration(milliseconds: 150);
  static const Duration inventorySearchDebounce = Duration(milliseconds: 150);
  static const Duration salesHistorySearchDebounce = Duration(milliseconds: 200);

  // ==================== Logging ====================
  /// True when running in release/profile mode (dart.vm.product = true).
  /// In debug mode, logs are printed. In production, they are silenced.
  static const bool isProduction = bool.fromEnvironment('dart.vm.product');

  /// Production-safe logging. No-op in release builds.
  static void log(String message) {
    if (!isProduction) {
      // ignore: avoid_print
      print(message);
    }
  }

  /// Production-safe error logging. Always prints in debug, includes stack trace option.
  static void logError(String message, [Object? error, StackTrace? stackTrace]) {
    if (!isProduction) {
      // ignore: avoid_print
      print('❌ $message');
      if (error != null) {
        // ignore: avoid_print
        print('   Error: $error');
      }
      if (stackTrace != null) {
        // ignore: avoid_print
        print('   Stack: $stackTrace');
      }
    }
  }
}