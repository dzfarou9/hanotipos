import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/helpers/direction_helper.dart';

void main() {
  group('appTextDirection', () {
    test('stays LTR for Arabic locale so the layout is not mirrored', () {
      expect(appTextDirection(const Locale('ar', 'SA')), TextDirection.ltr);
    });

    test('stays LTR for English and French locales', () {
      expect(appTextDirection(const Locale('en', 'US')), TextDirection.ltr);
      expect(appTextDirection(const Locale('fr', 'FR')), TextDirection.ltr);
    });
  });
}