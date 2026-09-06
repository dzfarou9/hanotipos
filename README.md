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
