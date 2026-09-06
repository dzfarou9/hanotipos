# نظام الموردين والمشتريات — وثيقة التصميم

**التاريخ:** 2026-08-25
**الحالة:** معتمدة من المستخدم
**النوع:** معماري (Architectural)

## 1. الهدف

إضافة نظام موردين كامل لتطبيق POS (Flutter) يعمل بنظام Offline First:

- إدارة الموردين (إضافة/تعديل/حذف/بحث)
- شراء من مورد (يرفع كميات المخزون)
- إرجاع للمورد (ينقص كميات المخزون)
- حذف عملية شراء أو مرتجع (يعكس أثرها على المخزون)
- مزامنة كاملة مع Firebase + قراءة محلية من Hive

## 2. النماذج الجديدة

### 2.1 Supplier (typeId: 5)

| الحقل | النوع | ملاحظات |
|-------|------|---------|
| id | String | UUID، مفتاح صندوق Hive |
| name | String | إلزامي |
| phone | String? | |
| address | String? | |
| notes | String? | |
| userId | String | مالك البيانات |
| isSynced | bool | false عند التعديل المحلي |
| createdAt | DateTime | |
| updatedAt | DateTime | يُحدَّث عند أي تعديل؛ يستخدم للسحب التزايدي |

`fromJson`/`toJson` بنمط snake_case المطابق لبقية النماذج (`user_id`, `created_at`...).

### 2.2 PurchaseItem (typeId: 6)

| الحقل | النوع |
|-------|------|
| id | String |
| productId | String |
| productName | String (منسوخ للعرض دون استعلام) |
| costPrice | double |
| quantity | int |
| subtotal | double = costPrice × quantity |

### 2.3 Purchase (typeId: 7)

| الحقل | النوع | ملاحظات |
|-------|------|---------|
| id | String | UUID |
| items | List\<PurchaseItem\> | |
| supplierId | String | |
| supplierName | String | منسوخ للعرض |
| total | double | مجموع الأصناف |
| note | String? | |
| purchaseType | String | `'purchase'` أو `'return'` (افتراضي `'purchase'`) |
| originalPurchaseId | String? | يملأ في حالة المرتجع فقط |
| userId | String | |
| isSynced | bool | |
| createdAt | DateTime | |

**قرار:** المرتجع سجل `Purchase` مستقل (`purchaseType = 'return'`) يشير للأصلية عبر `originalPurchaseId`. لا نعدّل الشراء الأصلي بعد إنشائه (بسيط ومتسق؛ حساب "المتاح للإرجاع" يتم بالاستعلام عن مرتجعات نفس `originalPurchaseId`). هذا أبسط من نمط `Sale.returnedItems` ولا يحتاجه هنا.

## 3. التخزين المحلي — DatabaseService

- صندوقان جديدان مشفران بنفس مفتاح Hive الحالي: `suppliers` (Box\<Supplier\>)، `purchases` (Box\<Purchase\>)
- تسجيل المهايئات: `SupplierAdapter`, `PurchaseAdapter`, `PurchaseItemAdapter`
- إضافة الصندوقين إلى `_allBoxNames` (للهجرة والتشفير)
- دوال جديدة بنفس أنماط المنتجات/المبيعات:
  - Suppliers: `getAllSuppliers()` (مرتبة بالاسم)، `getUnsyncedSuppliers()`, `addSupplierWithId()`, `updateSupplier()`, `deleteSupplier()`, `markSupplierAsSynced()`
  - Purchases: `getAllPurchases()` (مرتبة تنازلياً بالتاريخ)، `getPurchasesBySupplier(id)`، `getReturnPurchasesFor(originalId)`، `getUnsyncedPurchases()`, `addPurchaseWithId()`, `deletePurchase()`, `markPurchaseAsSynced()`
  - `supplierExists(id)`
- Tombstones: إعادة استخدام `addPendingDelete/getPendingDeletes/removePendingDelete` بأنواع `'supplier'` و `'purchase'`
- `clearUserData()`: مسح الصندوقين عند تسجيل الخروج
- `closeBoxes()`: إغلاق الصندوقين

## 4. Firebase

### 4.1 المجموعات (FirebaseConfig)

```dart
static const String suppliersCollection = 'suppliers';
static const String purchasesCollection = 'purchases';
```

### 4.2 دوال FirebaseService الجديدة

