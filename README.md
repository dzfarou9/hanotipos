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

## ويندوز (Windows Desktop)

التطبيق يعمل على ويندوز بنمط **محلي أولاً (Local-First)**:

- **المصادقة:** حساب محلي مشفّر (sha256 + ملح) عبر `flutter_secure_storage` — بدون Firebase Auth.
- **الاشتراك:** يُحكم من تاريخ الانتهاء المحلي (تجربة 30 يوماً عند أول تسجيل دخول).
- **الماسح:** قارئ USB (keyboard wedge) عبر `BarcodeInputService` بدل كاميرا/ML Kit؛ تسجيل الدخول بـ QR معطّل.
- **المزامنة السحابية:** معطّلة على ويندوز حالياً (لا جلسة Firebase Auth) — البيانات محلية عبر Hive.

المتطلبات:

- Windows 10 أو أحدث
- Flutter SDK مع تفعيل دعم ويندوز: `flutter config --enable-windows-desktop`
- Visual Studio 2022 مع عبء عمل **Desktop development with C++**

```bash
flutter pub get
flutter run -d windows
```

للإصدار النهائي:

```bash
flutter build windows --release
```

ملف Firebase الخاص بويندوز مسجّل باسم `hanoti-windows` (appId بنمط web) في `lib/firebase_options.dart`.

## الاختبارات والتحليل

```bash
flutter test
flutter analyze
```

CI ينفذ الأمرين أعلاه تلقائياً على الـ pushes إلى main/master وعلى جميع pull requests (`.github/workflows/ci.yml`).

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
