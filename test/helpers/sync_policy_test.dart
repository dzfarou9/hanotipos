import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/helpers/sync_policy.dart';

void main() {
  group('SyncPolicy', () {
    group('shouldRetryAfterFailure', () {
      test('retries while attempts remain', () {
        expect(SyncPolicy.shouldRetryAfterFailure(attempt: 1, maxRetries: 3), isTrue);
        expect(SyncPolicy.shouldRetryAfterFailure(attempt: 2, maxRetries: 3), isTrue);
      });

      test('stops when retries exhausted', () {
        expect(SyncPolicy.shouldRetryAfterFailure(attempt: 3, maxRetries: 3), isFalse);
        expect(SyncPolicy.shouldRetryAfterFailure(attempt: 4, maxRetries: 3), isFalse);
      });

      test('never retries with zero budget', () {
        expect(SyncPolicy.shouldRetryAfterFailure(attempt: 1, maxRetries: 0), isFalse);
      });
    });

    group('needsDirectPull', () {
      test('true when both stores empty', () {
        expect(SyncPolicy.needsDirectPull(productCount: 0, saleCount: 0), isTrue);
      });

      test('false when products exist', () {
        expect(SyncPolicy.needsDirectPull(productCount: 5, saleCount: 0), isFalse);
      });

      test('false when sales exist', () {
        expect(SyncPolicy.needsDirectPull(productCount: 0, saleCount: 2), isFalse);
      });
    });
  });
}
