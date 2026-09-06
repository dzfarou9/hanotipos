// lib/helpers/login_rate_limiter.dart

/// Tracks failed login attempts and enforces a temporary lockout.
///
/// Pure Dart with an injectable clock so it can be unit tested without
/// depending on [DateTime.now].
class LoginRateLimiter {
  LoginRateLimiter({
    this.maxAttempts = 5,
    this.lockDuration = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxAttempts;
  final Duration lockDuration;
  final DateTime Function() _clock;

  int _attempts = 0;
  DateTime? _lockedUntil;

  bool get isLocked {
    final until = _lockedUntil;
    if (until == null) return false;
    return _clock().isBefore(until);
  }

  /// Attempts remaining before the next lockout, or 0 while locked.
  int get attemptsRemaining {
    if (isLocked) return 0;
    return maxAttempts - _attempts;
  }

  /// Remaining lockout time, or null when not locked.
  Duration? get remainingLock {
    if (!isLocked) return null;
    return _lockedUntil!.difference(_clock());
  }

  /// Records a failed attempt and locks the limiter once [maxAttempts] is
  /// reached. No-op while already locked.
  void recordFailure() {
    if (isLocked) return;
    _attempts++;
    if (_attempts >= maxAttempts) {
      _attempts = 0;
      _lockedUntil = _clock().add(lockDuration);
    }
  }
}