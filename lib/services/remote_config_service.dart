// lib/services/remote_config_service.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../config/app_config.dart';
import '../config/firebase_config.dart';

class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  static const String trialDaysKey = 'trial_days';
  static const int minTrialDays = 0;
  // ⭐ M-11: سقف صارم للتجربة (7 أيام) — يطابق نية العمل وقواعد Firestore.
  // القيمة المنشورة في Remote Config يجب أن تكون 7؛ أي قيمة أعلى تُقصّ إلى 7.
  static const int maxTrialDays = 7;

  FirebaseRemoteConfig? _remoteConfig;

  /// يحوّل قيمة Remote Config إلى عدد أيام صالح.
  /// أي قيمة غير رقمية أو فارغة تعيد الافتراضي من FirebaseConfig.trialDays،
  /// والقيم خارج المدى [minTrialDays, maxTrialDays] تُقصّ.
  static int parseTrialDays(Object? value) {
    final int parsed;
    if (value is int) {
      parsed = value;
    } else {
      final raw = value?.toString().trim() ?? '';
      parsed = int.tryParse(raw) ?? FirebaseConfig.trialDays;
    }
    if (parsed < minTrialDays) return minTrialDays;
    if (parsed > maxTrialDays) return maxTrialDays;
    return parsed;
  }

  bool get _initialized => _remoteConfig != null && Firebase.apps.isNotEmpty;

  Future<void> init() async {
    try {
      if (Firebase.apps.isEmpty) {
        AppConfig.log('⚠️ Firebase not initialized, skipping RemoteConfig');
        return;
      }
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );
      await remoteConfig.setDefaults(<String, Object?>{
        trialDaysKey: FirebaseConfig.trialDays,
      });
      // جلب أولي بدون انتظار طويل: القيم المخزنة كافية عند الفشل
      try {
        await remoteConfig.fetchAndActivate().timeout(
              const Duration(seconds: 5),
            );
        AppConfig.log('✅ Remote Config fetched and activated');
      } catch (e) {
        AppConfig.log('⚠️ Remote Config initial fetch failed, using defaults');
      }
      _remoteConfig = remoteConfig;
    } catch (e) {
      AppConfig.logError('⚠️ Remote Config init error', e);
    }
  }

  /// مدة التجربة الحالية: يجلب أحدث قيمة إن أمكن ثم يقرأها.
  /// لا يرمي استثناءات أبداً؛ يعيد الافتراضي عند أي فشل.
  Future<int> getTrialDays() async {
    final config = _remoteConfig;
    if (!_initialized || config == null) return FirebaseConfig.trialDays;
    try {
      await config.fetchAndActivate().timeout(const Duration(seconds: 5));
    } catch (_) {
      // نكمل بالقيمة المخزنة سابقاً أو الافتراضية
    }
    return parseTrialDays(config.getString(trialDaysKey));
  }
}
