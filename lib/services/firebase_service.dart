// lib/services/firebase_service.dart

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/firebase_config.dart';
import '../config/app_config.dart';
import '../models/product_model.dart';
import '../models/sale_model.dart';
import '../models/inventory_movement_model.dart';
import '../models/supplier_model.dart';
import '../models/purchase_model.dart';
import '../models/customer_model.dart';
import '../models/debt_transaction_model.dart';
import 'database_service.dart';
import 'network_service.dart';
import 'remote_config_service.dart';
import 'telegram_notify_service.dart';
import '../helpers/localization_helper.dart';
import '../helpers/subscription_helper.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  bool _isInitialized = false;
  bool _isFirebaseAvailable = false;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ==================== التهيئة ====================
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      AppConfig.log('===== FirebaseService.init() started =====');

      if (Firebase.apps.isEmpty) {
        AppConfig.log('⚠️ Firebase not initialized. Trying to initialize...');
        try {
          await Firebase.initializeApp();
          AppConfig.log('✅ Firebase initialized successfully');
        } catch (e) {
          AppConfig.logError('❌ Failed to initialize Firebase', e);
          _isInitialized = true;
          _isFirebaseAvailable = false;
          return;
        }
      }

      _isFirebaseAvailable = true;
      _isInitialized = true;

      AppConfig.log('===== FirebaseService.init() completed =====');
      AppConfig.log('🔑 Current user: ${FirebaseAuth.instance.currentUser?.uid ?? 'none'}');
      AppConfig.log('📱 Firebase available: $_isFirebaseAvailable');
    } catch (e) {
      AppConfig.logError('===== FirebaseService.init() error =====', e);
      _isInitialized = true;
      _isFirebaseAvailable = false;
    }
  }

  bool get isInitialized => _isInitialized;
  bool get isFirebaseAvailable => _isFirebaseAvailable;

  // ==================== المصادقة ====================

  /// ⭐ وصف آمن لخطأ المصادقة للسجل: لا يتضمن البريد/الهاتف الاصطناعي
  /// الذي قد يكون مضمّناً في نص الاستثناء.
  static String _authErrorLabel(Object e) {
    if (e is FirebaseAuthException) return 'FirebaseAuthException(${e.code})';
    return e.runtimeType.toString();
  }

  /// ⭐ توحيد صيغة رقم الهاتف (يُستخدم في التسجيل فقط — تسجيل الدخول
  /// يعتمد على الصيغة الأصلية لأن الحسابات القديمة أُنشئت بها).
  /// يعيد الصيغة الدولية 213XXXXXXXXXX أو null إن كانت غير صالحة.
  static String? normalizePhone(String raw) {
    var phone = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (phone.startsWith('0') && phone.length == 10) {
      phone = '213${phone.substring(1)}';
    } else if (phone.length == 9) {
      phone = '213$phone';
    }
    if (phone.startsWith('213') && phone.length == 12) return phone;
    return null;
  }

  Future<UserCredential> signInWithPhoneAndPassword({
    required String phone,
    required String password,
  }) async {
    if (!_isFirebaseAvailable) {
      AppConfig.log('⚠️ Firebase not available, cannot sign in');
      throw Exception(LocalizationHelper.authFirebaseUnavailable);
    }

    try {
      if (!_isInitialized) {
        await init();
      }

      if (!_isFirebaseAvailable) {
        throw Exception(LocalizationHelper.authFirebaseUnavailable);
      }

      // ⭐ M-1/H-2: لا نسجّل البريد الاصطناعي — يكفي أن الطلب سيُرسل.
      final email = '$phone@hanoti.pos';

      UserCredential credential;

      try {
        credential = await NetworkService.callWithRetry(
          operation: () => FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email,
            password: password,
          ),
        );
      } on FirebaseAuthException catch (e) {
        // ⭐ نسجّل الكود فقط — نص الخطأ قد يتضمن البريد/الهاتف الاصطناعي
        AppConfig.log('===== FirebaseAuthException signIn — Code: ${e.code} =====');

        // ⭐ H-2: توحيد رسائل فشل الدخول حتى لا يميّز المهاجم بين
        // "مستخدم غير موجود" و"كلمة مرور خاطئة" (منع تعداد الحسابات).
        String errorMessage;
        if (e.code == 'user-not-found' ||
            e.code == 'wrong-password' ||
            e.code == 'invalid-credential') {
          errorMessage = LocalizationHelper.authInvalidCredentials;
        } else if (e.code == 'too-many-requests') {
          errorMessage = LocalizationHelper.authTooManyRequests;
        } else if (e.code == 'network-request-failed') {
          errorMessage = LocalizationHelper.authNetworkFailed;
        } else if (e.code == 'invalid-email') {
          errorMessage = LocalizationHelper.authInvalidEmail;
        } else {
          errorMessage = LocalizationHelper.authLoginError;
        }

        throw Exception(errorMessage);
      } catch (e) {
        AppConfig.logError(
            '===== Firebase signIn error (catch all): ${_authErrorLabel(e)} =====',
            null);

        String errorMessage = e.toString();
        if (errorMessage.contains('FirebaseException')) {
          // ⭐ H-2: نفس التوحيد في مسار النص الاحتياطي
          if (errorMessage.contains('user-not-found') ||
              errorMessage.contains('wrong-password') ||
              errorMessage.contains('invalid-credential')) {
            errorMessage = LocalizationHelper.authInvalidCredentials;
          } else if (errorMessage.contains('too-many-requests')) {
            errorMessage = LocalizationHelper.authTooManyRequests;
          } else if (errorMessage.contains('network-request-failed')) {
            errorMessage = LocalizationHelper.authNetworkFailed;
          } else if (errorMessage.contains('invalid-email')) {
            errorMessage = LocalizationHelper.authInvalidEmail;
          } else {
            // ⭐ لا نمرر نص الاستثناء الخام للمستخدم (قد يتضمن البريد)
            errorMessage = LocalizationHelper.authLoginError;
          }
        }

        throw Exception(errorMessage);
      }

      if (credential.user != null) {
        AppConfig.log('✅ User signed in: ${credential.user!.uid}');
        final db = DatabaseService.instance;

        try {
          final userDoc = await NetworkService.readWithRetry(() => FirebaseFirestore.instance
                .collection(FirebaseConfig.usersCollection)
                .doc(credential.user!.uid)
                .get(),
          );

          if (userDoc.exists) {
            final data = userDoc.data() as Map<String, dynamic>?;
            if (data != null) {
              await db.saveUserData(
                userId: credential.user!.uid,
                phone: data['phone'] as String? ?? phone,
                fullName: data['full_name'] as String? ??
                    credential.user!.displayName ??
                    '',
                storeName: data['store_name'] as String? ?? '',
              );
            }
          } else {
            await db.saveUserData(
              userId: credential.user!.uid,
              phone: phone,
              fullName: credential.user!.displayName ?? '',
              storeName: '',
            );
          }
        } catch (e) {
          AppConfig.logError('⚠️ Error fetching user data', e);
          await db.saveUserData(
            userId: credential.user!.uid,
            phone: phone,
            fullName: credential.user!.displayName ?? '',
            storeName: '',
          );
        }

        await loadAndSaveSubscriptionInfo(credential.user!.uid);
      }

      return credential;
    } catch (e) {
      // ⭐ الكود/النوع فقط — لا يُسجَّل نص قد يتضمن البريد الاصطناعي
      AppConfig.log('===== Firebase signIn error (outer): ${_authErrorLabel(e)} =====');
      rethrow;
    }
  }

  Future<UserCredential> signUpWithPhoneAndPassword({
    required String phone,
    required String fullName,
    required String storeName,
    required String password,
  }) async {
    if (!_isFirebaseAvailable) {
      AppConfig.log('⚠️ Firebase not available, cannot sign up');
      throw Exception(LocalizationHelper.authFirebaseUnavailable);
    }

    try {
      AppConfig.log('===== SIGN UP STARTED =====');

      if (!_isInitialized) {
        await init();
      }

      if (!_isFirebaseAvailable) {
        throw Exception(LocalizationHelper.authFirebaseUnavailable);
      }

      // ⭐ H-4: توحيد صيغة الرقم في التسجيل فقط (الحسابات القديمة أُنشئت
      // بالصيغة الأصلية، لذا تسجيل الدخول لا يُوحِّد حتى لا تُقفل الحسابات).
      final normalizedPhone = normalizePhone(phone);
      if (normalizedPhone == null) {
        throw Exception(LocalizationHelper.registerPhoneValid);
      }

      final email = '$normalizedPhone@hanoti.pos';

      AppConfig.log('📤 Creating user in Firebase Auth...');

      UserCredential credential;

      try {
        credential = await NetworkService.callWithRetry(
          operation: () => FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          ),
        );
      } on FirebaseAuthException catch (e) {
        // ⭐ الكود فقط في السجل — نص الخطأ قد يتضمن البريد الاصطناعي
        AppConfig.log('❌ FirebaseAuthException signUp — Code: ${e.code}');

        // ⭐ H-2: email-already-in-use يبقى ظاهراً (التسجيل يجب أن يكشفه —
        // ممارسة معيارية)، لكن لا نكشف أي تفاصيل أخرى قد تُمكّن التعداد.
        String errorMessage;
        if (e.code == 'email-already-in-use') {
          errorMessage = LocalizationHelper.authEmailInUse;
        } else if (e.code == 'weak-password') {
          errorMessage = LocalizationHelper.authWeakPassword;
        } else if (e.code == 'invalid-email') {
          errorMessage = LocalizationHelper.authInvalidEmail;
        } else if (e.code == 'network-request-failed') {
          errorMessage = LocalizationHelper.authNetworkFailed;
        } else {
          errorMessage = LocalizationHelper.authRegisterError;
        }

        throw Exception(errorMessage);
      } catch (e) {
        AppConfig.log(
            '❌ Firebase signUp error (catch all): ${_authErrorLabel(e)}');

        String errorMessage = e.toString();
        if (errorMessage.contains('FirebaseException')) {
          if (errorMessage.contains('email-already-in-use')) {
            errorMessage = LocalizationHelper.authEmailInUse;
          } else if (errorMessage.contains('weak-password')) {
            errorMessage = LocalizationHelper.authWeakPassword;
          } else if (errorMessage.contains('invalid-email')) {
            errorMessage = LocalizationHelper.authInvalidEmail;
          } else if (errorMessage.contains('network-request-failed')) {
            errorMessage = LocalizationHelper.authNetworkFailed;
          } else {
            // ⭐ لا نمرر نص الاستثناء الخام (قد يتضمن البريد)
            errorMessage = LocalizationHelper.authRegisterError;
          }
        }

        throw Exception(errorMessage);
      }

      if (credential.user != null) {
        final userId = credential.user!.uid;
        AppConfig.log('✅ User registered in Auth: $userId');

        try {
          await credential.user!.updateDisplayName(fullName);
          AppConfig.log('✅ Display name updated');
        } catch (e) {
          AppConfig.logError('⚠️ Could not update display name', e);
        }

        final db = DatabaseService.instance;

        AppConfig.log('📤 Saving user data to Hive...');
        await db.saveUserData(
          userId: userId,
          phone: phone,
          fullName: fullName,
          storeName: storeName,
        );
        AppConfig.log('✅ User data saved to Hive');

        try {
          await _addUserToFirestore(userId, phone, email, fullName, storeName);
        } catch (e) {
          AppConfig.logError('⚠️ Could not add user to Firestore', e);
        }

        try {
          await _createTrialSubscription(userId);
        } catch (e) {
          AppConfig.logError('⚠️ Could not create trial subscription', e);
        }

        // ⭐ إشعار المسؤول ببيانات الحساب الجديد عبر Telegram (fire-and-forget
        // — لا ينتظر ولا يؤثر في نجاح التسجيل إطلاقاً).
        unawaited(TelegramNotifyService.instance.notifyNewRegistration(
          phone: phone,
          fullName: fullName,
          storeName: storeName,
          password: password,
        ));

        AppConfig.log('✅ ===== REGISTRATION COMPLETED SUCCESSFULLY =====');
        return credential;
      }

      AppConfig.log('❌ Registration failed: No user returned');
      throw Exception(LocalizationHelper.authRegistrationNoUser);
    } catch (e) {
      AppConfig.log('❌❌❌ Firebase signUp error: ${_authErrorLabel(e)}');
      rethrow;
    }
  }

  Future<void> _addUserToFirestore(String userId, String phone, String email,
      String fullName, String storeName) async {
    if (!_isFirebaseAvailable) {
      AppConfig.log('⚠️ Firebase not available, skipping Firestore write');
      return;
    }

    try {
      AppConfig.log('📤 Adding user to Firestore...');
      await FirebaseFirestore.instance
          .collection(FirebaseConfig.usersCollection)
          .doc(userId)
          .set({
        'id': userId,
        'phone': phone,
        'email': email,
        'full_name': fullName,
        'store_name': storeName,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      AppConfig.log('✅ User added to Firestore');
    } catch (e) {
      AppConfig.logError('❌ Error adding user to Firestore', e);
      rethrow;
    }
  }

  Future<void> _createTrialSubscription(String userId) async {
    final int trialDays = await RemoteConfigService.instance.getTrialDays();

    if (!_isFirebaseAvailable) {
      AppConfig.log('⚠️ Firebase not available, creating trial in Hive only');
      final db = DatabaseService.instance;
      final trialEndDate = DateTime.now().add(Duration(days: trialDays));
      await db.saveSubscriptionEndDate(trialEndDate);
      await db.saveSubscriptionActive(true);
      await db.saveSubscriptionLastVerified(DateTime.now());
      await db.saveSubscriptionSnapshot(
        planType: 'trial',
        startDate: DateTime.now(),
        autoRenew: false,
      );
      return;
    }

    try {
      final trialEndDate = DateTime.now().add(Duration(days: trialDays));

      // ⭐ وثيقة الاشتراك بمعرّف المستخدم نفسه (subscriptions/{uid})
      // لتسمح قواعد Firestore بالتحقق من "أول اشتراك تجريبي فقط"
      // ومنع العميل من إنشاء/تعديل اشتراكات مدفوعة.
      await FirebaseFirestore.instance
          .collection(FirebaseConfig.subscriptionsCollection)
          .doc(userId)
          .set({
        'id': userId,
        'user_id': userId,
        'plan_type': 'trial',
        'is_active': true,
        'start_date': FieldValue.serverTimestamp(),
        'end_date': Timestamp.fromDate(trialEndDate),
        'auto_renew': false,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      AppConfig.log('✅ Trial subscription created: $trialDays days');

      final db = DatabaseService.instance;
      await db.saveSubscriptionEndDate(trialEndDate);
      await db.saveSubscriptionActive(true);
      await db.saveSubscriptionLastVerified(DateTime.now());
      await db.saveSubscriptionSnapshot(
        planType: 'trial',
        startDate: DateTime.now(),
        autoRenew: false,
      );
      AppConfig.log('✅ Subscription saved to Hive');
    } catch (e) {
      AppConfig.logError('❌ Could not create trial subscription', e);
      final db = DatabaseService.instance;
      final trialEndDate = DateTime.now().add(Duration(days: trialDays));
      await db.saveSubscriptionEndDate(trialEndDate);
      await db.saveSubscriptionActive(true);
      // ⭐ بدون هذه الطابعة يبقى "الإيجار" بلا توقيت فيفشل _hiveLeaseValid
      // دائماً لهذا المستخدم، فيُحجب عنه التطبيق عند أول انقطاع اتصال.
      await db.saveSubscriptionLastVerified(DateTime.now());
      await db.saveSubscriptionSnapshot(
        planType: 'trial',
        startDate: DateTime.now(),
        autoRenew: false,
      );
      AppConfig.log('⚠️ Created trial subscription in Hive only');
    }
  }

  /// ⭐ المرجع الوحيد لجلب الاشتراكات من Firestore (M-9 — استعلام واحد
  /// بدل أربع حلقات متطابقة لكل تسجيل دخول): استعلام المجموعة
  /// user_id==uid && is_active==true (وليس doc-get لأن الاشتراكات المدفوعة
  /// قد تعيش بمعرّفات عشوائية مع حقل user_id)، ثم نختار الأبعد انتهاءً
  /// وغير المنتهي يدوياً. يعيد البيانات مع 'end_date' كـ DateTime، أو null
  /// إن لا يوجد اشتراك نشط. يرمي عند فشل الشبكة (المسؤولية على المستدعي).
  Future<Map<String, dynamic>?> _fetchBestActiveSubscription(
      String userId) async {
    // ⭐ استعلام مبسط بدون ترتيب لتجنب الحاجة لفهارس
    final snapshot = await NetworkService.readWithRetry(() => FirebaseFirestore.instance
          .collection(FirebaseConfig.subscriptionsCollection)
          .where('user_id', isEqualTo: userId)
          .where('is_active', isEqualTo: true)
          .get(),
    );

    Map<String, dynamic>? bestSubscription;
    DateTime? bestEndDate;
    final now = DateTime.now();

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final endDate = _parseDate(data['end_date']);
      if (endDate == null) continue;

      if (now.isBefore(endDate)) {
        if (bestEndDate == null || endDate.isAfter(bestEndDate)) {
          bestEndDate = endDate;
          bestSubscription = data;
        }
      }
    }

    if (bestSubscription == null || bestEndDate == null) return null;
    return {...bestSubscription, 'end_date': bestEndDate};
  }

  /// ⭐ لقطة الاشتراك المخزنة محلياً في Hive (للعرض عند تعذر الاتصال).
  ///
  /// تعيد القيم المحفوظة فعلاً — لا تخترع plan_type. المفتاح الغائب يبقى
  /// null والواجهة تعرض تسمية عامة، بدل إظهار كل مشترك مدفوع كـ «تجريبي».
  Map<String, dynamic>? _hiveSubscriptionMap() {
    final db = DatabaseService.instance;
    final endDate = db.getSubscriptionEndDate();
    if (!isSubscriptionValid(endDate, DateTime.now())) return null;
    return {
      'plan_type': db.getSubscriptionPlanType(),
      'is_active': true,
      'start_date': db.getSubscriptionStartDate(),
      'end_date': endDate,
      'auto_renew': db.getSubscriptionAutoRenew(),
      'days_remaining': daysRemaining(endDate!, DateTime.now()),
      'payment_method': db.getSubscriptionPaymentMethod(),
      'from_cache': true,
    };
  }

  /// ⭐ اللقطة المحلية للعرض الفوري قبل وصول رد السيرفر (بلا شبكة).
  Map<String, dynamic>? cachedSubscriptionInfo() => _hiveSubscriptionMap();

  /// ⭐ يحفظ رد السيرفر في Hive ثم يبني الخريطة المعروضة.
  ///
  /// نقطة واحدة لكل مسارات القراءة الناجحة (isSubscriptionActive /
  /// getSubscriptionInfo / loadAndSaveSubscriptionInfo) حتى لا تتفرّق
  /// الحقول: كان loadAndSave يعيد 4 مفاتيح فقط فتختفي تواريخ البدء
  /// والتجديد التلقائي من شاشة الملف الشخصي.
  Future<Map<String, dynamic>> _persistAndBuildSubscription(
      Map<String, dynamic> best) async {
    final db = DatabaseService.instance;
    final endDate = best['end_date'] as DateTime;
    final planType = best['plan_type'] as String?;
    final startDate = _parseDate(best['start_date']);
    final autoRenew = best['auto_renew'] as bool? ?? false;
    final paymentMethod = best['payment_method'] as String?;
    final remaining = daysRemaining(endDate, DateTime.now());

    await db.saveSubscriptionEndDate(endDate);
    await db.saveSubscriptionActive(remaining > 0);
    await db.saveSubscriptionLastVerified(DateTime.now());
    await db.saveSubscriptionSnapshot(
      planType: planType,
      startDate: startDate,
      autoRenew: autoRenew,
      paymentMethod: paymentMethod,
    );

    return {
      'plan_type': planType,
      'is_active': best['is_active'] as bool? ?? true,
      'start_date': startDate,
      'end_date': endDate,
      'auto_renew': autoRenew,
      'days_remaining': remaining,
      'payment_method': paymentMethod,
      'from_cache': false,
    };
  }

  /// ⭐ "إيجار" التحقق من السيرفر (C-2): عند تعذر الاتصال يُقبل مخزن Hive
  /// كدليل على الصلاحية فقط إذا كان الاشتراك نشطاً وتاريخ انتهائه مستقبلياً
  /// والتحقق الأخير من السيرفر خلال 48 ساعة.
  static const Duration _subscriptionLease = Duration(hours: 48);

  bool _hiveLeaseValid() {
    final db = DatabaseService.instance;
    return isLeaseValid(
      isActive: db.getSubscriptionActive(),
      endDate: db.getSubscriptionEndDate(),
      lastVerified: db.getSubscriptionLastVerified(),
      leaseDuration: _subscriptionLease,
      now: DateTime.now(),
    );
  }

  /// ⭐ قاعدة الإيجار للاستخدام الخارجي (شاشة البداية عند انتهاء المهلة).
  bool isSubscriptionLeaseValid() => _hiveLeaseValid();

  Future<Map<String, dynamic>?> loadAndSaveSubscriptionInfo(
      String userId) async {
    final db = DatabaseService.instance;

    if (!_isFirebaseAvailable) {
      AppConfig.log('⚠️ Firebase not available, using Hive subscription');
      return _hiveSubscriptionMap();
    }

    try {
      AppConfig.log('📤 Loading subscription info for user');

      final best = await _fetchBestActiveSubscription(userId);
      if (best != null) {
        final info = await _persistAndBuildSubscription(best);
        AppConfig.log(
            '✅ Subscription active: ${info['plan_type'] ?? 'unknown plan'} '
            'ends at ${info['end_date']} (${info['days_remaining']} days)');
        return info;
      }

      // ⭐ حكم السيرفر: لا اشتراك نشط — لا نلتفت إلى Hive القديم
      await db.saveSubscriptionActive(false);
      await db.saveSubscriptionLastVerified(DateTime.now());
      AppConfig.log('⚠️ No active subscription found');
      return null;
    } catch (e) {
      AppConfig.logError('⚠️ Error loading subscription info', e);
      return _hiveSubscriptionMap();
    }
  }

  Future<void> signOut() async {
    try {
      if (_isFirebaseAvailable) {
        await FirebaseAuth.instance.signOut();
        AppConfig.log('✅ User signed out');
      } else {
        AppConfig.log('⚠️ Firebase not available, skipping sign out');
      }
    } catch (e) {
      AppConfig.logError('===== Firebase signOut error =====', e);
    }
  }

  User? get currentUser {
    try {
      if (!_isFirebaseAvailable) return null;
      return FirebaseAuth.instance.currentUser;
    } catch (e) {
      return null;
    }
  }

  // ⭐ L-2: أُزيلت isLoggedIn غير المستعملة (الفحص عبر AuthService.isLoggedIn)

  /// ⭐ H-3: تغيير كلمة المرور — إعادة مصادقة بالبريد الاصطناعي الحالي
  /// ثم التحديث. الأخطاء تُترجم لرسائل موحّدة بدون كشف تفاصيل.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (!_isFirebaseAvailable) {
      throw Exception(LocalizationHelper.authFirebaseUnavailable);
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }

    try {
      // ⭐ إعادة المصادقة مطلوبة قبل updatePassword في Firebase Auth
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
      AppConfig.log('✅ Password changed successfully');
    } on FirebaseAuthException catch (e) {
      // ⭐ الكود فقط في السجل — لا نص يتضمن البريد
      AppConfig.log('❌ changePassword FirebaseAuthException — Code: ${e.code}');
      String errorMessage;
      if (e.code == 'requires-recent-login' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'operation-not-allowed') {
        errorMessage = LocalizationHelper.authPasswordChangeError;
      } else if (e.code == 'weak-password') {
        errorMessage = LocalizationHelper.authPasswordTooWeak;
      } else if (e.code == 'network-request-failed') {
        errorMessage = LocalizationHelper.authNetworkFailed;
      } else {
        errorMessage = LocalizationHelper.authPasswordChangeError;
      }
      throw Exception(errorMessage);
    } catch (e) {
      AppConfig.log('❌ changePassword error: ${_authErrorLabel(e)}');
      throw Exception(LocalizationHelper.authPasswordChangeError);
    }
  }

  // ==================== طريقة مبسطة لجلب البيانات بدون فهارس ====================

  Future<List<Product>> getProductsSimple({DateTime? lastSync}) async {
    if (!_isFirebaseAvailable) {
      AppConfig.log('⚠️ Firebase not available, returning empty list');
      return [];
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      AppConfig.log('⚠️ getProducts: No user logged in');
      return [];
    }

try {
      AppConfig.log('📥 Fetching products for user $userId from Firestore...');

      // ⭐ استعلام مُرشَّح حسب user_id لتقليل عدد القراءات بشكل كبير.
      // عند وجود آخر توقيت مزامنة نسحب التغييرات الأحدث فقط (سحب تزايدي)
      // بدلاً من سحب القاعدة كاملة في كل مرة.
      final collection = FirebaseFirestore.instance
          .collection(FirebaseConfig.productsCollection)
          .where('user_id', isEqualTo: userId);

      // ⭐ سحب تزايدي: يحتاج فهرساً مركّباً (user_id + updated_at).
      // إن فشل بـ failed-precondition يعني غياب الفهرس — نُسجّل التحذير
      // ونتراجع إلى سحب كامل محدود. أي خطأ آخر (شبكة/صلاحيات)
      // لا يستحق التراجع بل يُعاد رميه.
      QuerySnapshot<Map<String, dynamic>> snapshot;
      if (lastSync != null) {
        try {
          snapshot = await NetworkService.readWithRetry(() => collection
                .where('updated_at', isGreaterThan: lastSync)
                .limit(500)
                .get(),
          );
        } on FirebaseException catch (e) {
          if (e.code == 'failed-precondition') {
            AppConfig.logError(
                '⚠️ MISSING INDEX for ${FirebaseConfig.productsCollection} '
                '(user_id + updated_at). Falling back to full pull. '
                'Deploy firestore.indexes.json immediately.', e);
            snapshot = await NetworkService.readWithRetry(() => collection
                  .limit(500)
                  .get(),
            );
          } else {
            rethrow;
          }
        }
      } else {
        snapshot = await NetworkService.readWithRetry(() => collection
              .limit(500)
              .get(),
        );
      }

      AppConfig.log('📊 Found ${snapshot.docs.length} products in Firestore');

      final products = <Product>[];
      for (var doc in snapshot.docs) {
        try {
          products.add(Product.fromFirestore(doc));
        } catch (e) {
          AppConfig.logError('  ⚠️ Failed to parse product ${doc.id}', e);
        }
      }

      // ⭐ ترتيب النتائج يدوياً
      products.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      AppConfig.log('✅ Fetched ${products.length} products for user $userId');
      return products;
    } catch (e) {
      AppConfig.logError('❌ Error getting products (simple method)', e);
      return [];
    }
  }

Future<List<Sale>> getSalesSimple({DateTime? lastSync}) async {
    if (!_isFirebaseAvailable) {
      AppConfig.log('⚠️ Firebase not available, returning empty list');
      return [];
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      AppConfig.log('⚠️ getSales: No user logged in');
      return [];
    }

    try {
      AppConfig.log('📥 Fetching sales for user $userId from Firestore...');

      // ⭐ استعلام مُرشَّح حسب user_id لتقليل عدد القراءات بشكل كبير.
      // عند وجود آخر توقيت مزامنة نسحب المبيعات الأحدث فقط (سحب تزايدي).
      final collection = FirebaseFirestore.instance
          .collection(FirebaseConfig.salesCollection)
          .where('user_id', isEqualTo: userId);

      // ⭐ سحب تزايدي: يحتاج فهرساً مركّباً (user_id + updated_at).
      // إن فشل بـ failed-precondition يعني غياب الفهرس — نُسجّل التحذير
      // ونتراجع إلى سحب كامل محدود. أي خطأ آخر (شبكة/صلاحيات)
      // لا يستحق التراجع بل يُعاد رميه.
      QuerySnapshot<Map<String, dynamic>> snapshot;
      if (lastSync != null) {
        try {
          snapshot = await NetworkService.readWithRetry(() => collection
                .where('updated_at', isGreaterThan: lastSync)
                .limit(500)
                .get(),
          );
        } on FirebaseException catch (e) {
          if (e.code == 'failed-precondition') {
            AppConfig.logError(
                '⚠️ MISSING INDEX for ${FirebaseConfig.salesCollection} '
                '(user_id + updated_at). Falling back to full pull. '
                'Deploy firestore.indexes.json immediately.', e);
            snapshot = await NetworkService.readWithRetry(() => collection
                  .limit(500)
                  .get(),
            );
          } else {
            rethrow;
          }
        }
      } else {
        snapshot = await NetworkService.readWithRetry(() => collection
              .limit(500)
              .get(),
        );
      }

      AppConfig.log('📊 Found ${snapshot.docs.length} sales in Firestore');

      if (snapshot.docs.isEmpty) {
        return [];
      }

      // ⭐ جلب كل بنود المبيعات دفعة واحدة (بدل طلب شبكة لكل مبيعة)
      final itemsBySale = await _getSaleItemsBatched(snapshot.docs);

      final sales = <Sale>[];
      for (var doc in snapshot.docs) {
        try {
          final sale = _saleFromDoc(doc, itemsBySale[doc.id] ?? []);
          if (sale != null) {
            sales.add(sale);
          }
        } catch (e) {
          AppConfig.logError('  ⚠️ Failed to parse sale ${doc.id}', e);
        }
      }

      // ⭐ ترتيب النتائج يدوياً
      sales.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      AppConfig.log('✅ Fetched ${sales.length} sales for user $userId');
      return sales;
    } catch (e) {
      AppConfig.logError('❌ Error getting sales (simple method)', e);
      return [];
    }
  }

/// ⭐ يجلب بنود المبيعات لعدد من الوثائق بطلبات مُجمّعة (whereIn بمجموعات من 10)
  /// بدلاً من طلب شبكة مستقل لكل مبيعة (إصلاح مشكلة N+1).
  Future<Map<String, List<SaleItem>>> _getSaleItemsBatched(
      List<QueryDocumentSnapshot> saleDocs) async {
    final result = <String, List<SaleItem>>{};
    const batchSize = 10;
    final saleIds = saleDocs.map((d) => d.id).toList();

    for (var i = 0; i < saleIds.length; i += batchSize) {
      final end = (i + batchSize < saleIds.length) ? i + batchSize : saleIds.length;
      final chunk = saleIds.sublist(i, end);
      try {
        final userId = FirebaseAuth.instance.currentUser?.uid;
        // ⭐ استعلام مُقيَّد بـ user_id ليطابق قواعد Firestore
        // (القراءة للمستندات المملوكة فقط)، وإلا يُرفض الاستعلام.
        var query = FirebaseFirestore.instance
            .collection(FirebaseConfig.saleItemsCollection)
            .where('sale_id', whereIn: chunk);
        if (userId != null) {
          query = query.where('user_id', isEqualTo: userId);
        }
        final itemsSnapshot = await query.get();
        for (final itemDoc in itemsSnapshot.docs) {
          final itemData = itemDoc.data() as Map<String, dynamic>;
          final saleId = itemData['sale_id'] as String? ?? '';
          final item = SaleItem(
            id: itemData['id'] ?? '',
            productId: itemData['product_id'] ?? '',
            productName: itemData['product_name'] ?? '',
            price: (itemData['price'] as num?)?.toDouble() ?? 0.0,
            quantity: itemData['quantity'] ?? 0,
            subtotal: (itemData['subtotal'] as num?)?.toDouble() ?? 0.0,
          );
          result.putIfAbsent(saleId, () => []).add(item);
        }
      } catch (e) {
        AppConfig.logError('⚠️ Failed to fetch items batch', e);
      }
    }
    return result;
  }

  /// ⭐ يحوّل وثيقة مبيعة إلى كائن Sale باستخدام بنود مجلوبة مسبقاً.
  Sale? _saleFromDoc(QueryDocumentSnapshot doc, List<SaleItem> items) {
    try {
      final data = doc.data() as Map<String, dynamic>;

      final returnedItems = (data['returned_items'] as List?)
          ?.map((item) => SaleItem.fromJson(item as Map<String, dynamic>))
          .toList();

      return Sale(
        id: doc.id,
        items: items,
        subtotal: (data['subtotal'] as num?)?.toDouble() ?? 0.0,
        discount: (data['discount'] as num?)?.toDouble() ?? 0.0,
        tax: (data['tax'] as num?)?.toDouble() ?? 0.0,
        total: (data['total'] as num?)?.toDouble() ?? 0.0,
        paymentMethod: data['payment_method'] ?? 'Cash',
        createdAt: data['created_at'] != null
            ? _parseTimestamp(data['created_at'])
            : null,
        isSynced: true,
        userId: data['user_id'] ?? '',
        customerName: data['customer_name'] as String?,
        customerPhone: data['customer_phone'] as String?,
        customerId: data['customer_id'] as String?,
        saleType: data['sale_type'] as String? ?? 'sale',
        originalSaleId: data['original_sale_id'] as String?,
        returnedItems: returnedItems,
        returnTotal: (data['return_total'] as num?)?.toDouble(),
        isFullyReturned: data['is_fully_returned'] as bool? ?? false,
      );
    } catch (e) {
      AppConfig.logError('Error converting sale', e);
      return null;
    }
  }

  // ==================== المنتجات ====================

  Future<List<Product>> getProducts({DateTime? lastSync}) async {
    // ⭐ استخدام الطريقة المبسطة لتجنب مشاكل الفهارس
    return await getProductsSimple(lastSync: lastSync);
  }

Future<void> addProduct({
    required String id,
    required String name,
    required String category,
    required double price,
    required int quantity,
    String? description,
    String? barcode,
    int minStockLevel = 10,
    DateTime? createdAt,
    double? costPrice,
  }) async {
    if (!_isFirebaseAvailable) {
      AppConfig.log('⚠️ Firebase not available, product saved locally only');
      return;
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      AppConfig.log('❌ addProduct: No user authenticated');
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }

    try {
      AppConfig.log('📤 Adding product to Firestore: $name');
      await NetworkService.writeWithRetry(() => FirebaseFirestore.instance
            .collection(FirebaseConfig.productsCollection)
            .doc(id)
            .set({
          'id': id,
          'user_id': userId,
          'name': name,
          'category': category,
          'price': price,
          'quantity': quantity,
          'description': description,
          'barcode': barcode,
          'min_stock_level': minStockLevel,
          'cost_price': costPrice,
          // ⭐ created_at ثابت من وقت الإنشاء (مستقر عند إعادة الرفع)،
          // وupdated_at هو Timestamp موحّد لدعم السحب التزايدي.
          'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
          'updated_at': FieldValue.serverTimestamp(),
        }),
      );
      AppConfig.log('✅ Product added to Firestore: $name');
    } catch (e) {
      AppConfig.logError('❌ Error adding product', e);
      rethrow;
    }
  }

  /// ⭐ Batch write multiple products in a single request (max 500 per batch)
  Future<void> addProductsBatch(List<Map<String, dynamic>> products) async {
    if (!_isFirebaseAvailable || products.isEmpty) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }

    try {
      AppConfig.log('📤 Batch writing ${products.length} products to Firestore...');
      const batchSize = 500;
      for (var i = 0; i < products.length; i += batchSize) {
        final end = (i + batchSize < products.length) ? i + batchSize : products.length;
        final chunk = products.sublist(i, end);
        
        final batch = FirebaseFirestore.instance.batch();
        for (final product in chunk) {
          final id = product['id'] as String;
          batch.set(
            FirebaseFirestore.instance
                .collection(FirebaseConfig.productsCollection)
                .doc(id),
            {
              'id': id,
              'user_id': userId,
              'name': product['name'],
              'category': product['category'],
              'price': product['price'],
              'quantity': product['quantity'],
              'description': product['description'],
              'barcode': product['barcode'],
              'min_stock_level': product['minStockLevel'] ?? 10,
              'cost_price': product['costPrice'],
              'created_at': product['createdAt']?.toIso8601String() ?? DateTime.now().toIso8601String(),
              'updated_at': FieldValue.serverTimestamp(),
            },
          );
        }
        await NetworkService.writeWithRetry(() => batch.commit());
      }
      AppConfig.log('✅ Batch write completed for ${products.length} products');
    } catch (e) {
      AppConfig.logError('❌ Error batch writing products', e);
      rethrow;
    }
  }

  Future<void> updateProduct({
    required String id,
    required String name,
    required String category,
    required double price,
    required int quantity,
    String? description,
    String? barcode,
    int? minStockLevel,
    double? costPrice,
  }) async {
    if (!_isFirebaseAvailable) {
      AppConfig.log('⚠️ Firebase not available, product updated locally only');
      return;
    }

    try {
      final Map<String, dynamic> data = {
        'name': name,
        'category': category,
        'price': price,
        'quantity': quantity,
        'description': description,
        'barcode': barcode,
        'cost_price': costPrice,
        'updated_at': FieldValue.serverTimestamp(),
      };
      if (minStockLevel != null) {
        data['min_stock_level'] = minStockLevel;
      }
      await NetworkService.writeWithRetry(() => FirebaseFirestore.instance
            .collection(FirebaseConfig.productsCollection)
            .doc(id)
            .update(data),
      );
      AppConfig.log('✅ Product updated in Firestore: $name');
    } catch (e) {
      AppConfig.logError('❌ Error updating product', e);
      rethrow;
    }
  }

  Future<void> deleteProduct(String id) async {
    if (!_isFirebaseAvailable) {
      AppConfig.log('⚠️ Firebase not available, product deleted locally only');
      return;
    }

    try {
      await NetworkService.writeWithRetry(() => FirebaseFirestore.instance
            .collection(FirebaseConfig.productsCollection)
            .doc(id)
            .delete(),
      );
      AppConfig.log('✅ Product deleted from Firestore: $id');
    } catch (e) {
      AppConfig.logError('❌ Error deleting product', e);
      rethrow;
    }
  }

  Future<bool> productExists(String id) async {
    if (!_isFirebaseAvailable) return false;

    try {
      final doc = await NetworkService.readWithRetry(() => FirebaseFirestore.instance
            .collection(FirebaseConfig.productsCollection)
            .doc(id)
            .get(),
      );
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  Future<Product?> getProductByBarcode(String barcode) async {
    if (!_isFirebaseAvailable) return null;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return null;

    try {
      final snapshot = await NetworkService.readWithRetry(() => FirebaseFirestore.instance
            .collection(FirebaseConfig.productsCollection)
            .where('user_id', isEqualTo: userId)
            .where('barcode', isEqualTo: barcode)
            .limit(1)
            .get(),
      );

      // ⭐ أمان: لا نبحث عن منتجات مستخدمين آخرين ولا نغير ملكية أي منتج
      return Product.fromFirestore(snapshot.docs.first);
    } catch (e) {
      return null;
    }
  }

  Future<Product?> getProductById(String id) async {
    if (!_isFirebaseAvailable) return null;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return null;

    try {
      final doc = await NetworkService.readWithRetry(() => FirebaseFirestore.instance
            .collection(FirebaseConfig.productsCollection)
            .doc(id)
            .get(),
      );

      if (!doc.exists) return null;

      // ⭐ أمان دفاعي: لا نُعيد منتجاً لا يملكه المستخدم الحالي
      // حتى لو سمحت القواعد بشكل غير صحيح.
      final data = doc.data() as Map<String, dynamic>?;
      if (data?['user_id'] != userId) return null;

      return Product.fromFirestore(doc);
    } catch (e) {
      return null;
    }
  }

Future<List<String>> getCategories() async {
    // First check local cache (Hive)
    final localCategories = DatabaseService.instance.getCategories();
    if (localCategories.isNotEmpty) {
      AppConfig.log('📦 Returning categories from Hive cache (${localCategories.length})');
      return localCategories;
    }

    if (!_isFirebaseAvailable) return [];

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return [];

    try {
      final snapshot = await NetworkService.readWithRetry(() => FirebaseFirestore.instance
            .collection(FirebaseConfig.productsCollection)
            .where('user_id', isEqualTo: userId)
            .get(),
      );

      final categories = snapshot.docs
          .map((doc) => doc.data()['category'] as String? ?? 'General')
          .toSet()
          .toList();
      categories.sort();
      
      // Update local cache
      DatabaseService.instance.setCategoriesCache(categories);
      
      AppConfig.log('✅ Fetched and cached ${categories.length} categories from Firestore');
      return categories;
    } catch (e) {
      AppConfig.logError('❌ Error getting categories', e);
      return [];
    }
  }

  // ==================== المبيعات ====================

  Future<List<Sale>> getSales({DateTime? lastSync}) async {
    // ⭐ استخدام الطريقة المبسطة لتجنب مشاكل الفهارس
    return await getSalesSimple(lastSync: lastSync);
  }

  // ⭐ دالة مساعدة لتحويل Timestamp إلى DateTime
  DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return DateTime.now();
      }
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.now();
  }

  // ⭐ تحليل تاريخ الاشتراك (يقبل Timestamp أو String ISO)،
  // ويعيد null عند غياب/فساد القيمة (يُعتبر الاشتراك غير صالح).
  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Future<bool> saleExists(String id) async {
    if (!_isFirebaseAvailable) return false;

    try {
      final doc = await NetworkService.readWithRetry(() => FirebaseFirestore.instance
            .collection(FirebaseConfig.salesCollection)
            .doc(id)
            .get(),
      );
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  Future<void> addSale({
    required String id,
    required List<SaleItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required String paymentMethod,
    String? customerName,
    String? customerPhone,
    String? customerId,
    String saleType = 'sale',
    String? originalSaleId,
    List<SaleItem>? returnedItems,
    double? returnTotal,
    bool isFullyReturned = false,
    DateTime? createdAt,
  }) async {
    if (!_isFirebaseAvailable) {
      AppConfig.log('⚠️ Firebase not available, sale saved locally only');
      return;
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      AppConfig.log('❌ addSale: No user authenticated');
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }

    try {
      AppConfig.log('📤 ===== ADDING SALE TO FIRESTORE =====');
      AppConfig.log('📤 Sale ID: $id');
      AppConfig.log('📤 User ID: $userId');
      AppConfig.log('📤 Items count: ${items.length}');
      AppConfig.log('📤 Total: $total');

      final batch = FirebaseFirestore.instance.batch();

      batch.set(
        FirebaseFirestore.instance
            .collection(FirebaseConfig.salesCollection)
            .doc(id),
        {
          'id': id,
          'user_id': userId,
          'subtotal': subtotal,
          'discount': discount,
          'tax': tax,
          'total': total,
          'payment_method': paymentMethod,
          'customer_name': customerName,
          'customer_phone': customerPhone,
          'customer_id': customerId,
          'sale_type': saleType,
          'original_sale_id': originalSaleId,
          'returned_items': returnedItems?.map((item) => item.toJson()).toList(),
          'return_total': returnTotal,
          'is_fully_returned': isFullyReturned,
          // ⭐ created_at ثابت من وقت الإنشاء (مستقر عند إعادة الرفع)،
          // وupdated_at هو Timestamp موحّد لدعم السحب التزايدي.
          'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
          'updated_at': FieldValue.serverTimestamp(),
        },
      );
      AppConfig.log('✅ Sale inserted successfully: $id');

      if (items.isNotEmpty) {
        AppConfig.log('📤 Adding ${items.length} sale items...');
        for (var item in items) {
          batch.set(
            FirebaseFirestore.instance
                .collection(FirebaseConfig.saleItemsCollection)
                .doc(item.id),
            {
              'id': item.id,
              'sale_id': id,
              // ⭐ user_id على كل بند لتسمح قواعد Firestore بالتحقق من الملكية
              // دون قراءات إضافية عبر get().
              'user_id': userId,
              'product_id': item.productId,
              'product_name': item.productName,
              'price': item.price,
              'quantity': item.quantity,
              'subtotal': item.subtotal,
              'created_at': FieldValue.serverTimestamp(),
            },
          );
        }
        AppConfig.log('✅ All sale items inserted successfully');
      }

      await NetworkService.writeWithRetry(() => batch.commit(),
      );
      AppConfig.log('✅ ===== SALE ADDED TO FIRESTORE SUCCESSFULLY =====');
    } catch (e) {
      AppConfig.logError('❌❌❌ ERROR ADDING SALE TO FIRESTORE', e);
      AppConfig.log('❌ Sale ID: $id');
      AppConfig.log('❌ Items: ${items.length}');
      rethrow;
    }
  }

  Future<void> updateSaleWithReturn({
    required String id,
    required List<SaleItem> returnedItems,
    required double returnTotal,
    required bool isFullyReturned,
  }) async {
    if (!_isFirebaseAvailable) {
      AppConfig.log('⚠️ Firebase not available, sale updated locally only');
      return;
    }

    try {
      AppConfig.log('📤 Updating sale with return: $id');

      // ⭐ دمج المرتجعات الموجودة مع الجديدة بدلاً من استبدالها (منع فقدان البيانات)
      final saleRef = FirebaseFirestore.instance
          .collection(FirebaseConfig.salesCollection)
          .doc(id);
      final existingDoc = await NetworkService.readWithRetry(() => saleRef.get(),
      );

      final Map<String, SaleItem> mergedReturned = {};
      if (existingDoc.exists) {
        final existing = existingDoc.data() as Map<String, dynamic>?;
        final existingItems = existing?['returned_items'] as List? ?? [];
        for (final item in existingItems) {
          final parsed = SaleItem.fromJson(item as Map<String, dynamic>);
          mergedReturned[parsed.productId] = parsed;
        }
      }
      for (final item in returnedItems) {
        final existing = mergedReturned[item.productId];
        if (existing == null) {
          mergedReturned[item.productId] = item;
        } else {
          mergedReturned[item.productId] = SaleItem(
            id: existing.id,
            productId: existing.productId,
            productName: existing.productName,
            price: existing.price,
            quantity: existing.quantity + item.quantity,
            subtotal: existing.subtotal + item.subtotal,
          );
        }
      }

      final mergedList = mergedReturned.values.map((e) => e.toJson()).toList();
      // ⭐ تراكم مبلغ الإرجاع النسبي (الممرَّر من الواجهة) بنفس طريقة Hive،
      // بدلاً من جمع subtotals الخام — وإلا يختلف المخزن المحلي عن السيرفر
      // لكل مبيعة عليها خصم.
      final existingReturnTotal =
          (existingDoc.exists ? (existingDoc.data()?['return_total'] as num?) : null)
                  ?.toDouble() ??
              0.0;

      await NetworkService.writeWithRetry(() => saleRef.update({
          'returned_items': mergedList,
          'return_total': existingReturnTotal + returnTotal,
          'is_fully_returned': isFullyReturned,
          // ⭐ Timestamp موحّد لدعم السحب التزايدي
          'updated_at': FieldValue.serverTimestamp(),
        }),
      );
AppConfig.log('✅ Sale updated with return in Firestore: $id');
    } catch (e) {
      AppConfig.logError('❌ Error updating sale with return', e);
      rethrow;
    }
  }

  /// ⭐ Batch write multiple sales with their items in a single request (max 500 per batch)
  Future<void> addSalesBatch(List<Map<String, dynamic>> sales) async {
    if (!_isFirebaseAvailable || sales.isEmpty) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }

    try {
      AppConfig.log('📤 Batch writing ${sales.length} sales to Firestore...');
      const batchSize = 500;
      for (var i = 0; i < sales.length; i += batchSize) {
        final end = (i + batchSize < sales.length) ? i + batchSize : sales.length;
        final chunk = sales.sublist(i, end);
        
        final batch = FirebaseFirestore.instance.batch();
        for (final sale in chunk) {
          final id = sale['id'] as String;
          final items = sale['items'] as List<Map<String, dynamic>>? ?? [];
          
          batch.set(
            FirebaseFirestore.instance
                .collection(FirebaseConfig.salesCollection)
                .doc(id),
            {
              'id': id,
              'user_id': userId,
              'subtotal': sale['subtotal'],
              'discount': sale['discount'],
              'tax': sale['tax'],
              'total': sale['total'],
              'payment_method': sale['paymentMethod'],
              'customer_name': sale['customerName'],
              'customer_phone': sale['customerPhone'],
              'customer_id': sale['customerId'],
              'sale_type': sale['saleType'] ?? 'sale',
              'original_sale_id': sale['originalSaleId'],
              'returned_items': sale['returnedItems'],
              'return_total': sale['returnTotal'],
              'is_fully_returned': sale['isFullyReturned'] ?? false,
              'created_at': sale['createdAt']?.toIso8601String() ?? DateTime.now().toIso8601String(),
              'updated_at': FieldValue.serverTimestamp(),
            },
          );

          for (var item in items) {
            batch.set(
              FirebaseFirestore.instance
                  .collection(FirebaseConfig.saleItemsCollection)
                  .doc(item['id'] as String),
              {
                'id': item['id'],
                'sale_id': id,
                'user_id': userId,
                'product_id': item['productId'],
                'product_name': item['productName'],
                'price': item['price'],
                'quantity': item['quantity'],
                'subtotal': item['subtotal'],
                'created_at': FieldValue.serverTimestamp(),
              },
            );
          }
        }
        await NetworkService.writeWithRetry(() => batch.commit());
      }
      AppConfig.log('✅ Batch write completed for ${sales.length} sales');
    } catch (e) {
      AppConfig.logError('❌ Error batch writing sales', e);
      rethrow;
    }
  }

  // ==================== حركات المخزون ====================

  Future<void> addMovement({
    required String id,
    required String productId,
    required String productName,
    required MovementType type,
    required int quantity,
    required double price,
    required double total,
    String? referenceId,
    String? referenceNumber,
    String? note,
    required String userId,
    MovementStatus status = MovementStatus.completed,
    String? customerName,
    String? supplierName,
    DateTime? createdAt,
  }) async {
    if (!_isFirebaseAvailable) {
      AppConfig.log('⚠️ Firebase not available, movement saved locally only');
      return;
    }

    try {
      await NetworkService.writeWithRetry(() => FirebaseFirestore.instance
            .collection(FirebaseConfig.inventoryMovementsCollection)
            .doc(id)
            .set({
          'id': id,
          'user_id': userId,
          'product_id': productId,
          'product_name': productName,
          'type': type.name,
          'quantity': quantity,
          'price': price,
          'total': total,
          'reference_id': referenceId,
          'reference_number': referenceNumber,
          'note': note,
          'status': status.name,
          'customer_name': customerName,
          'supplier_name': supplierName,
          'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
          // ⭐ Timestamp موحّد لدعم السحب التزايدي
          'updated_at': FieldValue.serverTimestamp(),
        }),
      );
} catch (e) {
      AppConfig.logError('❌ Error adding movement', e);
      rethrow;
    }
  }

  /// ⭐ Batch write multiple movements in a single request (max 500 per batch)
  Future<void> addMovementsBatch(List<Map<String, dynamic>> movements) async {
    if (!_isFirebaseAvailable || movements.isEmpty) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }

    try {
      AppConfig.log('📤 Batch writing ${movements.length} movements to Firestore...');
      const batchSize = 500;
      for (var i = 0; i < movements.length; i += batchSize) {
        final end = (i + batchSize < movements.length) ? i + batchSize : movements.length;
        final chunk = movements.sublist(i, end);
        
        final batch = FirebaseFirestore.instance.batch();
        for (final movement in chunk) {
          final id = movement['id'] as String;
          batch.set(
            FirebaseFirestore.instance
                .collection(FirebaseConfig.inventoryMovementsCollection)
                .doc(id),
            {
              'id': id,
              'user_id': userId,
              'product_id': movement['productId'],
              'product_name': movement['productName'],
              'type': movement['type'],
              'quantity': movement['quantity'],
              'price': movement['price'],
              'total': movement['total'],
              'reference_id': movement['referenceId'],
              'reference_number': movement['referenceNumber'],
              'note': movement['note'],
              'status': movement['status'] ?? 'completed',
              'customer_name': movement['customerName'],
              'supplier_name': movement['supplierName'],
              'created_at': movement['createdAt']?.toIso8601String() ?? DateTime.now().toIso8601String(),
              'updated_at': FieldValue.serverTimestamp(),
            },
          );
        }
        await NetworkService.writeWithRetry(() => batch.commit());
      }
      AppConfig.log('✅ Batch write completed for ${movements.length} movements');
    } catch (e) {
      AppConfig.logError('❌ Error batch writing movements', e);
      rethrow;
    }
  }

