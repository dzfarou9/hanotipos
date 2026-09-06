# خطة إصلاح مشاكل مشروع hanoti POS

> **للوكلاء المنفذين:** مطلوب مهارة فرعية: استخدام superpowers:subagent-driven-development (موصى به) أو superpowers:executing-plans لتنفيذ هذه الخطة مهمةً بمهمة. الخطوات تستخدم صيغة checkbox (`- [ ]`) للتتبع.

**الهدف:** إصلاح جميع المشاكل المرصودة في مراجعة المشروع عدا التحقق من رقم الهاتف (OTP): النظافة، CI، معالجة الأخطاء، منطق الجلسة، تدفق الدخول، وتفكيك pos_screen.

**المعمارية:** تطبيق Flutter Offline-First (Hive + Firebase). الإصلاحات تحافظ على السلوك الظاهر للمستخدم: رسائل الأخطاء المترجمة تصل للشاشات كـ `Exception` بنفس الصيغة الحالية (`e.toString().startsWith('Exception: ')`)، وشاشة الدخول لا تنتظر نجاح المزامنة.

**التقنيات:** Flutter SDK >=3.1.0 <4.0.0، flutter_lints ^6.0.0، Hive، Firebase Auth/Firestore، easy_localization. بيئة التنفيذ: Windows PowerShell — الأوامر من جذر المستودع.

**المواصفات:** مراجعة الجلسة الحالية ("رأيي الصريح في المشروع") — قائمة المشاكل 1-8 ما عدا #5.

## Global Constraints

