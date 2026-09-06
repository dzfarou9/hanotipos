import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/helpers/login_rate_limiter.dart';

void main() {
  group('LoginRateLimiter', () {
    var now = DateTime(2026, 1, 1, 12, 0, 0);
    late LoginRateLimiter limiter;

    setUp(() {
      now = DateTime(2026, 1, 1, 12, 0, 0);
      limiter = LoginRateLimiter(
        maxAttempts: 5,
        lockDuration: const Duration(minutes: 5),
        clock: () => now,
      );
    });

    test('starts unlocked with all attempts remaining', () {
      expect(limiter.isLocked, isFalse);
      expect(limiter.attemptsRemaining, 5);
    });

    test('decrements attempts on each failure', () {
      limiter.recordFailure();
      limiter.recordFailure();
      expect(limiter.isLocked, isFalse);
      expect(limiter.attemptsRemaining, 3);
    });

    test('locks after reaching max attempts', () {
      for (var i = 0; i < 5; i++) {
        limiter.recordFailure();
      }
      expect(limiter.isLocked, isTrue);
      expect(limiter.attemptsRemaining, 0);
    });

    test('recordFailure is ignored while locked', () {
      for (var i = 0; i < 5; i++) {
        limiter.recordFailure();
      }
      limiter.recordFailure();
      limiter.recordFailure();
      expect(limiter.isLocked, isTrue);
    });

    test('unlocks after lock duration passes', () {
      for (var i = 0; i < 5; i++) {
        limiter.recordFailure();
      }
      expect(limiter.isLocked, isTrue);

      now = now.add(const Duration(minutes: 5));
      expect(limiter.isLocked, isFalse);
      expect(limiter.attemptsRemaining, 5);
    });

    test('still locked just before lock duration elapses', () {
      for (var i = 0; i < 5; i++) {
        limiter.recordFailure();
      }
      now = now.add(const Duration(minutes: 4, seconds: 59));
      expect(limiter.isLocked, isTrue);
    });

    test('remainingLock returns null when not locked', () {
      expect(limiter.remainingLock, isNull);
    });

    test('remainingLock shrinks as time passes', () {
      for (var i = 0; i < 5; i++) {
        limiter.recordFailure();
      }
      expect(limiter.remainingLock, const Duration(minutes: 5));

      now = now.add(const Duration(minutes: 2));
      expect(limiter.remainingLock, const Duration(minutes: 3));
    });
  });
}