- `addSupplier({id, name, phone, address, notes, createdAt})`
- `updateSupplier(...)` (نفس حقول الإضافة)
- `deleteSupplier(String id)`
- `getSuppliers({DateTime? lastSync})` — سحب تزايدي بـ `whereGreaterThan('updated_at', lastSync)` بنمط `getProducts`
- `addPurchase({id, items, supplierId, supplierName, total, note, purchaseType, originalPurchaseId, createdAt})`
- `addPurchasesBatch(List<Map>)` / `addSuppliersBatch(List<Map>)`
- `getPurchases({DateTime? lastSync})` — الأصناف تُخزَّن كمصفوفة داخل وثيقة الشراء (بدلاً من مجموعة فرعية مثل `sale_items`؛ المشتريات أصغر حجماً وتُقرأ دائماً مع رأسها)
- `deletePurchase(String id)`

كل الوثائق تتضمن `user_id` وتُستعلم بفلتر المستخدم الحالي (نفس نمط المنتجات).

### 4.3 قواعد Firestore

تحديث `firestore.rules`: السماح بالقراءة/الكتابة للمجموعتين `suppliers` و `purchases` لنفس قاعدة `user_id == request.auth.uid` المطبقة على باقي المجموعات.

## 5. المزامنة — SyncService

### 5.1 الرفع (Push) — داخل `_syncUnsyncedData()`

- مزامنة الموردين غير المتزامنين (Batch ثم fallback فردي عند الفشل)
- مزامنة المشتريات غير المتزامنة (Batch ثم fallback فردي)

### 5.2 السحب (Pull) — داخل `_syncFromFirebase()`

- جلب الموردين والمشتريات بتاريخ آخر مزامنة (سحب تزايدي)
- **Mوردون:** إذا لم يوجد محلياً → إضافة (isSynced=true). إذا وجد ومتزامن → تحديث إذا كان سيرفر أحدث. غير متزامن → يُترك كما هو (نمط المنتجات)
- **مشتريات:** إضافة فقط إذا لم توجد محلياً (لا تعديل للموجود — نمط المبيعات)

### 5.3 الكتابة المباشرة (Write-through)

عند أي إنشاء/حذف وهو الجهاز متصل: حفظ محلي فوري (isSynced=false) ثم محاولة رفع مباشر؛ عند الفشل تبقى غير متزامنة وتُرفع لاحقاً — نفس نمط `addProduct/deleteSale`.

### 5.4 عدادات الحالة

`pendingSyncCount` و `getUnsyncedCount()` تشمل الموردين والمشتريات.

## 6. قواعد المخزون (طبقة منطق في SyncService)

| العملية | أثر المخزون | حركة مخزون مسجلة |
|---------|-------------|-------------------|
| إنشاء شراء | `quantity += qty` لكل صنف | `incoming` + supplierName |
| إنشاء مرتجع | `quantity -= qty` لكل صنف | `return_out` + supplierName |
| حذف شراء | `quantity -= qty` لكل صنف | — |
| حذف مرتجع | `quantity += qty` لكل صنف | — |

قواعد إضافية:

- **منع المرتجع الزائد:** مجموع (المرتجعات القائمة + الكمية الجديدة) لكل منتج يجب ألا يتجاوز الكمية المشتراة منه في الشراء الأصلي
- **منع النقص تحت الصفر:** إذا كانت كمية المنتج الحالية أقل من كمية الإرجاع/الحذف → رفض العملية برسالة واضحة (لا كميات سالبة)
- **تحديث سعر المنتج:** لا. سعر التكلفة يُسجل في `PurchaseItem.costPrice` فقط؛ سعر البيع (`Product.price`) لا يتغير (YAGNI)
- كل تعديل كمية عبر `updateQuantity()` الموجود (يضبط `isSynced=false` تلقائياً)

### 6.1 حذف عملية شراء (السيناريو الكامل)

1. التحقق من إمكانية عكس الأثر (كميات كافية)
2. عكس أثر الكميات في Hive
3. `deletePurchase` من صندوق Hive
4. Tombstone: `addPendingDelete('purchase', id)`
5. إن كان متصلاً → `firebase.deletePurchase` وإزالة الـ Tombstone
6. إشعار الواجهة `_notifyDataChanged()`

**حالة خاصة:** إذا كان عكس الأثر سيجعل كمية منتج سالبة (مثلاً: شراء 10 ثم رجاع 3 ثم حذف الشراء) → يُرفض الحذف برسالة توجّه المستخدم لحذف المرتجعات المرتبطة أولاً (تُعرض في شاشة التفاصيل).

## 7. الشاشات والواجهة