- **مستثنى صراحة بطلب المستخدم:** أي عمل على التحقق من رقم الهاتف عبر OTP (المشكلة #5).
- **خارج النطاق:** تفكيك dashboard_screen و sales_history_screen؛ Cloud Functions الخلفية (غير موجودة في هذا المستودع)؛ تغيير رسائل/مفاتيح الترجمة.
- **لا إضافات dependencies جديدة** في pubspec.yaml.
- **عقد الرسائل المحفوظ:** شاشة الدخول/التسجيل تعرض `e.toString()` بعد تجريد البادئة `'Exception: '`، وتتحقق من الشبكة عبر `message.contains(LocalizationHelper.authNetworkFailed)` لأجل rate limiter. أي استثناء يُرمى من AuthService يجب أن يحمل رسالة مترجمة من LocalizationHelper داخل Exception عادي.
- **سلوك محفوظ:** فشل المزامنة بعد الدخول لا يمنع الدخول (Offline First).
- أسلوب رسائل الالتزام يتبع المستودع: `Fix: ...` / `Refactor: ...` / `Add: ...`.
- بعد كل مهمة: `flutter analyze` نظيف و`flutter test` أخضر قبل الالتزام.
- التعليقات بالعربية بأسلوب المشروع الحالي.

---

### Task 1: نظافة المستودع — حذف الأرشيف وإعادة كتابة README

**Files:**
- Delete: `hanotipos-master.zip` (متتبَّع في git)
- Modify: `.gitignore`
- Modify: `README.md`

**السياق:** `git ls-files` يُظهر `hanotipos-master.zip` متتبعاً. أما `android/local.properties` فهو موجود في .gitignore أصلاً (السطران 60-61) وغير متتبَّع — لا حاجة لتغييره، فقط تأكيد.

- [ ] **Step 1: إزالة الأرشيف من التتبع والقرص**

```powershell
git rm --cached hanotipos-master.zip
Remove-Item -LiteralPath hanotipos-master.zip
```

- [ ] **Step 2: منع تكرار الخطأ في .gitignore**

أضف في نهاية قسم "# Local configuration":

```gitignore
# أرشيفات المشروع المضغوطة
*.zip
```

- [ ] **Step 3: إعادة كتابة README.md بالكامل**

```markdown
# hanoti — نظام نقاط البيع | POS System

تطبيق نقاط بيع للمتاجر الصغيرة، يعمل Offline-First: البيانات تُقرأ وتُكتب محلياً عبر Hive وتتزامن تلقائياً مع Firebase عند توفر الاتصال.

## المزايا

- شاشة بيع (POS) مع سلة، مسح باركود، وخصومات
- إدارة مخزون كاملة مع حركات المخزون وتنبيهات نقص الكمية
- سجل مبيعات مع مرتجعات جزئية/كلية وفواتير PDF قابلة للطباعة والمشاركة
- لوحة تحكم بإحصائيات المتجر
- نظام اشتراكات (تجريبي ومدفوع) مع مزامنة آمنة عبر قواعد Firestore
- ثلاث لغات: العربية، الفرنسية، الإنجليزية (دعم RTL كامل بخط Tajawal)

## التقنيات

Flutter · Firebase (Auth / Firestore / Storage / App Check) · Hive · easy_localization

## التشغيل

```bash
flutter pub get
flutter run
```

المتطلبات: Flutter SDK >= 3.1.0 ومشروع Firebase مهيأ (Email/Password Auth + Firestore).
ملف `lib/firebase_options.dart` مضمّن؛ لإعادة التوليد لمشروع جديد استخدم `flutterfire configure`.

## الاختبارات والتحليل

```bash
flutter test
flutter analyze
```

CI ينفذ الأمرين أعلاه تلقائياً على كل push وpull request (`.github/workflows/ci.yml`).

## قواعد أمان Firestore

القواعد في `firestore.rules` والفهارس في `firestore.indexes.json`. نشرها:

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

## بنية lib/

| المسار | المسؤولية |
|--------|-----------|
| `config/` | إعدادات التطبيق وFirebase |
| `models/` | نماذج البيانات (Hive adapters مولدة بـ build_runner) |
| `screens/` | شاشات التطبيق |
| `services/` | المصادقة، المزامنة، الطباعة، الكاش |
| `widgets/` | مكوّنات الواجهة القابلة لإعادة الاستخدام |
| `helpers/` | أدوات مساعدة نقية قابلة للاختبار |
| `theme/` | الثيم والألوان وأنماط النصوص |

> ملاحظة: اشتراكات المدفوعات تُدار خلفياً عبر Cloud Functions خارج هذا المستودع؛ العميل يقرأ فقط (قواعد Firestore تمنع الكتابة).
```

- [ ] **Step 4: التحقق**

Run: `flutter analyze`
Expected: No issues found (أو نفس عدد المشاكل السابقة — لا جديد)

- [ ] **Step 5: Commit**

```powershell
git add -A
git commit -m "Chore: remove bundled archive, rewrite README, ignore zips"
```

---

### Task 2: سير عمل CI

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: إنشاء الملف**

```yaml
name: CI

on:
  push:
    branches: [master, main]
  pull_request:

jobs:
  analyze-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Install dependencies
        run: flutter pub get

      - name: Analyze
        run: flutter analyze

      - name: Run tests
        run: flutter test
```

- [ ] **Step 2: التحقق محلياً أن الأمرين يمران كما سيصلهما CI**

Run: `flutter analyze; if ($?) { flutter test }`
Expected: تحليل نظيف + All tests passed!

- [ ] **Step 3: Commit**

```powershell
git add .github/workflows/ci.yml
git commit -m "Add: GitHub Actions CI (analyze + test)"
```

---

### Task 3: إزالة معالجة الأخطاء الميتة بالسلاسل النصية في AuthService

**Files:**
- Modify: `lib/services/auth_service.dart` (login ~145-169، register ~383-407)

**السياق الحرج:** `FirebaseService.signInWithPhoneAndPassword` و`signUpWithPhoneAndPassword` يمسكَان `FirebaseAuthException` داخلياً ويترجمان `e.code` عبر LocalizationHelper ثم يرميان `Exception(رسالة مترجمة)`. لذلك فحوصات `e.toString().contains('user-not-found')` في AuthService **كود ميت** لن يطابق أبداً لأن الرسالة وصلت مترجمةً بالفعل (عربية/فرنسية/إنجليزية). الحل: تسجيل الخطأ وإعادة رميه كما هو.

- [ ] **Step 1: تبسيط catch تسجيل الدخول**

استبدل الكتلة من `UserCredential? credential;` حتى نهاية catch الداخلية (قبل سطر `AppConfig.log('Login response...')`) بـ:

```dart
      // FirebaseService يترجم أكواد FirebaseAuthException إلى رسائل مترجمة
      // ويرميها داخل Exception — نعيد رفعها كما هي للشاشة.
      final credential = await firebaseService.signInWithPhoneAndPassword(
        phone: phone,
        password: password,
      );
```

- [ ] **Step 2: تبسيط catch التسجيل (register)**

استبدل كتلة try/catch حول `signUpWithPhoneAndPassword` بما يناسبها:

```dart
      // FirebaseService يترجم أكواد FirebaseAuthException إلى رسائل مترجمة
      // ويرميها داخل Exception — نعيد رفعها كما هي للشاشة.
      final credential = await firebaseService.signUpWithPhoneAndPassword(
        phone: phone,
        fullName: fullName,
        storeName: storeName,
        password: password,
      );
```

مهم: في `register()` الـ outer catch الحالي يعيد `return false` — غيّره إلى `rethrow` حتى تصل الرسالة المترجمة المحددة إلى `register_screen.dart` الذي يعالجها فعلاً (يفكّ بادئة `Exception: ` ويعرض الرسالة). أضف قبل rethrow:

```dart
    } catch (e) {
      AppConfig.logError('❌❌❌ Registration error', e);
      rethrow;
    }
```

- [ ] **Step 3: التحقق أن الشاشتان تعتمدان على العقد ذاته**

افحص `lib/screens/login_screen.dart:154-168` و`lib/screens/register_screen.dart:245+`: كلاهما يجرد `'Exception: '` ويعرض الرسالة — العقد محفوظ تلقائياً لأننا لم نغيّر ما يرميه FirebaseService.

- [ ] **Step 4: التحقق**

Run: `flutter analyze`
Expected: No issues

Run: `flutter test`
Expected: All tests passed!

- [ ] **Step 5: Commit**

```powershell
git add lib/services/auth_service.dart
git commit -m "Fix: drop dead string-based auth error mapping, rethrow translated messages"
```

---

### Task 4: إصلاح منطق isLoggedIn وvalidateSession

**Files:**
- Modify: `lib/services/auth_service.dart` (isLoggedIn 34-51، validateSession 495-526)

**السياق:** `FirebaseService.currentUser` لا يرمي استثناءً أبداً (يمسك داخلياً ويعيد null — راجع firebase_service.dart:500-507)، لذا فرعا `catch → return true` غير قابلَين للوصول وهما خطيران كتوثيق مضلل. السلوك الفعلي اليوم: Hive userId موجود + Firebase user مطابق = مسجل دخول. نُبقي السلوك ونحذف التضليل. (شاشة splash تستدعي validateSession بعد isLoggedIn — السلوك الخارجي كما هو.)

- [ ] **Step 1: استبدل isLoggedIn بالكامل**

```dart
  bool get isLoggedIn {
    try {
      final userId = DatabaseService.instance.getUserId();
      if (userId == null) return false;

      // currentUser لا يرمي استثناءً أبداً (يعيد null عند تعذر الوصول لـ Firebase)
      final user = FirebaseService().currentUser;
      return user != null && user.uid == userId;
    } catch (e) {
      AppConfig.logError('Error checking login status', e);
      return false;
    }
  }
```

- [ ] **Step 2: استبدل validateSession بالكامل**

```dart
  Future<bool> validateSession() async {
    try {
      final userId = DatabaseService.instance.getUserId();
      if (userId == null) {
        AppConfig.log('⚠️ No user ID in Hive');
        return false;
      }

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
```

- [ ] **Step 3: التحقق**

Run: `flutter analyze; if ($?) { flutter test }`
Expected: نظيف/أخضر

- [ ] **Step 4: Commit**

```powershell
git add lib/services/auth_service.dart
git commit -m "Fix: remove misleading unreachable catch-return-true session logic"
```

---

### Task 5: استخراج منطق قرارات مزامنة ما بعد الدخول (TDD)

**Files:**
- Create: `lib/helpers/sync_policy.dart`
- Test: `test/helpers/sync_policy_test.dart`

**Interfaces:**
- Produces: `class SyncPolicy` بدالتين ثابتتين نقيّتين تستخدمهما Task 6:
  - `static bool shouldRetryAfterFailure({required int attempt, required int maxRetries})`
  - `static bool needsDirectPull({required int productCount, required int saleCount})`

- [ ] **Step 1: اكتب الاختبار الفاشل**

```dart
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
```

- [ ] **Step 2: شغّله ليتحقق فشله**

Run: `flutter test test/helpers/sync_policy_test.dart`
Expected: FAIL (الملف lib/helpers/sync_policy.dart غير موجود)

- [ ] **Step 3: التنفيذ الأدنى**

```dart
// lib/helpers/sync_policy.dart

/// منطق قرارات مزامنة ما بعد تسجيل الدخول.
/// دوال نقية (pure) لسهولة الاختبار دون Firebase أو Hive.
class SyncPolicy {
  SyncPolicy._();

  /// هل نعيد المحاولة بعد فشل محاولة مزامنة؟
  /// [attempt] رقم المحاولة المنتهية (تبدأ من 1).
  static bool shouldRetryAfterFailure({
    required int attempt,
    required int maxRetries,
  }) {
    return attempt < maxRetries;
  }

  /// هل المخزن المحلي فارغ تماماً ويحتاج سحباً مباشراً من Firebase؟
  static bool needsDirectPull({
    required int productCount,
    required int saleCount,
  }) {
    return productCount == 0 && saleCount == 0;
  }
}
```

- [ ] **Step 4: شغّله ليتحقق نجاحه**

Run: `flutter test test/helpers/sync_policy_test.dart`
Expected: All tests passed!

- [ ] **Step 5: Commit**

```powershell
git add lib/helpers/sync_policy.dart test/helpers/sync_policy_test.dart
git commit -m "Add: pure SyncPolicy decisions with unit tests"
```

---

### Task 6: نقل تنسيق مزامنة ما بعد الدخول من login() إلى SyncService.syncAfterLogin()

**Files:**
- Modify: `lib/services/sync_service.dart` (إضافة method بعد syncNow، حوالي السطر 288)
- Modify: `lib/services/auth_service.dart` (login 134-283)

**Interfaces:**
- Consumes: `SyncPolicy` من Task 5.
- Produces: `Future<void> SyncService.syncAfterLogin({int maxRetries = 3})` — **لا ترمي أبداً** (تلتقط داخلياً).

**اكتشاف جوهري:** `syncNow()` يمسك جميع أخطائه داخلياً (sync_service.dart:276-287) ولا يرمي شيئاً عملياً، وحالة النجاح/الفشل تُنشر عبر `_syncStatusNotifier.value`. لذلك حلقة retry القديمة في login() كانت شبه ميّة. `syncAfterLogin` تقرأ حالة النوتفاير بعد كل محاولة، وتستخدم fallback السحب المباشر `_syncFromFirebase(fullPull: true)` إذا ظل Hive فارغاً.

- [ ] **Step 1: أضف syncAfterLogin إلى SyncService**

أضف imports إذا لزم (`../helpers/sync_policy.dart` موجود ضمن imports helpers؟ لا — أضِفه)، ثم بعد syncNow مباشرة:

```dart
  /// مزامنة ما بعد تسجيل الدخول (Offline First):
  /// رفع البيانات غير المتزامنة ثم سحب كامل لبيانات الحساب.
  ///
  /// لا ترمي استثناءً أبداً — فشل المزامنة لا يمنع الدخول.
  /// تُعيد المحاولة حتى [maxRetries] مرة إذا بقيت حالة آخر محاولة فاشلة
  /// والمخزن فارغاً، ثم تجرب سحباً مباشراً واحداً كشبكة أمان.
  Future<void> syncAfterLogin({int maxRetries = 3}) async {
    AppConfig.log('===== Post-login sync started (maxRetries: $maxRetries) =====');

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      await syncNow(fullSync: true);

      final lastOk = _syncStatusNotifier.value != SyncStatus.error;
      final hasData = !SyncPolicy.needsDirectPull(
        productCount: _db.getProductCount(),
        saleCount: _db.getSaleCount(),
      );

      if (lastOk || hasData) break;

      AppConfig.log('⚠️ Post-login sync incomplete (attempt $attempt/$maxRetries)');
      if (SyncPolicy.shouldRetryAfterFailure(attempt: attempt, maxRetries: maxRetries)) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    // ⭐ شبكة أمان: إذا ظل Hive فارغاً جرّب سحباً مباشراً واحداً
    if (SyncPolicy.needsDirectPull(
      productCount: _db.getProductCount(),
      saleCount: _db.getSaleCount(),
    )) {
      try {
        AppConfig.log('⚠️ Hive still empty, attempting direct pull...');
        await _syncFromFirebase(fullPull: true);
        _notifyDataChanged();
      } catch (e) {
        AppConfig.logError('❌ Direct data load failed', e);
      }
    }

    AppConfig.log('📊 Post-login sync finished:');
    AppConfig.log('  - Products: ${_db.getProductCount()}');
    AppConfig.log('  - Sales: ${_db.getSaleCount()}');
  }
```

- [ ] **Step 2: اختصر login() في AuthService**

استبدل كل ما بين حفظ `saveUserData` و`return true` (كتل المزامنة، retry loop، refresh الاشتراك الثاني، `if (!syncSuccess)`، عدادات الطوارئ) بـ:

```dart
      if (credential.user != null) {
        final db = DatabaseService.instance;
        final userId = credential.user!.uid;

        await db.saveUserData(
          userId: userId,
          phone: phone,
          fullName: credential.user!.displayName ?? '',
          storeName: credential.user!.displayName ?? '',
        );

        try {
          final subInfo = await firebaseService.getSubscriptionInfo();
          if (subInfo != null && subInfo['end_date'] != null) {
            await db.saveSubscriptionEndDate(subInfo['end_date']);
            await db.saveSubscriptionActive(true);
          }
        } catch (e) {
          AppConfig.logError('⚠️ Could not fetch subscription info', e);
        }

        // ⭐ Offline First: مزامنة كاملة للحساب (لا ترمي؛ الفشل لا يمنع الدخول)
        await SyncService().syncAfterLogin();

        // ⭐ تحديث الاشتراك بعد المزامنة حتى لا تظهر شاشة
        // "الاشتراك منتهي" بشكل خاطئ
        try {
          final subInfo = await firebaseService.getSubscriptionInfo();
          if (subInfo != null && subInfo['end_date'] != null) {
            await db.saveSubscriptionEndDate(subInfo['end_date']);
            await db.saveSubscriptionActive(true);
            AppConfig.log('✅ Subscription refreshed after sync');
          }
        } catch (e) {
          AppConfig.logError('⚠️ Could not refresh subscription info', e);
        }

        AppConfig.log('✅ Login successful!');
        return true;
      }
```

- [ ] **Step 3: احذف الدوال المكررة من AuthService**

احذف بالكامل: `_loadInitialData()` و`_emergencyLoadData()` (مسارهما المنطقي انتقل إلى `_syncFromFirebase(fullPull: true)` داخل syncNow/syncAfterLogin).

- [ ] **Step 4: تأكد عدم وجود مستخدمين آخرين للدوال المحذوفة**

Run: `rg "_loadInitialData|_emergencyLoadData" lib/`
Expected: no matches

- [ ] **Step 5: التحقق**

Run: `flutter analyze; if ($?) { flutter test }`
Expected: نظيف/أخضر

- [ ] **Step 6: Commit**

```powershell
git add lib/services/sync_service.dart lib/services/auth_service.dart
git commit -m "Refactor: move post-login sync orchestration into SyncService.syncAfterLogin"
```

---

### Task 7: تفكيك pos_screen (1/5) — أدوات الإيصال المشتركة

**Files:**
- Create: `lib/widgets/pos/receipt_formatting.dart`
- Modify: `lib/screens/pos_screen.dart`

**Interfaces:**
- Produces (تستهلكها Tasks 8-10):
  - `String formatPosDateTime(DateTime dt)` — من `_formatDateTime` (pos_screen.dart:1433)
  - `Widget buildPosReceiptRow({required String label, required String value, required Color color, double fontSize})` — من `_buildReceiptRow` (pos_screen.dart:1406). **اقرأ التواقيع الفعلية أولاً** وانقل المعاملات الاختيارية كما هي.

- [ ] **Step 1: اقرأ المصدر بدقة**

اقرأ pos_screen.dart الأسطر 1406-1440 وسجّل التواقيع والاعتماديات (AppTextStyles على الأغلب).

- [ ] **Step 2: أنشئ الملف الجديد بالنقل الحرفي**

انقل الكود حرفياً كدوال عامة top-level مع نفس الجسم. مثال الهيكل (عدّل التوقيع حسب المصدر):

```dart
// lib/widgets/pos/receipt_formatting.dart
// أدوات تنسيق إيصالات البيع مشتركة بين شاشة البيع والحوارات.

import 'package:flutter/material.dart';
import '../../theme/app_text_styles.dart';
// أضف imports أخرى بحسب ما يستخدمه الكود المنقول (intl مثلاً)

String formatPosDateTime(DateTime dt) => /* انقل جسم _formatDateTime حرفياً */;

Widget buildPosReceiptRow({
  required String label,
  required String value,
  required Color color,
  /* انقل أي معاملات اختيارية من المصدر */
}) {
  /* انقل جسم _buildReceiptRow حرفياً */
}
```

- [ ] **Step 3: حدّث pos_screen.dart**

- احذف `_formatDateTime` و`_buildReceiptRow` من الكلاس.
- أضف `import '../widgets/pos/receipt_formatting.dart';`
- استبدل كل استدعاءات `_formatDateTime(` بـ `formatPosDateTime(` و`_buildReceiptRow(` بـ `buildPosReceiptRow(` داخل الملف (توجد استدعاءات في checkout confirmation ~803+ وفي invoice dialog ~1346+). استخدم replaceAll بعناية بعد القراءة.

- [ ] **Step 4: التحقق**

Run: `flutter analyze; if ($?) { flutter test }`
Expected: نظيف/أخضر

Run: `rg "_formatDateTime|_buildReceiptRow" lib/`
Expected: no matches

- [ ] **Step 5: Commit**

```powershell
git add lib/widgets/pos/receipt_formatting.dart lib/screens/pos_screen.dart
git commit -m "Refactor: extract shared receipt formatting helpers from POS screen"
```

---

### Task 8: تفكيك pos_screen (2/5) — عنصر شبكة المنتجات

**Files:**
- Create: `lib/widgets/pos/product_grid_item.dart`
- Modify: `lib/screens/pos_screen.dart`

**Interfaces:**
- Produces: `class POSProductGridItem extends StatelessWidget` — يستقبل `Product product` و`String currency` وأي callbacks يحتاجها الجسم (على الأغلب `VoidCallback onTap` أو `Function(Product)`).

- [ ] **Step 1: اقرأ المصدر**

اقرأ `_buildProductGridItem` (pos_screen.dart:2162 حتى نهاية الميثود) وسجّل كل مرجع خارجي: `_currency`، دوال الحالة مثل الإضافة للسلة أو `_showSnackBar`، إلخ.

- [ ] **Step 2: أنشئ الويدجت بالنقل الحرفي**

```dart
// lib/widgets/pos/product_grid_item.dart

import 'package:flutter/material.dart';
import '../../models/product_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../helpers/localization_helper.dart';

/// بطاقة منتج في شبكة شاشة البيع.
class POSProductGridItem extends StatelessWidget {
  final Product product;
  final String currency;
  /* أضف الحقول التي يتطلبها الجسم المنقول (callbacks) */
  const POSProductGridItem({
    super.key,
    required this.product,
    required this.currency,
    /* required this.onTap, */
  });

  @override
  Widget build(BuildContext context) {
    /* انقل جسم _buildProductGridItem حرفياً مع استبدال
       المراجع الخارجية بالحقول أعلاه */
  }
}
```

- [ ] **Step 3: حدّث موقع الاستدعاء**

في pos_screen.dart استبدل `_buildProductGridItem(product)` في builder الشبكة بـ:

```dart
POSProductGridItem(
  product: product,
  currency: _currency,
  /* onTap: () => نفس سلوك المصدر الأصلي */
),
```

ثم احذف `_buildProductGridItem` وأضف import الملف الجديد. **ملاحظة:** إن كان المنتج يعرض حالة نفاد الكمية عبر دالة حالة خاصة بالمكوّن، انقل تلك الدالة الصغيرة معه إلى الملف الجديد.

- [ ] **Step 4: التحقق**

Run: `flutter analyze; if ($?) { flutter test }`
Expected: نظيف/أخضر

- [ ] **Step 5: Commit**

```powershell
git add lib/widgets/pos/product_grid_item.dart lib/screens/pos_screen.dart
git commit -m "Refactor: extract product grid item widget from POS screen"
```

---

### Task 9: تفكيك pos_screen (3/5) — ورقة تأكيد الدفع ومعالجة الدفع

**Files:**
- Create: `lib/widgets/pos/checkout_confirmation_sheet.dart`
- Modify: `lib/screens/pos_screen.dart`

**Interfaces:**
- Consumes: `buildPosReceiptRow`, `formatPosDateTime`, `CartService`.
- Produces:
  - `Future<void> showCheckoutConfirmationSheet(BuildContext context, {required CartService cart, required VoidCallback onConfirm})` — من `_showCheckoutConfirmation` (703 حتى ~1104)
  - `Future<void> showPosProcessingDialog(BuildContext context)` — من `_showProcessingDialog` (1105-1147)

- [ ] **Step 1: اقرأ المصدر**

اقرأ الأسطر 703-1150. سجّل: كيف يُغلق الـ sheet عند التأكيد، وماذا يستدعي بعد الإغلاق (على الأغلب `_processCheckout(cart)` من موقع الاستدعاء)، وأي مراجع لحالة الكلاس.

- [ ] **Step 2: أنشئ الملف بالنقل الحرفي**

```dart
// lib/widgets/pos/checkout_confirmation_sheet.dart
// ورقة تأكيد الدفع وحوار معالجة العملية لشاشة البيع.

import 'package:flutter/material.dart';
import '../../services/cart_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../helpers/localization_helper.dart';
import 'receipt_formatting.dart';

Future<void> showCheckoutConfirmationSheet(
  BuildContext context, {
  required CartService cart,
  required VoidCallback onConfirm,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  /* انقل باقي جسم _showCheckoutConfirmation حرفياً؛ زر التأكيد يستدعي:
     Navigator.pop(ctx); onConfirm();  بدل الاستدعاء المباشر لـ _processCheckout */
}

Future<void> showPosProcessingDialog(BuildContext context) {
  /* انقل جسم _showProcessingDialog حرفياً */
}
```

- [ ] **Step 3: حدّث مواقع الاستدعاء في pos_screen.dart**

استبدل `_showCheckoutConfirmation(cart)` (داخل `_processCheckout` تقريباً سطر 703) بـ:

```dart
await showCheckoutConfirmationSheet(context, cart: cart, onConfirm: () {
  _processCheckout(cart);
});
```

إن كان المصدر يستدعي `_processCheckout` قبل الإغلاق أو بعده، حافظ على نفس الترتيب الزمني تماماً. ثم احذف الميثودتين من الكلاس وأضف الـ import.

- [ ] **Step 4: التحقق**

Run: `flutter analyze; if ($?) { flutter test }`
Expected: نظيف/أخضر

- [ ] **Step 5: Commit**

```powershell
git add lib/widgets/pos/checkout_confirmation_sheet.dart lib/screens/pos_screen.dart
git commit -m "Refactor: extract checkout confirmation sheet from POS screen"
```

---

### Task 10: تفكيك pos_screen (4/5) — حوار خيارات الفاتورة

**Files:**
- Create: `lib/widgets/pos/invoice_options_dialog.dart`
- Modify: `lib/screens/pos_screen.dart`

**Interfaces:**
- Consumes: `buildPosReceiptRow`, `formatPosDateTime`.
- Produces: `Future<void> showInvoiceOptionsDialog(BuildContext context, {required List<CartItem> items, required double subtotal, required double discount, required double tax, required double taxRate, required double total, required String paymentMethod, required String saleId, required DateTime date})` — نفس توقيع الميثود الحالية عند 1147 (مع `BuildContext context` الأول كما هو).

- [ ] **Step 1: اقرأ المصدر**

اقرأ الأسطر 1147-1405 (`_showInvoiceOptionsDialog` + `_buildInvoiceOption` 1346-1405). سجّل الاعتماديات (PrintingService على الأغلب للطباعة/المشاركة — يمكن استيراده مباشرة).

- [ ] **Step 2: أنشئ الملف بالنقل الحرفي**

انقل الميثود كدالة top-level بنفس المعاملات، و`_buildInvoiceOption` كدالة خاصة `_buildInvoiceOption` في نفس الملف. استورد PrintingService وCart item model حسب الحاجة.

- [ ] **Step 3: حدّث موقع الاستدعاء**

استبدل `_showInvoiceOptionsDialog(context, ...)` بـ `showInvoiceOptionsDialog(context, ...)` (نفس المعاملات)، احذف الميثودتين من الكلاس، أضف الـ import.

- [ ] **Step 4: التحقق**

Run: `flutter analyze; if ($?) { flutter test }`
Expected: نظيف/أخضر

- [ ] **Step 5: Commit**

```powershell
git add lib/widgets/pos/invoice_options_dialog.dart lib/screens/pos_screen.dart
git commit -m "Refactor: extract invoice options dialog from POS screen"
```

---

### Task 11: تفكيك pos_screen (5/5) — الطلبات المعلقة

**Files:**
- Create: `lib/widgets/pos/held_orders.dart`
- Modify: `lib/screens/pos_screen.dart`

**Interfaces:**
- Produces:
  - `Future<String?> showHoldOrderNameDialog(BuildContext context, {required CartService cart})` — من `_holdCurrentOrder` (1438-1540): تُعيد اسم الطلب المحفوظ أو null عند الإلغاء؛ **الحفظ الفعلي (منطق `cart.holdOrder` أو ما يقابله في المصدر) يبقى في موقع الاستدعاء** حتى لا تلمس طبقة البيانات.
  - `Future<void> showHeldOrdersSheet(BuildContext context, {required CartService cart, required VoidCallback onChanged})` — من `_showHeldOrders` (1541-1673): `onChanged` تُستدعى عند استعادة طلب أو حذفه ليحدّث pos_screen حالتها (`setState`).

- [ ] **Step 1: اقرأ المصدر**

اقرأ الأسطر 1438-1673. سجّل بالضبط ماذا يحدث عند: حفظ الطلب، استعادة طلب معلق، حذف طلب معلق (أي دوال cart/db تُستدعى وما بعدها من setState/snackbar).

- [ ] **Step 2: أنشئ الملف بالنقل الحرفي**

انقل الواجهات حرفياً مع تمرير النتائج عبر القيم المُعادة و`onChanged` بدل لمس حالة الكلاس مباشرة. أي منطق كتابة بيانات (DatabaseService) يمكن استيراده واستخدامه داخل الملف الجديد مباشرة إن كان المكوّن مستقلاً.

- [ ] **Step 3: حدّث مواقع الاستدعاء**

في pos_screen.dart: استبدل استدعاءات `_holdCurrentOrder(cart)` و`_showHeldOrders(cart)` بالدوال الجديدة، مع تمرير closures تحافظ على السلوك (setState + snackbar + إعادة بناء السلة). احذف الميثودتين، أضف الـ import.

- [ ] **Step 4: التحقق النهائي للتفكيك**

Run: `flutter analyze; if ($?) { flutter test }`
Expected: نظيف/أخضر

Run: `(Get-Content lib\screens\pos_screen.dart).Count`
Expected: أقل بكثير من 2554 (متوقع ~900-1200 سطراً)

- [ ] **Step 5: Commit**

```powershell
git add lib/widgets/pos/held_orders.dart lib/screens/pos_screen.dart
git commit -m "Refactor: extract held orders dialogs from POS screen"
```

---

### Task 12: تحقق نهائي شامل

- [ ] **Step 1: التحليل والاختبارات والتنسيق**

```powershell
flutter analyze
flutter test
dart format lib\helpers\sync_policy.dart lib\widgets\pos lib\services\auth_service.dart lib\services\sync_service.dart
```
Expected: No issues / All tests passed!

- [ ] **Step 2: مراجعة الحالة النهائية**

```powershell
git status --short
git log --oneline -12
```
Expected: شجرة نظيفة (كل شيء ملتزم) وسلسلة commits واضحة.

- [ ] **Step 3: تقرير**

اذكر للمستخدم: عدد أسطر pos_screen قبل/بعد، قائمة الملفات الجديدة، وأن المشاكل 1،2،3،4،6،7،8 مُصلحة والمشكلة 5 مستثناة بطلبه.
