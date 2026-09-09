// lib/services/barcode_input_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Windows: قارئ باركود USB (keyboard wedge) — يكتب الرمز بسرعة ثم Enter.
/// نكشف Stream<String> للشاشات للتعامل معه مثل onBarcodeDetected.
class BarcodeInputService {
  static BarcodeInputService? _instance;

  BarcodeInputService._();

  static BarcodeInputService get instance {
    _instance ??= BarcodeInputService._();
    return _instance!;
  }

  /// للاختبارات: نسخة معزولة بلا معالج keyboard عام.
  factory BarcodeInputService.forTest() => BarcodeInputService._();

  static const int minLength = 4;
  static const int interKeyGapMs = 50;
  static const int maxScanDurationMs = 1500;

  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  Stream<String> get scans => _controller.stream;

  final StringBuffer _buffer = StringBuffer();
  DateTime _firstKeyTime = DateTime.now();
  DateTime _lastKeyTime = DateTime.now();
  bool _installed = false;

  /// تسجيل معالج keyboard العام (يستدعى مرة واحدة من main).
  void init() {
    if (_installed) return;
    _installed = true;
    HardwareKeyboard.instance.addHandler(handleKeyEvent);
  }

  void dispose() {
    if (_installed) {
      HardwareKeyboard.instance.removeHandler(handleKeyEvent);
      _installed = false;
    }
  }

  /// يعيد true فقط إذا استهلك الحدث (لا يستهلك شيئاً —
  /// نترك حقول النص تستقبل الإدخال كالمعتاد).
  @visibleForTesting
  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _flush();
      return false;
    }
    final character = event.character;
    if (character == null || character.isEmpty) return false;
    final trimmed = character.trim();
    if (trimmed.isEmpty) return false;
    final now = DateTime.now();
    if (now.difference(_lastKeyTime).inMilliseconds > interKeyGapMs) {
      _buffer.clear();
      _firstKeyTime = now;
    }
    _lastKeyTime = now;
    _buffer.write(trimmed);
    return false;
  }

  void _flush() {
    final code = _buffer.toString().trim();
    _buffer.clear();
    final now = DateTime.now();
    if (code.length < minLength) return;
    if (now.difference(_firstKeyTime).inMilliseconds > maxScanDurationMs) {
      return;
    }
    _controller.add(code);
  }
}