### 7.1 شاشة الموردين (`lib/screens/suppliers_screen.dart`)

- قائمة الموردين من Hive + حقل بحث بالاسم/الهاتف
- زر عائم للإضافة؛ نقر على مورد → ورقة سفلية (Bottom Sheet) عرض/تعديل
- حذف مورد: مربع تأكيد يوضح عدد مشترياته المسجلة (الحذف لا يمسح المشتريات؛ اسم المورد منسوخ فيها فتبقى سليمة)
- حالة فراغ عندما لا يوجد موردون

### 7.2 شاشة الشراء (`lib/screens/purchase_screen.dart`)

- اختيار مورد (قائمة منسدلة؛ زر "إضافة مورد" سريع داخلها)
- **مسح باركود**: زر يفتح `BarcodeScannerView` الموجود؛ البحث عبر `getProductByBarcode`؛ دعم الإدخال اليدوي بقائمة اختيار منتجات كبديل
- لكل صنف: كمية + سعر تكلفة (القيمة الافتراضية 0.0 قابلة للتعديل؛ سعر البيع لا يُستخدم كتكلفة)
- سلة قابلة للتعديل (كمية/حذف صنف) + إجمالي
- حقل ملاحظة اختياري + زر "حفظ الشراء"

### 7.3 سجل المشتريات (`lib/screens/purchases_history_screen.dart`)

- قائمة تنازلية بالتاريخ مع شارة نوع (شراء أخضر / مرتجع بنفسجي — نفس ألوان `MovementType`)
- تصفية حسب المورد (اختياري)
- تفاصيل العملية في Bottom Sheet (الأصناف، الكميات، الأسعار، الملاحظة)
- **زر حذف** (شراء أو مرتجع) مع تأكيد يوضح أنه سيُعكس أثر الكميات
- زر "إرجاع للمورد" يظهر على عمليات الشراء فقط → يفتح شاشة الإرجاع معبأة بأصناف الشراء الأصلية والمتاح للإرجاع لكل صنف

### 7.4 شاشة الإرجاع (`lib/screens/supplier_return_screen.dart`)

- نفس بنية شاشة الشراء لكن:
  - المورد مثبت من الشراء الأصلي
  - الأصناف **محدودة بأصناف الشراء الأصلي فقط** (لا يمكن إضافة أصناف أخرى)؛ سقف كل صنف = المشترى − المرتجع سابقاً
  - الكمية الافتراضية لكل صنف = السقف المتاح، قابلة للتنقيص

### 7.5 التنقل

- مدخل "الموردين" في `dashboard_menu.dart` (أيقونة `local_shipping_rounded`)
- من شاشة الموردين: زر "عملية شراء جديدة" وسجل مشترياته
- من الداشبورد: بطاقة/مدخل لسجل المشتريات

### 7.6 الترجمة

مفاتيح جديدة في `assets/translations/{ar,en,fr}.json` تحت قسم `suppliers` و `purchases` (الأسماء، الحقول، الأزرار، رسائل الأخطاء، رسائل التأكيد).

## 8. الاختبارات

- `test/models/purchase_model_test.dart`: JSON roundtrip للنماذج الثلاثة، parse التواريخ
- `test/services/suppliers_stock_test.dart` (منطق المخزون):
  - شراء بكمية n يزيد المخزون n ويكتب حركة incoming
  - مرتجع ينقص المخزون ويكتب return_out
  - حذف شراء يعكس الكميات
  - حذف مرتجع يعيدها
  - رفض مرتجع أكبر من المشترى
  - رفض عملية تجعل الكمية سالبة
- اختبارات الواجهة الأساسية لشاشة الموردين (بناء، إضافة)

## 9. معالجة الأخطاء

- فشل الشبكة أثناء أي كتابة → العملية تبقى محلية (isSynced=false) ولا يرى المستخدم خطأً؛ الرفع تلقائي عند العودة
- حذف فاشل في Firebase → Tombstone يضمن إعادة المحاولة
- مورد محذوف مُشار إليه في شراء قائم → لا انكسار (اسم المورد منسوخ في العملية)
- منع حذف/تعديل أثناء مزامنة جارية غير مطلوب — العمليات محلية أولاً بطبيعتها

## 10. خارج النطاق (YAGNI)

- مدفوعات/ديون الموردين (آجل، جزئي)
- ربط سعر التكلفة بسعر بيع المنتج أو حساب الأرباح من المشتريات
- أوامر شراء معلقة (Draft POs)
- فواتير شراء PDF