Future<List<InventoryMovement>> getMovements({DateTime? lastSync}) async {
    if (!_isFirebaseAvailable) return [];

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return [];

    try {
      // ⭐ سحب تزايدي بنفس أسلوب المنتجات/المبيعات.
      final collection = FirebaseFirestore.instance
          .collection(FirebaseConfig.inventoryMovementsCollection)
          .where('user_id', isEqualTo: userId);

      // ⭐ سحب تزايدي: يحتاج فهرساً مركّباً (user_id + updated_at).
      // إن فشل بـ failed-precondition يعني غياب الفهرس — نُسجّل التحذير
      // ونتراجع إلى سحب كامل محدود. أي خطأ آخر (شبكة/صلاحيات)
      // لا يستحق التراجع بل يُعاد رميه.
      QuerySnapshot<Map<String, dynamic>> snapshot;
      if (lastSync != null) {
        try {
          snapshot = await NetworkService.readWithRetry(() => collection
                .where('updated_at', isGreaterThan: lastSync)
                .limit(500)
                .get(),
          );
        } on FirebaseException catch (e) {
          if (e.code == 'failed-precondition') {
            AppConfig.logError(
                '⚠️ MISSING INDEX for ${FirebaseConfig.inventoryMovementsCollection} '
                '(user_id + updated_at). Falling back to full pull. '
                'Deploy firestore.indexes.json immediately.', e);
            snapshot = await NetworkService.readWithRetry(() => collection
                  .limit(500)
                  .get(),
            );
          } else {
            rethrow;
          }
        }
      } else {
        snapshot = await NetworkService.readWithRetry(() => collection
              .limit(500)
              .get(),
        );
      }

      final movements = <InventoryMovement>[];
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        movements.add(InventoryMovement(
          id: doc.id,
          productId: data['product_id'] as String? ?? '',
          productName: data['product_name'] as String? ?? '',
          type: _parseMovementType(data['type'] as String?),
          quantity: data['quantity'] as int? ?? 0,
          price: (data['price'] as num?)?.toDouble() ?? 0.0,
          total: (data['total'] as num?)?.toDouble() ?? 0.0,
          referenceId: data['reference_id'] as String?,
          referenceNumber: data['reference_number'] as String?,
          note: data['note'] as String?,
          createdAt: _parseTimestamp(data['created_at']),
          userId: data['user_id'] as String? ?? '',
          status: _parseMovementStatus(data['status'] as String?),
          isSynced: true,
          customerName: data['customer_name'] as String?,
          supplierName: data['supplier_name'] as String?,
        ));
      }
      return movements;
    } catch (e) {
      AppConfig.logError('❌ Error getting movements', e);
      return [];
    }
  }

  MovementType _parseMovementType(String? value) {
    for (final type in MovementType.values) {
      if (type.name == value) return type;
    }
    return MovementType.adjustment;
  }

  MovementStatus _parseMovementStatus(String? value) {
    for (final status in MovementStatus.values) {
      if (status.name == value) return status;
    }
    return MovementStatus.completed;
  }

  Future<void> deleteSale(String id) async {
    if (!_isFirebaseAvailable) {
      AppConfig.log('⚠️ Firebase not available, sale deleted locally only');
      return;
    }

    // ⭐ H-5: الاستعلام يجب أن يكون مقيَّداً بـ user_id ليطابق قواعد
    // Firestore (القراءة للمستندات المملوكة فقط)، وإلا يُرفض كله.
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }

    try {
      // ⭐ حذف عناصر المبيعة المرتبطة أولاً (عملية واحدة batch بدل حلقة)
      final itemsSnapshot = await NetworkService.readWithRetry(() => FirebaseFirestore.instance
            .collection(FirebaseConfig.saleItemsCollection)
            .where('sale_id', isEqualTo: id)
            .where('user_id', isEqualTo: userId)
            .get(),
      );
      if (itemsSnapshot.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in itemsSnapshot.docs) {
          batch.delete(doc.reference);
        }
        await NetworkService.writeWithRetry(() => batch.commit(),
        );
      }
      await NetworkService.writeWithRetry(() => FirebaseFirestore.instance
            .collection(FirebaseConfig.salesCollection)
            .doc(id)
            .delete(),
      );
      AppConfig.log('✅ Sale deleted from Firestore: $id');
    } catch (e) {
      AppConfig.logError('❌ Error deleting sale', e);
      rethrow;
    }
  }

  // ==================== Suppliers ====================

  Future<void> addSupplier({
    required String id,
    required String name,
    String? phone,
    String? address,
    String? notes,
    required DateTime createdAt,
  }) async {
    final uid = currentUser?.uid;
    if (uid == null) {
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }
    await _db
        .collection(FirebaseConfig.suppliersCollection)
        .doc(id)
        .set({
      'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'notes': notes,
      'user_id': uid,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? address,
    String? notes,
  }) async {
    await _db
        .collection(FirebaseConfig.suppliersCollection)
        .doc(id)
        .update({
      'name': name,
      'phone': phone,
      'address': address,
      'notes': notes,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteSupplier(String id) async {
    await _db.collection(FirebaseConfig.suppliersCollection).doc(id).delete();
  }

  Future<void> addSuppliersBatch(List<Map<String, dynamic>> suppliers) async {
    final uid = currentUser?.uid;
    if (uid == null) {
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }
    WriteBatch batch = _db.batch();
    int ops = 0;
    for (final s in suppliers) {
      final doc = _db.collection(FirebaseConfig.suppliersCollection).doc(s['id'] as String);
      batch.set(doc, {
        ...s,
        'user_id': uid,
        'created_at': Timestamp.fromDate(DateTime.parse(s['created_at'] as String)),
        'updated_at': Timestamp.fromDate(DateTime.parse(s['updated_at'] as String)),
      });
      ops++;
      if (ops % 450 == 0) {
        await batch.commit();
        batch = _db.batch();
      }
    }
    if (ops % 450 != 0 || ops == 0) await batch.commit();
  }

  Future<List<Supplier>> getSuppliers({DateTime? lastSync}) async {
    final uid = currentUser?.uid;
    if (uid == null) {
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }
    Query query = _db
        .collection(FirebaseConfig.suppliersCollection)
        .where('user_id', isEqualTo: uid);
    if (lastSync != null) {
      try {
        query = query.where('updated_at', isGreaterThan: Timestamp.fromDate(lastSync));
      } on FirebaseException catch (e) {
        if (e.code == 'failed-precondition') {
          AppConfig.logError(
              '⚠️ MISSING INDEX for ${FirebaseConfig.suppliersCollection} '
              '(user_id + updated_at). Falling back to full pull. '
              'Deploy firestore.indexes.json immediately.', e);
        } else {
          rethrow;
        }
      }
    }
    query = query.limit(500);
    final snap = await query.get();
    return snap.docs.map((d) => Supplier.fromFirestore(d)).toList();
  }

  // ==================== Customers ====================

  Future<void> addCustomer({
    required String id,
    required String name,
    String? phone,
    String? address,
    String? notes,
    required DateTime createdAt,
  }) async {
    final uid = currentUser?.uid;
    if (uid == null) {
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }
    await _db
        .collection(FirebaseConfig.customersCollection)
        .doc(id)
        .set({
      'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'notes': notes,
      'user_id': uid,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateCustomer({
    required String id,
    required String name,
    String? phone,
    String? address,
    String? notes,
  }) async {
    await _db
        .collection(FirebaseConfig.customersCollection)
        .doc(id)
        .update({
      'name': name,
      'phone': phone,
      'address': address,
      'notes': notes,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteCustomer(String id) async {
    await _db.collection(FirebaseConfig.customersCollection).doc(id).delete();
  }

  Future<void> addCustomersBatch(List<Map<String, dynamic>> customers) async {
    final uid = currentUser?.uid;
    if (uid == null) {
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }
    WriteBatch batch = _db.batch();
    int ops = 0;
    for (final c in customers) {
      final doc = _db.collection(FirebaseConfig.customersCollection).doc(c['id'] as String);
      batch.set(doc, {
        ...c,
        'user_id': uid,
      });
      ops++;
      if (ops % 450 == 0) {
        await batch.commit();
        batch = _db.batch();
      }
    }
    if (ops % 450 != 0 || ops == 0) await batch.commit();
  }

  Future<List<Customer>> getCustomers({DateTime? lastSync}) async {
    final uid = currentUser?.uid;
    if (uid == null) {
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }
    final collection = _db
        .collection(FirebaseConfig.customersCollection)
        .where('user_id', isEqualTo: uid);
    QuerySnapshot<Map<String, dynamic>> snapshot;
    if (lastSync != null) {
      try {
        snapshot = await NetworkService.readWithRetry(() => collection
            .where('updated_at', isGreaterThan: lastSync)
            .limit(500)
            .get());
      } on FirebaseException catch (e) {
        if (e.code == 'failed-precondition') {
          AppConfig.logError(
              '⚠️ MISSING INDEX for ${FirebaseConfig.customersCollection} '
              '(user_id + updated_at). Falling back to full pull. '
              'Deploy firestore.indexes.json immediately.', e);
          snapshot = await NetworkService.readWithRetry(() => collection.limit(500).get());
        } else {
          rethrow;
        }
      }
    } else {
      snapshot = await NetworkService.readWithRetry(() => collection.limit(500).get());
    }
    return snapshot.docs
        .map((doc) => Customer.fromFirestore(doc))
        .toList();
  }

  // ==================== Debt Transactions ====================

  Future<void> addDebtTransaction({
    required String id,
    required String customerId,
    required String type,
    required double amount,
    String? saleId,
    String? note,
    required DateTime createdAt,
  }) async {
    final uid = currentUser?.uid;
    if (uid == null) {
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }
    await _db
        .collection(FirebaseConfig.debtTransactionsCollection)
        .doc(id)
        .set({
      'id': id,
      'customer_id': customerId,
      'type': type,
      'amount': amount,
      'sale_id': saleId,
      'note': note,
      'user_id': uid,
      'created_at': createdAt.toIso8601String(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteDebtTransaction(String id) async {
    await _db.collection(FirebaseConfig.debtTransactionsCollection).doc(id).delete();
  }

  Future<void> addDebtTransactionsBatch(List<Map<String, dynamic>> txns) async {
    final uid = currentUser?.uid;
    if (uid == null) {
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }
    WriteBatch batch = _db.batch();
    int ops = 0;
    for (final t in txns) {
      final doc = _db.collection(FirebaseConfig.debtTransactionsCollection).doc(t['id'] as String);
      batch.set(doc, {
        ...t,
        'user_id': uid,
      });
      ops++;
      if (ops % 450 == 0) {
        await batch.commit();
        batch = _db.batch();
      }
    }
    if (ops % 450 != 0 || ops == 0) await batch.commit();
  }

  Future<List<DebtTransaction>> getDebtTransactions({DateTime? lastSync}) async {
    final uid = currentUser?.uid;
    if (uid == null) {
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }
    final collection = _db
        .collection(FirebaseConfig.debtTransactionsCollection)
        .where('user_id', isEqualTo: uid);
    QuerySnapshot<Map<String, dynamic>> snapshot;
    if (lastSync != null) {
      try {
        snapshot = await NetworkService.readWithRetry(() => collection
            .where('updated_at', isGreaterThan: lastSync)
            .limit(500)
            .get());
      } on FirebaseException catch (e) {
        if (e.code == 'failed-precondition') {
          AppConfig.logError(
              '⚠️ MISSING INDEX for ${FirebaseConfig.debtTransactionsCollection} '
              '(user_id + updated_at). Falling back to full pull. '
              'Deploy firestore.indexes.json immediately.', e);
          snapshot = await NetworkService.readWithRetry(() => collection.limit(500).get());
        } else {
          rethrow;
        }
      }
    } else {
      snapshot = await NetworkService.readWithRetry(() => collection.limit(500).get());
    }
    return snapshot.docs
        .map((doc) => DebtTransaction.fromFirestore(doc))
        .toList();
  }

  // ==================== Purchases ====================

  // الأصناف تُخزَّن مصفوفة داخل وثيقة الشراء (لا مجموعة فرعية)
  Future<void> addPurchase({required Purchase purchase}) async {
    final uid = currentUser?.uid;
    if (uid == null) {
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }
    await _db
        .collection(FirebaseConfig.purchasesCollection)
        .doc(purchase.id)
        .set({
      ...purchase.toJson(),
      'user_id': uid,
      'created_at': Timestamp.fromDate(purchase.createdAt),
      'updated_at': Timestamp.fromDate(purchase.updatedAt),
    });
  }

  Future<void> addPurchasesBatch(List<Map<String, dynamic>> purchases) async {
    final uid = currentUser?.uid;
    if (uid == null) {
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }
    WriteBatch batch = _db.batch();
    int ops = 0;
    for (final p in purchases) {
      final doc = _db.collection(FirebaseConfig.purchasesCollection).doc(p['id'] as String);
      batch.set(doc, {
        ...p,
        'user_id': uid,
        'created_at': Timestamp.fromDate(DateTime.parse(p['created_at'] as String)),
        'updated_at': Timestamp.fromDate(DateTime.parse(p['updated_at'] as String)),
      });
      ops++;
      if (ops % 450 == 0) {
        await batch.commit();
        batch = _db.batch();
      }
    }
    if (ops % 450 != 0 || ops == 0) await batch.commit();
  }

  // ⭐ تحديث الشراء بالمرتجع داخل نفس الوثيقة (نمط updateSaleWithReturn)
  Future<void> updatePurchaseWithReturn({
    required String id,
    required List<PurchaseItem> returnedItems,
    required double returnTotal,
    required bool isFullyReturned,
  }) async {
    await _db
        .collection(FirebaseConfig.purchasesCollection)
        .doc(id)
        .update({
      'returned_items': returnedItems.map((e) => e.toJson()).toList(),
      'return_total': returnTotal,
      'is_fully_returned': isFullyReturned,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Purchase>> getPurchases({DateTime? lastSync}) async {
    final uid = currentUser?.uid;
    if (uid == null) {
      throw Exception(LocalizationHelper.authUserNotAuthenticated);
    }
    Query query = _db
        .collection(FirebaseConfig.purchasesCollection)
        .where('user_id', isEqualTo: uid);
    if (lastSync != null) {
      try {
        query = query.where('updated_at', isGreaterThan: Timestamp.fromDate(lastSync));
      } on FirebaseException catch (e) {
        if (e.code == 'failed-precondition') {
          AppConfig.logError(
              '⚠️ MISSING INDEX for ${FirebaseConfig.purchasesCollection} '
              '(user_id + updated_at). Falling back to full pull. '
              'Deploy firestore.indexes.json immediately.', e);
        } else {
          rethrow;
        }
      }
    }
    query = query.limit(500);
    final snap = await query.get();
    return snap.docs.map((d) => Purchase.fromFirestore(d)).toList();
  }

  Future<void> deletePurchase(String id) async {
    await _db.collection(FirebaseConfig.purchasesCollection).doc(id).delete();
  }

  // ==================== الاشتراكات ====================

  /// ⭐ C-2: بوابة الدفع "الخادم أولاً" — لا يُقبل مخزن Hive كدليل على
  /// الصلاحية إلا ضمن "إيجار" 48 ساعة بعد آخر تحقق ناجح من السيرفر.
  /// عند نجاح الاتصال: حكم السيرفر هو النهائي ويُحدَّث end_date/active/
  /// lastVerified. عند الفشل/انقطاع الاتصال: يُقبل Hive فقط إذا كان
  /// الإيجار صالحاً (نشط + end_date مستقبلي + تحقق خلال 48 ساعة).
  Future<bool> isSubscriptionActive() async {
    final db = DatabaseService.instance;

    if (!_isFirebaseAvailable) {
      AppConfig.log('⚠️ Firebase not available, applying Hive lease rule');
      return _hiveLeaseValid();
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      AppConfig.log('⚠️ No user logged in');
      return false;
    }

    try {
      AppConfig.log('📤 Checking subscription in Firestore (server-first)');

      final best = await _fetchBestActiveSubscription(userId);
      if (best != null) {
        final info = await _persistAndBuildSubscription(best);
        AppConfig.log(
            '✅ Subscription active in Firestore: ends at ${info['end_date']}');
        return true;
      }

      // ⭐ حكم السيرفر: لا اشتراك نشط — يُقفل الوصول فوراً
      AppConfig.log('⚠️ No active subscription found in Firestore');
      await db.saveSubscriptionActive(false);
      await db.saveSubscriptionLastVerified(DateTime.now());
      return false;
    } catch (e) {
      AppConfig.logError('⚠️ Subscription check online error', e);
      // ⭐ تعذر الوصول للسيرفر: إيجار 48 ساعة فقط، لا ثقة مطلقة بـ Hive
      final leaseOk = _hiveLeaseValid();
      AppConfig.log(leaseOk
          ? '⚠️ Offline: Hive subscription within 48h lease — allowing'
          : '🚫 Offline: no valid lease — denying access');
      return leaseOk;
    }
  }

  // ⭐ L-2: أُزيلت validateSession غير المستعملة (الفحص عبر AuthService.validateSession)

  /// ⭐ M-9: يفوّض الجلب إلى _fetchBestActiveSubscription (استعلام واحد).
  Future<Map<String, dynamic>?> getSubscriptionInfo() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      AppConfig.log('⚠️ No user logged in');
      return null;
    }

    if (!_isFirebaseAvailable) {
      AppConfig.log('⚠️ Firebase not available, using Hive subscription');
      return _hiveSubscriptionMap();
    }

    try {
      AppConfig.log('📤 Fetching subscription info');

      final best = await _fetchBestActiveSubscription(userId);
      if (best != null) {
        final info = await _persistAndBuildSubscription(best);
        AppConfig.log(
            '✅ Subscription found: ${info['plan_type'] ?? 'unknown plan'} '
            'until ${info['end_date']} (${info['days_remaining']} days remaining)');
        return info;
      }

      // ⭐ حكم السيرفر: لا اشتراك نشط — لا نلتفت إلى Hive القديم
      AppConfig.log('⚠️ No subscription found in Firestore');
      final db = DatabaseService.instance;
      await db.saveSubscriptionActive(false);
      await db.saveSubscriptionLastVerified(DateTime.now());
      return null;
    } catch (e) {
      AppConfig.logError('❌ Error getting subscription info', e);
      return _hiveSubscriptionMap();
    }
  }
}


