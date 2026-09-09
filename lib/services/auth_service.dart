// lib/services/auth_service.dart

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/app_config.dart';
import 'firebase_service.dart';
import 'remote_config_service.dart';
import 'database_service.dart';
import 'sync_service.dart';
import '../helpers/platform_helper.dart';
import 'local_auth_service.dart';
import 'package:uuid/uuid.dart';
import '../helpers/localization_helper.dart';

class AuthService {
  static AuthService? _instance;
  AuthService._();

  static AuthService get instance {
    _instance ??= AuthService._();
    return _instance!;
  }

  Future<void> init() async {
    AppConfig.log('===== AuthService initialized =====');
  }

  User? get currentUser {
    try {
      return FirebaseService().currentUser;
    } catch (e) {
      AppConfig.logError('Error getting current user', e);
      return null;
    }
  }

  bool get isLoggedIn {
    try {
      final userId = DatabaseService.instance.getUserId();
      if (userId == null) return false;

      // ⭐ Windows: وضع محلي بلا Firebase — وجود userId كافٍ للجلسة
      if (PlatformHelper.isWindows) return true;

      // currentUser لا يرمي استثناءً أبداً (يعيد null عند تعذر الوصول لـ Firebase)
      final user = FirebaseService().currentUser;
      return user != null && user.uid == userId;
    } catch (e) {
      AppConfig.logError('Error checking login status', e);
      return false;
    }
  }

  String? get userPhone {
    try {
      final phone = DatabaseService.instance.getUserPhone();
      if (phone != null) return phone;
      final user = FirebaseService().currentUser;
      return user?.email?.replaceAll('@hanoti.pos', '');
    } catch (e) {
      AppConfig.logError('Error getting user phone', e);
      return null;
    }
  }

  String? get userName {
    try {
      final name = DatabaseService.instance.getUserFullName();
      if (name != null) return name;
      final user = FirebaseService().currentUser;
      return user?.displayName;
    } catch (e) {
      AppConfig.logError('Error getting user name', e);
      return null;
    }
  }

  String? get storeName {
    try {
      final store = DatabaseService.instance.getStoreName();
      if (store != null) return store;
      final user = FirebaseService().currentUser;
      return user?.displayName;
    } catch (e) {
      AppConfig.logError('Error getting store name', e);
      return null;
    }
  }

  String? get storePhone {
    try {
      return DatabaseService.instance.getStorePhone();
    } catch (e) {
      AppConfig.logError('Error getting store phone', e);
      return null;
    }
  }

  String? get storeAddress {
    try {
      return DatabaseService.instance.getStoreAddress();
    } catch (e) {
      AppConfig.logError('Error getting store address', e);
      return null;
    }
  }

  String? get storeTaxId {
    try {
      return DatabaseService.instance.getStoreTaxId();
    } catch (e) {
      AppConfig.logError('Error getting store tax id', e);
      return null;
    }
  }

  /// ⭐ H-3: تغيير كلمة المرور (تفويض لـ FirebaseService الذي يعيد
  /// المصادقة ثم يحدّث). يرمي Exception برسالة مترجمة عند الفشل.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await FirebaseService().changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  /// يتحقق من صحة كلمة المرور مع Firebase Auth دون تنفيذ دورة
  /// تسجيل الدخول الكاملة (بدون مزامنة). يُرجع true عند النجاح،
  /// ويرمي Exception برسالة مترجمة عند الفشل.
  Future<bool> verifyCredentials({
    required String phone,
    required String password,
  }) async {
    try {
      final credential = await FirebaseService()
          .signInWithPhoneAndPassword(phone: phone, password: password);
      return credential.user != null;
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception(LocalizationHelper.authLoginError);
    }
  }

