import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/helpers/platform_helper.dart';

void main() {
  tearDown(() {
    PlatformHelper.resetOverride();
  });

  test('override forces isWindows true', () {
    PlatformHelper.overrideForTest(true);
    expect(PlatformHelper.isWindows, isTrue);
  });

  test('override forces isWindows false on Windows host', () {
    PlatformHelper.overrideForTest(false);
    expect(PlatformHelper.isWindows, isFalse);
  });

  test('resetOverride restores real platform', () {
    PlatformHelper.overrideForTest(true);
    PlatformHelper.resetOverride();
    // مضيف الاختبار هو Windows — إعادة الضبط تعيد true
    expect(PlatformHelper.isWindows, isTrue);
  });
}
