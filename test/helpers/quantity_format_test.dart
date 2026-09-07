// test/helpers/quantity_format_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/helpers/quantity_format.dart';

void main() {
  group('QuantityFormat.round', () {
    test('rounds to 3 decimals', () {
      expect(QuantityFormat.round(0.8504), 0.85);
      expect(QuantityFormat.round(1.23456), 1.235);
      expect(QuantityFormat.round(2), 2.0);
    });
  });

  group('QuantityFormat.quantity', () {
    test('trims trailing zeros', () {
      expect(QuantityFormat.quantity(2.0), '2');
      expect(QuantityFormat.quantity(0.85), '0.85');
      expect(QuantityFormat.quantity(2.5), '2.5');
      expect(QuantityFormat.quantity(-0.5), '-0.5');
      expect(QuantityFormat.quantity(0), '0');
    });
  });

  group('epsilon comparisons', () {
    test('treats sub-epsilon deltas as equal', () {
      expect(QuantityFormat.isZeroQty(0.0009), isTrue);
      expect(QuantityFormat.isZeroQty(0.01), isFalse);
      expect(QuantityFormat.greaterThanQty(0.85, 0.85), isFalse);
      expect(QuantityFormat.greaterThanQty(0.9, 0.85), isTrue);
      expect(QuantityFormat.exceedsQty(0.85, 0.85), isFalse);
      expect(QuantityFormat.exceedsQty(0.9, 0.85), isTrue);
    });
  });
}
