import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/services/barcode_input_service.dart';

void main() {
  late BarcodeInputService service;

  KeyDownEvent key(String? character, LogicalKeyboardKey logicalKey) {
    return KeyDownEvent(
      physicalKey: PhysicalKeyboardKey(logicalKey.keyId & 0xFFFFFFFF),
      logicalKey: logicalKey,
      character: character,
      timeStamp: Duration.zero,
    );
  }

  KeyDownEvent charKey(String c) {
    return KeyDownEvent(
      physicalKey: PhysicalKeyboardKey(c.codeUnitAt(0)),
      logicalKey: LogicalKeyboardKey(c.codeUnitAt(0) + 0x100000000),
      character: c,
      timeStamp: Duration.zero,
    );
  }

  setUp(() {
    service = BarcodeInputService.forTest();
  });

  test('fast digit burst + Enter emits scan', () async {
    final scans = <String>[];
    final sub = service.scans.listen(scans.add);
    for (final c in '6290123456789'.split('')) {
      service.handleKeyEvent(charKey(c));
    }
    service.handleKeyEvent(key(null, LogicalKeyboardKey.enter));
    await Future<void>.delayed(Duration.zero);
    expect(scans, ['6290123456789']);
    await sub.cancel();
  });

  test('short burst is ignored', () async {
    final scans = <String>[];
    final sub = service.scans.listen(scans.add);
    for (final c in '123'.split('')) {
      service.handleKeyEvent(charKey(c));
    }
    service.handleKeyEvent(key(null, LogicalKeyboardKey.enter));
    await Future<void>.delayed(Duration.zero);
    expect(scans, isEmpty);
    await sub.cancel();
  });

  test('second scan after first emits again', () async {
    final scans = <String>[];
    final sub = service.scans.listen(scans.add);
    for (final c in '6290123456789'.split('')) {
      service.handleKeyEvent(charKey(c));
    }
    service.handleKeyEvent(key(null, LogicalKeyboardKey.enter));
    for (final c in '6290123456780'.split('')) {
      service.handleKeyEvent(charKey(c));
    }
    service.handleKeyEvent(key(null, LogicalKeyboardKey.enter));
    await Future<void>.delayed(Duration.zero);
    expect(scans, ['6290123456789', '6290123456780']);
    await sub.cancel();
  });

  test('gap between bursts splits scans', () async {
    final scans = <String>[];
    final sub = service.scans.listen(scans.add);
    // Burst قصير (< minLength) يُهمَل عند Enter
    service.handleKeyEvent(charKey('1'));
    service.handleKeyEvent(charKey('2'));
    service.handleKeyEvent(key(null, LogicalKeyboardKey.enter));
    // فجوة حقيقية > interKeyGapMs تُفرّغ buffer فيurst التالي
    await Future<void>.delayed(
      const Duration(milliseconds: BarcodeInputService.interKeyGapMs + 20),
    );
    for (final c in '3456'.split('')) {
      service.handleKeyEvent(charKey(c));
    }
    service.handleKeyEvent(key(null, LogicalKeyboardKey.enter));
    await Future<void>.delayed(Duration.zero);
    expect(scans, ['3456']);
    await sub.cancel();
  });

  test('non-down events are ignored', () async {
    final scans = <String>[];
    final sub = service.scans.listen(scans.add);
    service.handleKeyEvent(KeyRepeatEvent(
      physicalKey: PhysicalKeyboardKey(LogicalKeyboardKey.digit1.keyId & 0xFFFFFFFF),
      logicalKey: LogicalKeyboardKey.digit1,
      character: '1',
      timeStamp: Duration.zero,
    ));
    service.handleKeyEvent(key(null, LogicalKeyboardKey.enter));
    await Future<void>.delayed(Duration.zero);
    expect(scans, isEmpty);
    await sub.cancel();
  });
}