  Future<bool> login({
    required String phone,
    required String password,
  }) async {
    try {
      AppConfig.log('===== LOGIN STARTED =====');
      AppConfig.log('Phone: $phone');

      // ⭐ Windows: تسجيل دخول محلي بلا Firebase
      if (PlatformHelper.isWindows) {
        return _localSignIn(phone: phone, password: password);
      }

      final firebaseService = FirebaseService();

      // FirebaseService يترجم أكواد FirebaseAuthException إلى رسائل مترجمة
      // ويرميها داخل Exception — نعيد رفعها كما هي للشاشة.
      final credential = await firebaseService.signInWithPhoneAndPassword(
        phone: phone,
        password: password,
      );

      AppConfig.log('Login response: ${credential.user != null}');
      if (kDebugMode) {
        AppConfig.log('User ID: ${credential.user?.uid}');
      }

      if (credential.user != null) {
        final db = DatabaseService.instance;
        final userId = credential.user!.uid;

        await db.saveUserData(
          userId: userId,
          phone: phone,
          fullName: credential.user!.displayName ?? '',
          storeName: credential.user!.displayName ?? '',
        );

        // ⭐ M-9: جلب واحد للاشتراك — signInWithPhoneAndPassword استعلم
        // بالفعل عبر loadAndSaveSubscriptionInfo وحدّث Hive؛ لا نكرر
        // الاستعلام هنا ولا بعد المزامنة.

        // ⭐ Offline First: مزامنة كاملة للحساب (لا ترمي؛ الفشل لا يمنع الدخول)
        await SyncService().syncAfterLogin();

        AppConfig.log('✅ Login successful!');
        return true;
      }

  AppConfig.log('❌ Login failed');
  return false;
} catch (e) {
  AppConfig.logError('❌ Login error', e);
      // ⭐ إعادة رمي أخطاء تسجيل الدخول المعروفة لعرضها للمستخدم
      rethrow;
    }
  }

  Future<bool> register({
    required String phone,
    required String fullName,
    required String storeName,
    required String password,
  }) async {
    try {
      AppConfig.log('===== REGISTRATION STARTED =====');

      // ⭐ Windows: إنشاء حساب محلي بلا Firebase
      if (PlatformHelper.isWindows) {
        final local = LocalAuthService();
        if (await local.hasLocalAccount()) {
          final ok = await local.verifyCredentials(
            phone: phone,
            password: password,
          );
          if (!ok) throw Exception(LocalizationHelper.authLoginError);
          await _saveLocalSession(phone: phone);
          return true;
        }
        await local.createLocalAccount(phone: phone, password: password);
        await _saveLocalSession(phone: phone);
        return true;
      }

      if (kDebugMode) {
        AppConfig.log('Phone: $phone');
        AppConfig.log('Full Name: $fullName');
        AppConfig.log('Store Name: $storeName');
      }

      final firebaseService = FirebaseService();

      AppConfig.log('📤 Calling FirebaseService.signUpWithPhoneAndPassword...');

      // FirebaseService يترجم أكواد FirebaseAuthException إلى رسائل مترجمة
      // ويرميها داخل Exception — نعيد رفعها كما هي للشاشة.
      final credential = await firebaseService.signUpWithPhoneAndPassword(
        phone: phone,
        fullName: fullName,
        storeName: storeName,
        password: password,
      );

      AppConfig.log('Registration response: ${credential.user != null}');
      if (kDebugMode) {
        AppConfig.log('User ID: ${credential.user?.uid}');
      }

      if (credential.user != null) {
        final db = DatabaseService.instance;
        final userId = credential.user!.uid;

        AppConfig.log('📤 Saving user data to Hive...');
        await db.saveUserData(
          userId: userId,
          phone: phone,
          fullName: fullName,
          storeName: storeName,
        );
        AppConfig.log('✅ User data saved to Hive');

        AppConfig.log('📤 Fetching subscription info...');
        try {
          final subInfo = await firebaseService.getSubscriptionInfo();
          if (subInfo != null && subInfo['end_date'] != null) {
            await db.saveSubscriptionEndDate(subInfo['end_date']);
            await db.saveSubscriptionActive(true);
            AppConfig.log('✅ Subscription info saved to Hive');
          } else {
            final trialEndDate = DateTime.now().add(
              Duration(days: await RemoteConfigService.instance.getTrialDays()),
            );
            await db.saveSubscriptionEndDate(trialEndDate);
            await db.saveSubscriptionActive(true);
            AppConfig.log('⚠️ Created temporary trial in Hive');
          }
        } catch (e) {
          AppConfig.logError('⚠️ Could not fetch subscription info', e);
          final trialEndDate = DateTime.now().add(
            Duration(days: await RemoteConfigService.instance.getTrialDays()),
          );
          await db.saveSubscriptionEndDate(trialEndDate);
          await db.saveSubscriptionActive(true);
        }

        // ⭐ Offline First: مزامنة كاملة للبيانات
        AppConfig.log('📤 Syncing data...');
        final syncService = SyncService();

        try {
          // ⭐ محاولة المزامنة الكاملة مع Firebase
          await syncService.syncNow(fullSync: true);
          AppConfig.log('✅ Sync completed');
        } catch (e) {
          AppConfig.logError('⚠️ Sync failed', e);
          // ⭐ سيتم المزامنة في الخلفية لاحقاً
        }

        AppConfig.log('✅ ===== REGISTRATION COMPLETED SUCCESSFULLY =====');
        return true;
      }

      AppConfig.log('❌ Registration failed');
      return false;
    } catch (e) {
      AppConfig.logError('❌❌❌ Registration error', e);
      rethrow;
    }
  }

