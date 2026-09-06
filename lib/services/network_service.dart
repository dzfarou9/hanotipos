// lib/services/network_service.dart

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/app_config.dart';
import '../helpers/localization_helper.dart';

/// Network service with timeout and exponential backoff retry.
/// Wraps Firebase and other network calls for consistent error handling.
class NetworkService {
  NetworkService._();

  /// Executes an operation with timeout and retry logic.
  ///
  /// [operation] - The async operation to execute
  /// [timeout] - Maximum time to wait for each attempt (default: 15s)
  /// [maxRetries] - Number of retry attempts (default: 3)
  /// [baseDelay] - Initial delay before first retry (default: 500ms)
  /// [retryCondition] - Optional predicate to determine if an error is retryable
  ///
  /// Returns the result of the successful operation.
  /// Throws the last error if all retries exhausted.
  static Future<T> callWithRetry<T>({
    required Future<T> Function() operation,
    Duration? timeout,
    int? maxRetries,
    Duration? baseDelay,
    bool Function(Object error)? retryCondition,
  }) async {
    final effectiveTimeout = timeout ?? AppConfig.defaultTimeout;
    final effectiveMaxRetries = maxRetries ?? AppConfig.maxRetries;
    final effectiveBaseDelay = baseDelay ?? AppConfig.baseRetryDelay;

    Object? lastError;
    StackTrace? lastStackTrace;

    for (int attempt = 0; attempt <= effectiveMaxRetries; attempt++) {
      try {
        final result = await operation().timeout(
          effectiveTimeout,
          onTimeout: () {
            throw TimeoutException(
                LocalizationHelper.commonTimedOut(effectiveTimeout.inSeconds));
          },
        );
        if (attempt > 0) {
          AppConfig.log('✅ Network call succeeded on retry $attempt');
        }
        return result;
      } on TimeoutException catch (e, st) {
        lastError = e;
        lastStackTrace = st;
        AppConfig.logError('⏱️ Timeout on attempt ${attempt + 1}/${effectiveMaxRetries + 1}', e, st);
      } catch (e, st) {
        lastError = e;
        lastStackTrace = st;
        AppConfig.logError('🌐 Network error on attempt ${attempt + 1}/${effectiveMaxRetries + 1}', e, st);

        // Check if error is retryable
        final isRetryable = retryCondition?.call(e) ?? _isRetryableError(e);
        if (!isRetryable || attempt == effectiveMaxRetries) {
          AppConfig.logError('🚫 Non-retryable error or max retries reached', e, st);
          rethrow;
        }
      }

      // Wait before retry with exponential backoff
      if (attempt < effectiveMaxRetries) {
        final delay = effectiveBaseDelay * (1 << attempt); // 500ms, 1s, 2s
        AppConfig.log('⏳ Retrying in ${delay.inMilliseconds}ms...');
        await Future.delayed(delay);
      }
    }

    // Should not reach here, but satisfy analyzer — نرمي الخطأ مع
    // stack trace الأصلي بدلاً من فقدانه.
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  /// Determines if an error is likely transient and worth retrying.
  static bool _isRetryableError(Object error) {
    // ⭐ M-5: أخطاء المصادقة لا تُعاد أبداً — إعادة المحاولة تُبطئ
    // الاستجابة وقد تُفعّل حماية too-many-requests بلا فائدة.
    if (error is FirebaseAuthException) return false;

    final errorString = error.toString().toLowerCase();

    // ⭐ M-5: أكواد مصادقة معروفة داخل نص أي استثناء غير مصنّف
    const authCodes = [
      'wrong-password',
      'user-not-found',
      'invalid-credential',
      'invalid-login-credentials',
      'email-already-in-use',
      'weak-password',
      'too-many-requests',
      'invalid-email',
      'user-disabled',
    ];
    for (final code in authCodes) {
      if (errorString.contains(code)) return false;
    }

    // Network/connection errors
    if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('socket') ||
        errorString.contains('timeout') ||
        errorString.contains('timed out')) {
      return true;
    }

    // Firebase-specific retryable errors
    if (errorString.contains('unavailable') ||
        errorString.contains('deadline-exceeded') ||
        errorString.contains('resource-exhausted') ||
        errorString.contains('internal') ||
        errorString.contains('aborted')) {
      return true;
    }

    // HTTP 5xx errors
    if (errorString.contains('500') ||
        errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('504')) {
      return true;
    }

    // Non-retryable: auth errors, permission denied, not found, invalid argument
    if (errorString.contains('permission-denied') ||
        errorString.contains('unauthenticated') ||
        errorString.contains('not-found') ||
        errorString.contains('invalid-argument') ||
        errorString.contains('already-exists') ||
        errorString.contains('failed-precondition')) {
      return false;
    }

    // Default: retry on unknown errors
    return true;
  }

  /// Convenience method for Firestore read operations.
  static Future<T> readWithRetry<T>(Future<T> Function() operation) {
    return callWithRetry(operation: operation);
  }

  /// Convenience method for Firestore write operations.
  static Future<T> writeWithRetry<T>(Future<T> Function() operation) {
    return callWithRetry(operation: operation, maxRetries: 2); // Fewer retries for writes
  }
}

/// Custom exception for network-related errors that should be shown to user.
class NetworkException implements Exception {
  final String message;
  final Object? originalError;
  final bool isRetryable;

  const NetworkException(this.message, {this.originalError, this.isRetryable = true});

  @override
  String toString() => 'NetworkException: $message';
}