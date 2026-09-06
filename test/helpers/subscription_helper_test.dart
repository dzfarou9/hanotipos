import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/helpers/subscription_helper.dart';

void main() {
  final now = DateTime(2025, 6, 18, 12);

  group('daysRemaining', () {
    test('an expired subscription is zero, never negative', () {
      expect(daysRemaining(DateTime(2025, 6, 17, 12), now), 0);
      expect(daysRemaining(DateTime(2024, 1, 1), now), 0);
    });

    test('the exact end instant counts as expired', () {
      expect(daysRemaining(now, now), 0);
    });

    test('a partial day counts as a whole day (the truncation bug)', () {
      // 23 hours left: Duration.inDays would say 0 while still active.
      expect(daysRemaining(now.add(const Duration(hours: 23)), now), 1);
      // One minute left is still a day of access.
      expect(daysRemaining(now.add(const Duration(minutes: 1)), now), 1);
    });

    test('whole days are not inflated', () {
      expect(daysRemaining(now.add(const Duration(days: 7)), now), 7);
      expect(daysRemaining(now.add(const Duration(days: 30)), now), 30);
    });

    test('days plus a remainder round up', () {
      expect(
        daysRemaining(now.add(const Duration(days: 7, hours: 5)), now),
        8,
      );
    });
  });

  group('isSubscriptionValid', () {
    test('a null end date is not valid', () {
      expect(isSubscriptionValid(null, now), isFalse);
    });

    test('a future end date is valid', () {
      expect(isSubscriptionValid(now.add(const Duration(days: 1)), now), isTrue);
    });

    test('a past end date is not valid', () {
      expect(
        isSubscriptionValid(now.subtract(const Duration(seconds: 1)), now),
        isFalse,
      );
    });
  });

  group('isLeaseValid', () {
    const lease = Duration(hours: 48);

    bool check({
      bool isActive = true,
      DateTime? endDate,
      DateTime? lastVerified,
    }) =>
        isLeaseValid(
          isActive: isActive,
          endDate: endDate ?? now.add(const Duration(days: 10)),
          lastVerified: lastVerified ?? now.subtract(const Duration(hours: 1)),
          leaseDuration: lease,
          now: now,
        );

    test('an active, unexpired, recently verified subscription passes', () {
      expect(check(), isTrue);
    });

    test('an inactive flag fails regardless of dates', () {
      expect(check(isActive: false), isFalse);
    });

    test('a missing end date or verification stamp fails', () {
      expect(
        isLeaseValid(
          isActive: true,
          endDate: null,
          lastVerified: now,
          leaseDuration: lease,
          now: now,
        ),
        isFalse,
      );
      expect(
        isLeaseValid(
          isActive: true,
          endDate: now.add(const Duration(days: 10)),
          lastVerified: null,
          leaseDuration: lease,
          now: now,
        ),
        isFalse,
      );
    });

    test('an expired end date fails even when recently verified', () {
      expect(check(endDate: now.subtract(const Duration(days: 1))), isFalse);
    });

    test('verification older than the lease fails', () {
      expect(
        check(lastVerified: now.subtract(const Duration(hours: 49))),
        isFalse,
      );
    });

    test('verification exactly at the lease boundary still passes', () {
      expect(
        check(lastVerified: now.subtract(const Duration(hours: 48))),
        isTrue,
      );
    });
  });
}