  Future<void> logout() async {
    AppConfig.log('===== LOGOUT STARTED =====');

    // ⭐ H-1: كل خطوة مستقلة try/catch — فشل إحداها لا يمنع الباقي.
    // الترتيب: تسجيل الخروج من Firebase أولاً ثم مسح Hive، حتى لا يترك
    // فشل المسح جلسة حيّة ببيانات قديمة على الجهاز.

    // ⭐ 1) تسجيل الخروج من Firebase
    try {
      await FirebaseService().signOut();
    } catch (e) {
      AppConfig.logError('⚠️ Firebase logout failed', e);
    }

    // ⭐ 2) إعادة ضبط حالة المزامنة (أعلام/أخطاء الحساب السابق)
    try {
      SyncService().reset();
    } catch (e) {
      AppConfig.logError('⚠️ Sync reset failed', e);
    }

    // ⭐ 3) مسح بيانات المستخدم من Hive
    try {
      await DatabaseService.instance.clearUserData();
    } catch (e) {
      AppConfig.logError('⚠️ Hive wipe failed', e);
    }

    AppConfig.log('✅ Logout completed');
  }

  Future<bool> validateSession() async {
    try {
      final userId = DatabaseService.instance.getUserId();
      if (userId == null) {
        AppConfig.log('⚠️ No user ID in Hive');
        return false;
      }

      // ⭐ Windows: وضع محلي — userId كافٍ
      if (PlatformHelper.isWindows) return true;

      final user = FirebaseService().currentUser;
      if (user == null) {
        AppConfig.log('⚠️ No user in Firebase session');
        return false;
      }

      if (user.uid != userId) {
        AppConfig.log('⚠️ User ID mismatch');
        return false;
      }

      return true;
    } catch (e) {
      AppConfig.logError('❌ Session validation error', e);
      return false;
    }
  }

  Future<bool> isSubscriptionActive() async {
    try {
      final firebaseService = FirebaseService();
      return await firebaseService.isSubscriptionActive();
    } catch (e) {
      AppConfig.logError('⚠️ Subscription check error', e);
      return DatabaseService.instance.getSubscriptionActive();
    }
  }

  Future<Map<String, dynamic>?> getSubscriptionInfo() async {
    try {
      final firebaseService = FirebaseService();
      return await firebaseService.getSubscriptionInfo();
    } catch (e) {
      AppConfig.logError('⚠️ Subscription info error', e);
      return null;
    }
  }

  /// ⭐ Windows: دخول محلي — أول استخدام ينشئ الحساب، ما بعده يتحقق.
  Future<bool> _localSignIn({
    required String phone,
    required String password,
  }) async {
    final local = LocalAuthService();
    if (!await local.hasLocalAccount()) {
      await local.createLocalAccount(phone: phone, password: password);
      await _saveLocalSession(phone: phone);
      AppConfig.log('✅ Local account created (Windows)');
      return true;
    }
    final ok = await local.verifyCredentials(phone: phone, password: password);
    if (!ok) {
      throw Exception(LocalizationHelper.authLoginError);
    }
    await _saveLocalSession(phone: phone);
    return true;
  }

  /// ⭐ Windows: حفظ جلسة محلية (userId ثابت + تجربة 30 يوم بلا Firebase)
  Future<void> _saveLocalSession({required String phone}) async {
    final db = DatabaseService.instance;
    final userId = await LocalAuthService().localUserId();
    await db.saveUserData(
      userId: userId ?? const Uuid().v4(),
      phone: phone,
      fullName: '',
      storeName: '',
    );
    await db.saveSubscriptionEndDate(
      DateTime.now().add(const Duration(days: 30)),
    );
    await db.saveSubscriptionActive(true);
  }
}
