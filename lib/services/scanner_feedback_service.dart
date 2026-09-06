// lib/services/scanner_feedback_service.dart
//
// خدمة التغذية الراجعة عند المسح: صوت "بيب" + اهتزاز لتمييز نجاح المسح
// عن عدم العثور على المنتج. تُستخدم من شاشتي نقطة البيع والمخزون.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class ScannerFeedbackService {
  static AudioPlayer? _player;

  /// ⭐ صوت النجاح + اهتزاز خفيف عند التعرف على باركود صالح (كل شاشة).
  static void playScanSuccess() {
    HapticFeedback.lightImpact();
    _playBeep();
  }

  /// اهتزاز متوسط عند العثور على المنتج وإضافته.
  static void productFound() {
    HapticFeedback.mediumImpact();
  }

  /// اهتزاز قوي عند عدم العثور على المنتج.
  static void productNotFound() {
    HapticFeedback.heavyImpact();
  }

  /// اهتزاز عند محاولة إضافة منتج نفد مخزونه.
  static void outOfStock() {
    HapticFeedback.heavyImpact();
  }

  static Future<void> _playBeep() async {
    try {
      _player ??= AudioPlayer();
      await _player?.stop();
      await _player?.play(AssetSource('audio/beep.wav'));
    } catch (e) {
      print('⚠️ Scanner beep failed: $e');
    }
  }
}