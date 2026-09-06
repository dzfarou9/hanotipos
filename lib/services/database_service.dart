// lib/services/database_service.dart

import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';
import '../models/product_model.dart';
import '../models/sale_model.dart';
import '../models/inventory_movement_model.dart';
import '../models/inventory_movement_enum_adapters.dart';
import '../models/supplier_model.dart';
import '../models/purchase_model.dart';
import '../models/customer_model.dart';
import '../models/debt_transaction_model.dart';
import '../models/debt_transaction_enum_adapter.dart';
import '../helpers/debt_ledger_helper.dart';
import '../helpers/localization_helper.dart';
import 'sales_cache.dart';
import 'products_cache.dart';

class DatabaseService {
  static const String _productsBoxName = 'products';
  static const String _salesBoxName = 'sales';
  static const String _metadataBoxName = 'metadata';
  static const String _movementsBoxName = 'inventory_movements';
  static const String _syncLogBoxName = 'sync_log';
  static const String _suppliersBoxName = 'suppliers';
  static const String _purchasesBoxName = 'purchases';
  static const String _customersBoxName = 'customers';
  static const String _debtTransactionsBoxName = 'debt_transactions';
  static const String _hiveKeyStorageKey = 'hive_encryption_key_v1';

  // ⭐ قائمة بكل الصناديق حتى نفتحها وتُحذف مع التشفير عند الهجرة
  static const List<String> _allBoxNames = [
    _productsBoxName,
    _salesBoxName,
    _metadataBoxName,
    _movementsBoxName,
    _syncLogBoxName,
    _suppliersBoxName,
    _purchasesBoxName,
    _customersBoxName,
    _debtTransactionsBoxName,
  ];

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static DatabaseService? _instance;
  late Box<Product> _productsBox;
  late Box<Sale> _salesBox;
  late Box _metadataBox;
  late Box<InventoryMovement> _movementsBox;
  late Box<Supplier> _suppliersBox;
  late Box<Purchase> _purchasesBox;
  late Box<Customer> _customersBox;
  late Box<DebtTransaction> _debtTransactionsBox;
  late SalesCache _salesCache;
  late ProductsCache _productsCache;
  final Uuid _uuid = const Uuid();

  // Cache للبيانات الإحصائية
  Map<String, dynamic>? _cachedStats;
  DateTime? _statsCacheTime;
  static const Duration _statsCacheDuration = Duration(seconds: 10);

  // Categories cache with TTL
  List<String>? _cachedCategories;
  DateTime? _categoriesCacheTime;
  static const Duration _categoriesCacheDuration = Duration(hours: 1);

  // Barcode index for O(1) product lookups by barcode
  Map<String, String> _barcodeIndex = <String, String>{};
  Map<String, List<String>> _customerDebtIndex = <String, List<String>>{};
  Map<String, CustomerLedger> _ledgerCache = <String, CustomerLedger>{};

  // سجل التعديلات للـ Conflict Resolution
  late Box _syncLogBox;

  DatabaseService._();

  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  Future<void> init() async {
    await Hive.initFlutter();

    Hive.registerAdapter(ProductAdapter());
    Hive.registerAdapter(SaleAdapter());
    Hive.registerAdapter(SaleItemAdapter());
    Hive.registerAdapter(InventoryMovementAdapter());
    // ⭐ adapters الenums لحركات المخزون (مكتوبة يدوياً — انظر الملف)
    Hive.registerAdapter(MovementTypeAdapter());
    Hive.registerAdapter(MovementStatusAdapter());
    Hive.registerAdapter(SupplierAdapter());
    Hive.registerAdapter(PurchaseAdapter());
    Hive.registerAdapter(PurchaseItemAdapter());
    Hive.registerAdapter(CustomerAdapter());
    Hive.registerAdapter(DebtTransactionAdapter());
    Hive.registerAdapter(DebtTransactionTypeAdapter());

    // ⭐ تشفير كل الصناديق: مفتاح 256 بت مخزَّن في التخزين الآمن
    // (Android Keystore / iOS Keychain). عند أول تشغيل بعد هذا التحديث
    // تُحذف الصناديق القديمة غير المشفرة ويُعاد سحب البيانات من Firestore
    // (المستخدم يعيد تسجيل الدخول مرة واحدة فقط).
    final hiveKey = await _getOrCreateHiveKey();
    final cipher = HiveAesCipher(hiveKey);

    _productsBox = await Hive.openBox<Product>(_productsBoxName,
        encryptionCipher: cipher);
    _salesBox =
        await Hive.openBox<Sale>(_salesBoxName, encryptionCipher: cipher);
    _metadataBox =
        await Hive.openBox(_metadataBoxName, encryptionCipher: cipher);
    _movementsBox = await Hive.openBox<InventoryMovement>(_movementsBoxName,
        encryptionCipher: cipher);
    _syncLogBox =
        await Hive.openBox(_syncLogBoxName, encryptionCipher: cipher);
    _suppliersBox =
        await Hive.openBox<Supplier>(_suppliersBoxName, encryptionCipher: cipher);
    _purchasesBox =
        await Hive.openBox<Purchase>(_purchasesBoxName, encryptionCipher: cipher);
    _customersBox = await Hive.openBox<Customer>(_customersBoxName, encryptionCipher: cipher);
    _debtTransactionsBox = await Hive.openBox<DebtTransaction>(_debtTransactionsBoxName, encryptionCipher: cipher);
    _salesCache = SalesCache(_salesBox);
    _productsCache = ProductsCache(_productsBox);

    await _buildBarcodeIndex();
    _buildCustomerDebtIndex();
  }

  /// يُعيد مفتاح تشفير Hive من التخزين الآمن، أو يولّد ويخزّن مفتاحاً جديداً.
  /// عند أول تشغيل (لا يوجد مفتاح مخزّن) تُحذف أي صناديق قديمة غير مشفرة
  /// لأن قراءتها بمفتاح جديد مستحيلة.
  Future<List<int>> _getOrCreateHiveKey() async {
    final existing = await _secureStorage.read(key: _hiveKeyStorageKey);
    if (existing != null) {
      return base64Url.decode(existing);
    }

    final newKey = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    await _secureStorage.write(
        key: _hiveKeyStorageKey, value: base64Url.encode(newKey));

    // ⭐ هجرة: حذف الصناديق القديمة غير المشفرة قبل فتحها بالمفتاح الجديد
    for (final boxName in _allBoxNames) {
      if (await Hive.boxExists(boxName)) {
        try {
          await Hive.deleteBoxFromDisk(boxName);
        } catch (_) {
          // تجاهل: الصناديق الجديدة ستُنشأ فارغة
        }
      }
    }

    return newKey;
  }

  // ⭐ تتبع الحذف غير المتزامن (Tombsones) حتى تتم المزامنة
  Future<void> addPendingDelete(String type, String id) async {
    await _metadataBox.put(
        'pending_delete_${type}_$id', DateTime.now().toIso8601String());
  }

  List<String> getPendingDeletes(String type) {
    final ids = <String>[];
    final prefix = 'pending_delete_${type}_';
    for (final key in _metadataBox.keys) {
      final k = key.toString();
      if (k.startsWith(prefix)) {
        ids.add(k.substring(prefix.length));
      }
    }
    return ids;
  }

  Future<void> removePendingDelete(String type, String id) async {
    await _metadataBox.delete('pending_delete_${type}_$id');
  }

  // ==================== Sync Log Methods ====================

  void setLastServerUpdate(String productId, DateTime serverTime) {
    _syncLogBox.put('server_update_$productId', serverTime.toIso8601String());
  }

  DateTime? getLastServerUpdate(String productId) {
    final value = _syncLogBox.get('server_update_$productId');
    if (value == null) return null;
    try {
      return DateTime.parse(value as String);
    } catch (e) {
      return null;
    }
  }

  void logConflict({
    required String productId,
    required String localVersion,
    required String serverVersion,
    required String resolution,
  }) {
    final timestamp = DateTime.now().toIso8601String();
    _syncLogBox.put('conflict_$productId', {
      'product_id': productId,
      'local_version': localVersion,
      'server_version': serverVersion,
      'resolution': resolution,
      'timestamp': timestamp,
    });
  }

  List<Map<String, dynamic>> getConflicts() {
    final conflicts = <Map<String, dynamic>>[];
    for (var key in _syncLogBox.keys) {
      if (key.toString().startsWith('conflict_')) {
        final value = _syncLogBox.get(key);
        if (value != null) {
          conflicts.add(value as Map<String, dynamic>);
        }
      }
    }
    conflicts.sort((a, b) {
      final aTime = DateTime.tryParse(a['timestamp'] as String? ?? '');
      final bTime = DateTime.tryParse(b['timestamp'] as String? ?? '');
      if (aTime == null || bTime == null) return 0;
      return bTime.compareTo(aTime);
    });
    return conflicts;
  }

  Future<void> cleanOldConflicts() async {
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    final keysToDelete = <String>[];
    for (var key in _syncLogBox.keys) {
      if (key.toString().startsWith('conflict_')) {
        final value = _syncLogBox.get(key);
        if (value != null) {
          final timestamp = DateTime.tryParse(
              ((value as Map)['timestamp'] as String?) ?? '');
          if (timestamp != null && timestamp.isBefore(thirtyDaysAgo)) {
            keysToDelete.add(key as String);
          }
        }
      }
    }
    for (var key in keysToDelete) {
      await _syncLogBox.delete(key);
    }
  }

  // ==================== Metadata ====================

  Future<void> saveUserData({
    required String userId,
    required String phone,
    required String fullName,
    required String storeName,
  }) async {
    await _metadataBox.put('user_id', userId);
    await _metadataBox.put('user_phone', phone);
    await _metadataBox.put('user_full_name', fullName);
    await _metadataBox.put('user_store_name', storeName);
  }

  String? getUserId() => _metadataBox.get('user_id');
  String? getUserPhone() => _metadataBox.get('user_phone');
  String? getUserFullName() => _metadataBox.get('user_full_name');
  String? getStoreName() => _metadataBox.get('user_store_name');

  Future<void> saveStoreInfo({
    required String storeName,
    String? phone,
    String? address,
    String? taxId,
  }) async {
    await _metadataBox.put('user_store_name', storeName);
    await _metadataBox.put(
      'user_store_phone',
      (phone == null || phone.isEmpty) ? null : phone,
    );
    await _metadataBox.put(
      'user_store_address',
      (address == null || address.isEmpty) ? null : address,
    );
    await _metadataBox.put(
      'user_store_tax_id',
      (taxId == null || taxId.isEmpty) ? null : taxId,
    );
  }

  String? getStorePhone() =>
      _metadataBox.get('user_store_phone') ?? _metadataBox.get('user_phone');
  String? getStoreAddress() => _metadataBox.get('user_store_address');
  String? getStoreTaxId() => _metadataBox.get('user_store_tax_id');

  Future<void> clearUserData() async {
    // ⭐ كل خطوة مستقلة try/catch: فشل حذف مفتاح واحد لا يوقف المسح كله،
    // والأخطاء تُجمع للفحص النهائي في الأسفل.
    final failures = <String>[];
    Future<void> tryStep(String label, Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        failures.add('$label (${e.runtimeType})');
        AppConfig.logError('⚠️ clearUserData: $label failed', e);
      }
    }

    await tryStep('user_id', () => _metadataBox.delete('user_id'));
    await tryStep('user_phone', () => _metadataBox.delete('user_phone'));
    await tryStep('user_full_name', () => _metadataBox.delete('user_full_name'));
    await tryStep('user_store_name', () => _metadataBox.delete('user_store_name'));
    await tryStep('user_store_phone',
        () => _metadataBox.delete('user_store_phone'));
    await tryStep('user_store_address',
        () => _metadataBox.delete('user_store_address'));
    await tryStep('user_store_tax_id',
        () => _metadataBox.delete('user_store_tax_id'));
    await tryStep('subscription_end_date',
        () => _metadataBox.delete('subscription_end_date'));
    await tryStep('subscription_active',
        () => _metadataBox.delete('subscription_active'));
    await tryStep('subscription_last_verified',
        () => _metadataBox.delete('subscription_last_verified'));
    await tryStep('subscription_plan_type',
        () => _metadataBox.delete('subscription_plan_type'));
    await tryStep('subscription_start_date',
        () => _metadataBox.delete('subscription_start_date'));
    await tryStep('subscription_auto_renew',
        () => _metadataBox.delete('subscription_auto_renew'));
    await tryStep('subscription_payment_method',
        () => _metadataBox.delete('subscription_payment_method'));
    await tryStep('qr_salt', () => _metadataBox.delete('qr_salt'));
    await tryStep('last_sync_time', () => _metadataBox.delete('last_sync_time'));

    // ⭐ مسح Tombstones وسجل المزامنة — وإلا أعيد رفعها للأبد على الحساب
    // الجديد بعد تبديل الحسابات على نفس الجهاز (permission denied متراكم)
    final tombstoneKeys = _metadataBox.keys
        .where((k) => k.toString().startsWith('pending_delete_'))
        .toList();
    for (final key in tombstoneKeys) {
      await tryStep('tombstone $key', () => _metadataBox.delete(key));
    }
    await tryStep('sync_log', () => _syncLogBox.clear());

    // ⭐ مسح بيانات الأعمال (المنتجات/المبيعات/الحركات) عند تسجيل الخروج
    // لمنع خلط بيانات الحسابات على نفس الجهاز
    await tryStep('products', deleteAllProducts);
    await tryStep('sales', deleteAllSales);
    await tryStep('movements', deleteAllMovements);
    await tryStep('suppliers', () => _suppliersBox.clear());
    await tryStep('purchases', () => _purchasesBox.clear());
    await tryStep('customers', () => _customersBox.clear());
    await tryStep('debt_transactions', () => _debtTransactionsBox.clear());
    _barcodeIndex.clear();
    _productsCache.invalidate();
    _salesCache.invalidate();
    invalidateCategoriesCache();
    _clearStatsCache();

    // ⭐ فحص نهائي: نتأكد أن الصناديق فارغة فعلاً، ونسجّل أي بقايا
    final leftovers = <String>[];
    if (_productsBox.isNotEmpty) leftovers.add('products=${_productsBox.length}');
    if (_salesBox.isNotEmpty) leftovers.add('sales=${_salesBox.length}');
    if (_movementsBox.isNotEmpty) {
      leftovers.add('movements=${_movementsBox.length}');
    }
    if (_suppliersBox.isNotEmpty) {
      leftovers.add('suppliers=${_suppliersBox.length}');
    }
    if (_purchasesBox.isNotEmpty) {
      leftovers.add('purchases=${_purchasesBox.length}');
    }
    if (_customersBox.isNotEmpty) leftovers.add('customers=${_customersBox.length}');
    if (_debtTransactionsBox.isNotEmpty) leftovers.add('debt_transactions=${_debtTransactionsBox.length}');
    if (_syncLogBox.isNotEmpty) leftovers.add('sync_log=${_syncLogBox.length}');
    if (_metadataBox.containsKey('user_id')) leftovers.add('user_id');
    if (_metadataBox.containsKey('subscription_end_date')) {
      leftovers.add('subscription_end_date');
    }
    if (_metadataBox.containsKey('qr_salt')) leftovers.add('qr_salt');

    if (failures.isNotEmpty || leftovers.isNotEmpty) {
      AppConfig.logError(
          '⚠️ clearUserData incomplete — failures: ${failures.join(', ')}; '
          'leftovers: ${leftovers.join(', ')}');
    } else {
      AppConfig.log('✅ clearUserData: all boxes verified empty');
    }
  }

  Future<void> saveSubscriptionEndDate(DateTime endDate) async {
    await _metadataBox.put('subscription_end_date', endDate.toIso8601String());
  }

  DateTime? getSubscriptionEndDate() {
    final value = _metadataBox.get('subscription_end_date');
    if (value == null) return null;
    try {
      return DateTime.parse(value as String);
    } catch (e) {
      return null;
    }
  }

  Future<void> saveSubscriptionActive(bool isActive) async {
    await _metadataBox.put('subscription_active', isActive);
  }

  bool getSubscriptionActive() {
    return _metadataBox.get('subscription_active', defaultValue: false);
  }

  // ⭐ آخر مرة تم فيها التحقق من الاشتراك من السيرفر (لـ "إيجار" 48 ساعة
  // يُسمح خلالها بالاعتماد على Hive عند تعذر الاتصال — انظر C-2).
  Future<void> saveSubscriptionLastVerified(DateTime verifiedAt) async {
    await _metadataBox.put(
        'subscription_last_verified', verifiedAt.toIso8601String());
  }

  DateTime? getSubscriptionLastVerified() {
    final value = _metadataBox.get('subscription_last_verified');
    if (value == null) return null;
    try {
      return DateTime.parse(value as String);
    } catch (e) {
      return null;
    }
  }

  // ⭐ لقطة الاشتراك الكاملة: النوع وتاريخ البدء والتجديد التلقائي وطريقة
  // الدفع. كان المخزن يحفظ تاريخ الانتهاء والحالة فقط، فكان مسار الاحتياط
  // (تعذر الوصول للسيرفر) يخترع plan_type = 'trial' لكل مشترك — ويُخفي
  // تاريخ البدء والتجديد التلقائي حتى عند نجاح الاستعلام.
  Future<void> saveSubscriptionSnapshot({
    String? planType,
    DateTime? startDate,
    bool? autoRenew,
    String? paymentMethod,
  }) async {
    if (planType != null) {
      await _metadataBox.put('subscription_plan_type', planType);
    }
    if (startDate != null) {
      await _metadataBox.put(
          'subscription_start_date', startDate.toIso8601String());
    }
    if (autoRenew != null) {
      await _metadataBox.put('subscription_auto_renew', autoRenew);
    }
    if (paymentMethod != null) {
      await _metadataBox.put('subscription_payment_method', paymentMethod);
    }
  }

  /// نوع الخطة المحفوظ، أو null إذا لم يُقرأ اشتراك من السيرفر بعد.
  /// null يعني «غير معروف» — لا يُستبدل بـ 'trial' أبداً.
  String? getSubscriptionPlanType() {
    final value = _metadataBox.get('subscription_plan_type');
    return value is String && value.isNotEmpty ? value : null;
  }

  DateTime? getSubscriptionStartDate() {
    final value = _metadataBox.get('subscription_start_date');
    if (value == null) return null;
    try {
      return DateTime.parse(value as String);
    } catch (e) {
      return null;
    }
  }

  bool getSubscriptionAutoRenew() {
    return _metadataBox.get('subscription_auto_renew', defaultValue: false)
        as bool;
  }

  String? getSubscriptionPaymentMethod() {
    final value = _metadataBox.get('subscription_payment_method');
    return value is String && value.isNotEmpty ? value : null;
  }

  // ⭐ ملح QR الدخول (اتفاق مع شاشة QR): يُخزَّن محلياً ويُمسح عند الخروج
  Future<void> saveQrSalt(String salt) async {
    await _metadataBox.put('qr_salt', salt);
  }

  String? getQrSalt() {
    final value = _metadataBox.get('qr_salt');
    return value is String ? value : null;
  }

  Future<void> saveLastSyncTime(DateTime? time) async {
    if (time == null) {
      await _metadataBox.delete('last_sync_time');
    } else {
      await _metadataBox.put('last_sync_time', time.toIso8601String());
    }
  }

  DateTime? getLastSyncTime() {
    final value = _metadataBox.get('last_sync_time');
    if (value == null) return null;
    try {
      return DateTime.parse(value as String);
    } catch (e) {
      return null;
    }
  }

  // ==================== Product Methods ====================

  int getProductCount() {
    return _productsBox.length;
  }

  List<Product> getProductsPaginated({int offset = 0, int limit = 50}) {
    // ⭐ ترتيب القائمة كاملة أولاً ثم أخذ الشريحة (منع تكرار/إغفال بين الصفحات)
    final all = _productsCache.getAllSorted();
    if (offset >= all.length) return [];
    final end = (offset + limit > all.length) ? all.length : offset + limit;
    return all.sublist(offset, end);
  }

  // ⭐ كل المنتجات مرتبة (للإحصائيات/الشاشات الكبيرة) — تُقرأ مرة واحدة ثم تُخزن
  List<Product> getAllProducts() {
    return _productsCache.getAllSorted();
  }

  // ⭐ الحصول على المنتجات غير المتزامنة (isSynced = false)
  List<Product> getUnsyncedProducts() {
    return _productsBox.values.where((product) => !product.isSynced).toList();
  }

  Product? getProductById(String id) {
    try {
      return _productsBox.get(id);
    } catch (e) {
      return null;
    }
  }

  // Barcode index helper methods
  Future<void> _buildBarcodeIndex() async {
    _barcodeIndex.clear();
    for (var product in _productsBox.values) {
      final barcode = product.barcode;
      if (barcode != null && barcode.isNotEmpty) {
        _barcodeIndex[barcode] = product.id;
      }
    }
  }

  void _addProductToBarcodeIndex(Product product) {
    final barcode = product.barcode;
    if (barcode != null && barcode.isNotEmpty) {
      _barcodeIndex[barcode] = product.id;
    }
  }

  void _removeProductFromBarcodeIndex(String productId) {
    _barcodeIndex.removeWhere((key, value) => value == productId);
  }

  Product? getProductByBarcode(String barcode) {
    if (barcode.isEmpty) return null;
    final productId = _barcodeIndex[barcode];
    if (productId == null) return null;
    return _productsBox.get(productId);
  }

  bool productExists(String id) {
    return _productsBox.containsKey(id);
  }

  // ⭐ إضافة منتج مع تعيين isSynced = false
  Future<void> addProductWithId({
    required String id,
    required String name,
    required String category,
    required double price,
    required int quantity,
    String? description,
    String? barcode,
    required String userId,
    int minStockLevel = 10,
    bool isSynced = false,
    double? costPrice,
  }) async {
    final product = Product(
      id: id,
      name: name,
      category: category,
      price: price,
      quantity: quantity,
      description: description,
      barcode: barcode,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isSynced: isSynced,
      userId: userId,
      minStockLevel: minStockLevel,
      costPrice: costPrice,
    );
    await _productsBox.put(product.id, product);
    _addProductToBarcodeIndex(product);
    _clearStatsCache();
    _productsCache.invalidate();
    invalidateCategoriesCache();
  }

  // ⭐ إضافة منتج مع تعيين isSynced = false
  Future<void> addProduct({
    required String name,
    required String category,
    required double price,
    required int quantity,
    String? description,
    String? barcode,
    required String userId,
    int minStockLevel = 10,
    bool isSynced = false,
    double? costPrice,
  }) async {
    final product = Product(
      id: _uuid.v4(),
      name: name,
      category: category,
      price: price,
      quantity: quantity,
      description: description,
      barcode: barcode,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isSynced: isSynced,
      userId: userId,
      minStockLevel: minStockLevel,
      costPrice: costPrice,
    );
    await _productsBox.put(product.id, product);
    _addProductToBarcodeIndex(product);
    _clearStatsCache();
    _productsCache.invalidate();
    invalidateCategoriesCache();
  }

  // ⭐ تحديث منتج مع تعيين isSynced = false
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
    final product = _productsBox.get(id);
    if (product != null) {
      final oldBarcode = product.barcode;
      if (oldBarcode != null && oldBarcode.isNotEmpty) {
        _barcodeIndex.remove(oldBarcode);
      }

      product.name = name;
      product.category = category;
      product.price = price;
      product.quantity = quantity;
      product.description = description;
      product.barcode = barcode;
      if (minStockLevel != null) {
        product.minStockLevel = minStockLevel;
      }
      product.costPrice = costPrice;
      product.updatedAt = DateTime.now();
      product.isSynced = false; // ⭐ تعيين isSynced = false عند التحديث
      await product.save();

      _addProductToBarcodeIndex(product);
      _clearStatsCache();
      _productsCache.invalidate();
      invalidateCategoriesCache();
    }
  }

  // ⭐ تحديث تكلفة الشراء فقط (بعد عملية شراء) مع تعيين isSynced = false
  Future<void> updateProductCost(String id, double costPrice) async {
    final product = _productsBox.get(id);
    if (product != null) {
      product.costPrice = costPrice;
      product.updatedAt = DateTime.now();
      product.isSynced = false;
      await product.save();
      _clearStatsCache();
      _productsCache.invalidate();
    }
  }

  // ⭐ تحديث الكمية مع تعيين isSynced = false
  Future<void> updateQuantity(String id, int newQuantity) async {
    final product = _productsBox.get(id);
    if (product != null) {
      product.quantity = newQuantity;
      product.updatedAt = DateTime.now();
      product.isSynced = false; // ⭐ تعيين isSynced = false عند التحديث
      await product.save();
      _clearStatsCache();
      _productsCache.invalidate();
    }
  }

  Future<void> deleteProduct(String id) async {
    final product = _productsBox.get(id);
    if (product != null) {
      _removeProductFromBarcodeIndex(id);
    }
    await _productsBox.delete(id);
    _clearStatsCache();
    _productsCache.invalidate();
    invalidateCategoriesCache();
  }

  Future<void> deleteAllProducts() async {
    await _productsBox.clear();
    _barcodeIndex.clear();
    _clearStatsCache();
    _productsCache.invalidate();
    invalidateCategoriesCache();
    AppConfig.log('✅ All products deleted from Hive');
  }

  List<Product> getLowStockProducts({int threshold = 10}) {
    return _productsBox.values
        .where((product) => product.quantity <= threshold)
        .toList();
  }

  List<String> getCategories() {
    // Check cache first
    if (_cachedCategories != null && _categoriesCacheTime != null) {
      final elapsed = DateTime.now().difference(_categoriesCacheTime!);
      if (elapsed < _categoriesCacheDuration) {
        AppConfig.log('📦 Returning cached categories (${_cachedCategories!.length})');
        return _cachedCategories!;
      }
    }

    final categories = <String>{};
    for (var product in _productsBox.values) {
      categories.add(product.category);
    }
    final sortedCategories = categories.toList()..sort();
    
    // Update cache
    _cachedCategories = sortedCategories;
    _categoriesCacheTime = DateTime.now();
    
    return sortedCategories;
  }

  /// Set categories cache (called after fetching from Firebase)
  void setCategoriesCache(List<String> categories) {
    _cachedCategories = categories..sort();
    _categoriesCacheTime = DateTime.now();
  }

  /// Invalidate categories cache (called when products change)
  void invalidateCategoriesCache() {
    _cachedCategories = null;
    _categoriesCacheTime = null;
  }

  Map<String, dynamic> getInventoryStats() {
    final products = _productsBox.values.toList();
    final totalProducts = products.length;
    final totalQuantity = products.fold<int>(0, (sum, p) => sum + p.quantity);
    final totalValue =
        products.fold<double>(0, (sum, p) => sum + (p.price * p.quantity));
    final lowStock = products
        .where((p) => p.quantity <= p.minStockLevel && p.quantity > 0)
        .length;
    final outOfStock = products.where((p) => p.quantity == 0).length;
    return {
      'totalProducts': totalProducts,
      'totalQuantity': totalQuantity,
      'totalValue': totalValue,
      'lowStock': lowStock,
      'outOfStock': outOfStock,
    };
  }

  // ==================== Sale Methods ====================

  int getSaleCount() {
    return _salesBox.length;
  }

  List<Sale> getSalesPaginated({int offset = 0, int limit = 50}) {
    // ⭐ تمر عبر الكاش المرتب (نفس مصدر getAllSales) — قراءة وفرز مرة واحدة
    final all = _salesCache.getAllSorted();
    if (offset >= all.length) return [];
    final end = (offset + limit > all.length) ? all.length : offset + limit;
    return all.sublist(offset, end);
  }

  // ⭐ كل المبيعات مرتبة (للإحصائيات/الشاشات الكبيرة) — تُقرأ مرة واحدة ثم تُخزن
  List<Sale> getAllSales() {
    return _salesCache.getAllSorted();
  }

  // ⭐ الحصول على المبيعات غير المتزامنة (isSynced = false)
  List<Sale> getUnsyncedSales() {
    return _salesBox.values.where((sale) => !sale.isSynced).toList();
  }

  List<Sale> getTodaySales() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _salesBox.values
        .where((sale) =>
            sale.createdAt.isAfter(startOfDay) ||
            sale.createdAt.isAtSameMomentAs(startOfDay))
        .where((sale) => sale.createdAt.isBefore(endOfDay))
        .toList();
  }

  List<Sale> getYesterdaySales() {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final startOfYesterday =
        DateTime(yesterday.year, yesterday.month, yesterday.day);
    final endOfYesterday = DateTime(today.year, today.month, today.day);
    return _salesBox.values
        .where((sale) =>
            sale.createdAt.isAfter(startOfYesterday) ||
            sale.createdAt.isAtSameMomentAs(startOfYesterday))
        .where((sale) => sale.createdAt.isBefore(endOfYesterday))
        .toList();
  }

  List<Sale> getWeeklySales() {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    return _salesBox.values
        .where((sale) => sale.createdAt.isAfter(weekAgo))
        .toList();
  }

  double getTodayRevenue() {
    final todaySales = getTodaySales();
    return todaySales.fold(0.0, (sum, sale) => sum + sale.total);
  }

  double getYesterdayRevenue() {
    final yesterdaySales = getYesterdaySales();
    return yesterdaySales.fold(0.0, (sum, sale) => sum + sale.total);
  }

  int getTodayTransactionCount() {
    return getTodaySales().length;
  }

  bool saleExists(String id) {
    return _salesBox.containsKey(id);
  }

  Sale? getSaleById(String id) {
    return _salesBox.get(id);
  }

  // ⭐ إضافة مبيعة مع تعيين isSynced = false
  Future<Sale> addSaleWithId({
    required String id,
    required List<SaleItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required String paymentMethod,
    required String userId,
    String? customerName,
    String? customerPhone,
    String? customerId,
    String saleType = 'sale',
    String? originalSaleId,
    DateTime? createdAt,
    List<SaleItem>? returnedItems,
    double? returnTotal,
    bool isFullyReturned = false,
    bool isSynced = false,
  }) async {
    final sale = Sale(
      id: id,
      items: items,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: total,
      paymentMethod: paymentMethod,
      isSynced: isSynced,
      userId: userId,
      customerName: customerName,
      customerPhone: customerPhone,
      customerId: customerId,
      saleType: saleType,
      originalSaleId: originalSaleId,
      returnedItems: returnedItems,
      returnTotal: returnTotal,
      isFullyReturned: isFullyReturned,
      createdAt: createdAt ?? DateTime.now(),
    );
    await _salesBox.put(sale.id, sale);
    _clearStatsCache();
    _salesCache.invalidate();
    return sale;
  }

  // ⭐ إضافة مبيعة مع تعيين isSynced = false
  Future<Sale> addSale({
    required List<SaleItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required String paymentMethod,
    required String userId,
    String? customerName,
    String? customerPhone,
    String? customerId,
    String saleType = 'sale',
    String? originalSaleId,
    List<SaleItem>? returnedItems,
    double? returnTotal,
    bool isFullyReturned = false,
    bool isSynced = false,
  }) async {
    final sale = Sale(
      id: _uuid.v4(),
      items: items,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: total,
      paymentMethod: paymentMethod,
      isSynced: isSynced,
      userId: userId,
      customerName: customerName,
      customerPhone: customerPhone,
      customerId: customerId,
      saleType: saleType,
      originalSaleId: originalSaleId,
      returnedItems: returnedItems,
      returnTotal: returnTotal,
      isFullyReturned: isFullyReturned,
    );
    await _salesBox.put(sale.id, sale);
    _clearStatsCache();
    _salesCache.invalidate();
    return sale;
  }

  // ⭐ تحديث مبيعة مع إرجاع مع تعيين isSynced = false
  // ملاحظة: حالة الإرجاع الكامل تُحسب من الكميات المدمجة هنا (مصدر الحقيقة
  // المحلي)؛ ممرّرات الواجهة لا تحتاج لحسابها مسبقاً.
  Future<Sale> updateSaleWithReturn({
    required String saleId,
    required List<SaleItem> returnedItems,
    required double returnTotal,
  }) async {
    final sale = _salesBox.get(saleId);
    if (sale == null) {
      throw Exception(LocalizationHelper.salesHistorySaleNotFound);
    }

    if (sale.isReturn) {
      throw Exception(LocalizationHelper.salesHistoryCannotReturnFromReturn);
    }

    if (sale.isFullyReturned) {
      throw Exception(LocalizationHelper.salesHistoryAlreadyFullyReturned);
    }

    final existingReturned = sale.returnedItems ?? [];
    final allReturnedItems = [...existingReturned, ...returnedItems];

    final Map<String, SaleItem> mergedReturned = {};
    for (var item in allReturnedItems) {
      if (mergedReturned.containsKey(item.productId)) {
        final existing = mergedReturned[item.productId]!;
        mergedReturned[item.productId] = SaleItem(
          id: existing.id,
          productId: existing.productId,
          productName: existing.productName,
          price: existing.price,
          quantity: existing.quantity + item.quantity,
          subtotal: existing.subtotal + item.subtotal,
        );
      } else {
        mergedReturned[item.productId] = item;
      }
    }

    final newReturnTotal = (sale.returnTotal ?? 0.0) + returnTotal;

    final totalOriginalQuantity =
        sale.items.fold(0, (sum, item) => sum + item.quantity);
    final totalReturnedQuantity =
        mergedReturned.values.fold(0, (sum, item) => sum + item.quantity);
    final fullyReturned = totalReturnedQuantity >= totalOriginalQuantity;

    final updatedSale = Sale(
      id: sale.id,
      items: sale.items,
      subtotal: sale.subtotal,
      discount: sale.discount,
      tax: sale.tax,
      total: sale.total,
      paymentMethod: sale.paymentMethod,
      createdAt: sale.createdAt,
      isSynced: false, // ⭐ تعيين isSynced = false عند التحديث
      userId: sale.userId,
      customerName: sale.customerName,
      customerPhone: sale.customerPhone,
      customerId: sale.customerId,
      saleType: sale.saleType,
      originalSaleId: sale.originalSaleId,
      returnedItems: mergedReturned.values.toList(),
      returnTotal: newReturnTotal,
      isFullyReturned: fullyReturned,
    );

    await _salesBox.put(updatedSale.id, updatedSale);
    _clearStatsCache();
    _salesCache.invalidate();
    return updatedSale;
  }

  // ⭐ تعيين المبيعة كمتزامنة
  Future<void> markSaleAsSynced(String id) async {
    final sale = _salesBox.get(id);
    if (sale != null) {
      sale.isSynced = true;
      await sale.save();
    }
  }

  // ⭐ تعيين المنتج كمتزامن
  Future<void> markProductAsSynced(String id) async {
    final product = _productsBox.get(id);
    if (product != null) {
      product.isSynced = true;
      await product.save();
    }
  }

  Future<void> deleteSale(String id) async {
    await _salesBox.delete(id);
    _clearStatsCache();
    _salesCache.invalidate();
  }

  Future<void> deleteAllSales() async {
    await _salesBox.clear();
    _clearStatsCache();
    _salesCache.invalidate();
    AppConfig.log('✅ All sales deleted from Hive');
  }

  // ==================== Inventory Movement Methods ====================

  InventoryMovement? getMovementById(String id) {
    try {
      return _movementsBox.get(id);
    } catch (e) {
      return null;
    }
  }

  List<InventoryMovement> getUnsyncedMovements() {
    return _movementsBox.values.where((m) => !m.isSynced).toList();
  }

  List<InventoryMovement> getMovementsByProduct(String productId) {
    return _movementsBox.values.where((m) => m.productId == productId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<InventoryMovement> getMovementsByType(MovementType type) {
    return _movementsBox.values.where((m) => m.type == type).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<InventoryMovement> getMovementsByDateRange(
      DateTime start, DateTime end) {
    return _movementsBox.values
        .where((m) => m.createdAt.isAfter(start) && m.createdAt.isBefore(end))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<InventoryMovement> addMovement({
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
    bool isSynced = false,
  }) async {
    final movement = InventoryMovement(
      id: _uuid.v4(),
      productId: productId,
      productName: productName,
      type: type,
      quantity: quantity,
      price: price,
      total: total,
      referenceId: referenceId,
      referenceNumber: referenceNumber,
      note: note,
      userId: userId,
      status: status,
      isSynced: isSynced,
      customerName: customerName,
      supplierName: supplierName,
    );
    await _movementsBox.put(movement.id, movement);
    _clearStatsCache();
    return movement;
  }

  Future<InventoryMovement> addMovementWithId({
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
    bool isSynced = true,
    String? customerName,
    String? supplierName,
    DateTime? createdAt,
  }) async {
    final movement = InventoryMovement(
      id: id,
      productId: productId,
      productName: productName,
      type: type,
      quantity: quantity,
      price: price,
      total: total,
      referenceId: referenceId,
      referenceNumber: referenceNumber,
      note: note,
      createdAt: createdAt,
      userId: userId,
      status: status,
      isSynced: isSynced,
      customerName: customerName,
      supplierName: supplierName,
    );
    await _movementsBox.put(movement.id, movement);
    _clearStatsCache();
    return movement;
  }

  Future<void> updateMovementStatus(String id, MovementStatus status) async {
    final movement = _movementsBox.get(id);
    if (movement != null) {
      movement.status = status;
      movement.isSynced = false;
      await movement.save();
      _clearStatsCache();
    }
  }

  Future<void> markMovementAsSynced(String id) async {
    final movement = _movementsBox.get(id);
    if (movement != null) {
      movement.isSynced = true;
      await movement.save();
    }
  }

  Future<void> deleteMovement(String id) async {
    await _movementsBox.delete(id);
    _clearStatsCache();
  }

  Future<void> deleteAllMovements() async {
    await _movementsBox.clear();
    _clearStatsCache();
    AppConfig.log('✅ All movements deleted from Hive');
  }

  // ==================== Supplier Methods ====================

  List<Supplier> getAllSuppliers() {
    return _suppliersBox.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Supplier? getSupplierById(String id) {
    try {
      return _suppliersBox.get(id);
    } catch (e) {
      return null;
    }
  }

  bool supplierExists(String id) => _suppliersBox.containsKey(id);

  List<Supplier> getUnsyncedSuppliers() {
    return _suppliersBox.values.where((s) => !s.isSynced).toList();
  }

  Future<void> addSupplierWithId({
    required String id,
    required String name,
    String? phone,
    String? address,
    String? notes,
    required String userId,
    bool isSynced = false,
  }) async {
    final supplier = Supplier(
      id: id,
      name: name,
      phone: phone,
      address: address,
      notes: notes,
      userId: userId,
      isSynced: isSynced,
    );
    await _suppliersBox.put(supplier.id, supplier);
  }

  Future<void> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? address,
    String? notes,
  }) async {
    final supplier = _suppliersBox.get(id);
    if (supplier != null) {
      supplier.name = name;
      supplier.phone = phone;
      supplier.address = address;
      supplier.notes = notes;
      supplier.updatedAt = DateTime.now();
      supplier.isSynced = false;
      await supplier.save();
    }
  }

  Future<void> deleteSupplierLocal(String id) async {
    await _suppliersBox.delete(id);
  }

  Future<void> markSupplierAsSynced(String id) async {
    final supplier = _suppliersBox.get(id);
    if (supplier != null) {
      supplier.isSynced = true;
      await supplier.save();
    }
  }

  // ==================== Purchase Methods ====================

  int getPurchaseCount() => _purchasesBox.length;

  List<Purchase> getAllPurchases() {
    return _purchasesBox.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<Purchase> getPurchasesBySupplier(String supplierId) {
    return _purchasesBox.values
        .where((p) => p.supplierId == supplierId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  // المرتجعات المرتبطة بعملية شراء أصلية
  List<Purchase> getReturnPurchasesFor(String originalPurchaseId) {
    return _purchasesBox.values
        .where((p) =>
            p.isReturn && p.originalPurchaseId == originalPurchaseId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Purchase? getPurchaseById(String id) {
    try {
      return _purchasesBox.get(id);
    } catch (e) {
      return null;
    }
  }

  List<Purchase> getUnsyncedPurchases() {
    return _purchasesBox.values.where((p) => !p.isSynced).toList();
  }

  Future<Purchase> addPurchaseWithId({
    required String id,
    required List<PurchaseItem> items,
    required String supplierId,
    required String supplierName,
    required double total,
    String? note,
    String purchaseType = 'purchase',
    String? originalPurchaseId,
    required String userId,
    bool isSynced = false,
    DateTime? createdAt,
    String? invoiceNumber,
    List<PurchaseItem>? returnedItems,
    double? returnTotal,
    bool isFullyReturned = false,
    DateTime? updatedAt,
  }) async {
    final purchase = Purchase(
      id: id,
      items: items,
      supplierId: supplierId,
      supplierName: supplierName,
      total: total,
      note: note,
      purchaseType: purchaseType,
      originalPurchaseId: originalPurchaseId,
      userId: userId,
      isSynced: isSynced,
      createdAt: createdAt,
      invoiceNumber: invoiceNumber,
      returnedItems: returnedItems,
      returnTotal: returnTotal,
      isFullyReturned: isFullyReturned,
      updatedAt: updatedAt,
    );
    await _purchasesBox.put(purchase.id, purchase);
    return purchase;
  }

  // ⭐ دمج المرتجع داخل نفس سجل الشراء الأصلي (نمط updateSaleWithReturn):
  // يدمج returnedItems، يجمع returnTotal، يحسب isFullyReturned، ويعيد الكتابة
  // مع isSynced=false وupdatedAt جديد.
  Future<Purchase> updatePurchaseWithReturn({
    required String purchaseId,
    required List<PurchaseItem> returnedItems,
    required double returnTotal,
    bool? isFullyReturnedOverride,
  }) async {
    final purchase = _purchasesBox.get(purchaseId);
    if (purchase == null) {
      throw Exception(LocalizationHelper.purchasesPurchaseNotFound);
    }
    if (purchase.isReturn) {
      throw Exception(LocalizationHelper.purchasesCannotReturnFromReturn);
    }
    if (purchase.isFullyReturned) {
      throw Exception(
          LocalizationHelper.purchasesPurchaseAlreadyFullyReturned);
    }

    final merged = <String, PurchaseItem>{};
    // ⭐ نوع صريح للقائمة الفارغة: بدونه يصبح item ضمنياً dynamic
    // والجمع يعطي num (فخ استنتاج الأنواع في الانتشار المضمّن داخل for)
    for (final item
        in [...(purchase.returnedItems ?? const <PurchaseItem>[]), ...returnedItems]) {
      final existing = merged[item.productId];
      if (existing != null) {
        merged[item.productId] = PurchaseItem(
          id: existing.id,
          productId: existing.productId,
          productName: existing.productName,
          costPrice: existing.costPrice,
          quantity: existing.quantity + item.quantity,
          subtotal: existing.subtotal + item.subtotal,
        );
      } else {
        merged[item.productId] = item;
      }
    }

    final newReturnTotal = (purchase.returnTotal ?? 0.0) + returnTotal;

    final totalOriginal =
        purchase.items.fold<int>(0, (sum, i) => sum + i.quantity);
    final totalReturned =
        merged.values.fold<int>(0, (sum, i) => sum + i.quantity);
    final fully = isFullyReturnedOverride ?? totalReturned >= totalOriginal;

    final updated = Purchase(
      id: purchase.id,
      items: purchase.items,
      supplierId: purchase.supplierId,
      supplierName: purchase.supplierName,
      total: purchase.total,
      note: purchase.note,
      purchaseType: purchase.purchaseType,
      originalPurchaseId: purchase.originalPurchaseId,
      userId: purchase.userId,
      isSynced: false,
      createdAt: purchase.createdAt,
      invoiceNumber: purchase.invoiceNumber,
      returnedItems: merged.values.toList(),
      returnTotal: newReturnTotal,
      isFullyReturned: fully,
      updatedAt: DateTime.now(),
    );
    await _purchasesBox.put(updated.id, updated);
    return updated;
  }

  // بحث بالفاتورة (رقم الفاتورة أو اسم المورد)
  List<Purchase> searchPurchases(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return getAllPurchases();
    return _purchasesBox.values
        .where((p) =>
            p.supplierName.toLowerCase().contains(q) ||
            (p.invoiceNumber ?? '').toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> deletePurchaseLocal(String id) async {
    await _purchasesBox.delete(id);
  }

  Future<void> markPurchaseAsSynced(String id) async {
    final purchase = _purchasesBox.get(id);
    if (purchase != null) {
      purchase.isSynced = true;
      await purchase.save();
    }
  }

  // ==================== Customer Methods ====================

  List<Customer> getAllCustomers() {
    return _customersBox.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Customer? getCustomerById(String id) {
    try { return _customersBox.get(id); } catch (e) { return null; }
  }

  bool customerExists(String id) => _customersBox.containsKey(id);

  List<Customer> getUnsyncedCustomers() {
    return _customersBox.values.where((c) => !c.isSynced).toList();
  }

  Future<void> addCustomerWithId({
    required String id, required String name, String? phone,
    String? address, String? notes, required String userId, bool isSynced = false,
    DateTime? createdAt, DateTime? updatedAt,
  }) async {
    final customer = Customer(
      id: id, name: name, phone: phone, address: address, notes: notes,
      userId: userId, isSynced: isSynced,
      createdAt: createdAt, updatedAt: updatedAt,
    );
    await _customersBox.put(customer.id, customer);
  }

  Future<void> updateCustomer({
    required String id, required String name, String? phone,
    String? address, String? notes,
  }) async {
    final customer = _customersBox.get(id);
    if (customer != null) {
      customer.name = name;
      customer.phone = phone;
      customer.address = address;
      customer.notes = notes;
      customer.updatedAt = DateTime.now();
      customer.isSynced = false;
      await customer.save();
    }
  }

  Future<void> markCustomerAsSynced(String id) async {
    final customer = _customersBox.get(id);
    if (customer != null) {
      customer.isSynced = true;
      await customer.save();
    }
  }

  Future<void> deleteCustomerLocal(String id) async {
    await _customersBox.delete(id);
  }

  Future<void> deleteAllCustomers() async {
    await _customersBox.clear();
    _customerDebtIndex.clear();
    _ledgerCache.clear();
  }

  // ==================== Debt Transaction Methods ====================

  List<DebtTransaction> getAllDebtTransactions() {
    return _debtTransactionsBox.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  DebtTransaction? getDebtTransactionById(String id) {
    try { return _debtTransactionsBox.get(id); } catch (e) { return null; }
  }

  List<DebtTransaction> getDebtTransactionsByCustomer(String customerId) {
    final ids = _customerDebtIndex[customerId];
    if (ids == null || ids.isEmpty) return [];
    return ids.map((id) => _debtTransactionsBox.get(id))
        .whereType<DebtTransaction>()
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  List<DebtTransaction> getDebtTransactionsBySale(String saleId) {
    return _debtTransactionsBox.values
        .where((t) => t.saleId == saleId)
        .toList();
  }

  List<DebtTransaction> getUnsyncedDebtTransactions() {
    return _debtTransactionsBox.values.where((t) => !t.isSynced).toList();
  }

  Future<void> addDebtTransactionWithId({
    required String id, required String customerId,
    required DebtTransactionType type, required double amount,
    String? saleId, String? note, required String userId,
    bool isSynced = false,
    DateTime? createdAt, DateTime? updatedAt,
  }) async {
    final tx = DebtTransaction(
      id: id, customerId: customerId, type: type, amount: amount,
      saleId: saleId, note: note, userId: userId, isSynced: isSynced,
      createdAt: createdAt, updatedAt: updatedAt,
    );
    await _debtTransactionsBox.put(tx.id, tx);
    _addDebtToIndex(customerId, id);
    _ledgerCache.remove(customerId);
  }

  Future<void> markDebtTransactionAsSynced(String id) async {
    final tx = _debtTransactionsBox.get(id);
    if (tx != null) {
      tx.isSynced = true;
      await tx.save();
    }
  }

  Future<void> deleteDebtTransactionLocal(String id) async {
    final tx = _debtTransactionsBox.get(id);
    if (tx != null) {
      _removeDebtFromIndex(tx.customerId, id);
      await _debtTransactionsBox.delete(id);
      _ledgerCache.remove(tx.customerId);
    }
  }

  Future<void> deleteAllDebtTransactions() async {
    await _debtTransactionsBox.clear();
    _customerDebtIndex.clear();
    _ledgerCache.clear();
  }

  // ⭐ Index helpers
  void _buildCustomerDebtIndex() {
    _customerDebtIndex.clear();
    for (final tx in _debtTransactionsBox.values) {
      _customerDebtIndex.putIfAbsent(tx.customerId, () => []).add(tx.id);
    }
  }

  void _addDebtToIndex(String customerId, String txId) {
    _customerDebtIndex.putIfAbsent(customerId, () => []).add(txId);
  }

  void _removeDebtFromIndex(String customerId, String txId) {
    final list = _customerDebtIndex[customerId];
    if (list != null) {
      list.remove(txId);
      if (list.isEmpty) _customerDebtIndex.remove(customerId);
    }
  }

  // ⭐ Ledger cache
  CustomerLedger getCustomerLedger(String customerId) {
    if (_ledgerCache.containsKey(customerId)) {
      return _ledgerCache[customerId]!;
    }
    final rows = getDebtTransactionsByCustomer(customerId);
    final ledger = buildCustomerLedger(rows);
    _ledgerCache[customerId] = ledger;
    return ledger;
  }

  // ==================== Chart Data Methods ====================

  Map<String, double> getWeeklySalesData() {
    final weeklySales = getWeeklySales();
    final Map<String, double> dailyTotals = {};
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    for (var day in days) {
      dailyTotals[day] = 0.0;
    }
    for (var sale in weeklySales) {
      final dayName = _getDayName(sale.createdAt.weekday);
      dailyTotals[dayName] = (dailyTotals[dayName] ?? 0.0) + sale.total;
    }
    return dailyTotals;
  }

  Map<String, double> getMonthlySalesData() {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final monthlySales = _salesBox.values
        .where((sale) =>
            sale.createdAt.isAfter(thirtyDaysAgo) &&
            sale.createdAt.isBefore(now))
        .toList();
    final Map<String, double> dailyTotals = {};

    for (var i = 0; i < 30; i++) {
      final date = thirtyDaysAgo.add(Duration(days: i + 1));
      dailyTotals['${date.day}/${date.month}'] = 0.0;
    }

    for (var sale in monthlySales) {
      final key = '${sale.createdAt.day}/${sale.createdAt.month}';
      dailyTotals[key] = (dailyTotals[key] ?? 0.0) + sale.total;
    }

    return dailyTotals;
  }

  Map<String, double> getYearlySalesData() {
    final now = DateTime.now();
    final twelveMonthsAgo = DateTime(now.year - 1, now.month, 1);
    final yearlySales = _salesBox.values
        .where((sale) => sale.createdAt.isAfter(twelveMonthsAgo))
        .toList();
    final Map<String, double> monthlyTotals = {};
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    for (var i = 11; i >= 0; i--) {
      var monthIndex = (now.month - 1 - i) % 12;
      if (monthIndex < 0) monthIndex += 12;
      monthlyTotals[months[monthIndex]] = 0.0;
    }

    for (var sale in yearlySales) {
      final month = months[sale.createdAt.month - 1];
      monthlyTotals[month] = (monthlyTotals[month] ?? 0.0) + sale.total;
    }

    return monthlyTotals;
  }

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  Map<String, dynamic> getAllStats() {
    if (_cachedStats != null && _statsCacheTime != null) {
      final elapsed = DateTime.now().difference(_statsCacheTime!);
      if (elapsed < _statsCacheDuration) {
        return _cachedStats!;
      }
    }

    final todaySales = getTodaySales();
    final todayRevenue = todaySales.fold(0.0, (sum, sale) => sum + sale.total);
    final todayTransactions = todaySales.length;

    final inventoryStats = getInventoryStats();

    final weeklySalesData = getWeeklySalesData();
    double weeklyTotal = 0.0;
    int daysWithSales = 0;
    weeklySalesData.forEach((key, value) {
      if (value > 0) {
        weeklyTotal += value;
        daysWithSales++;
      }
    });
    final averageSales = daysWithSales > 0 ? weeklyTotal / daysWithSales : 0.0;

    final stats = {
      'todayRevenue': todayRevenue,
      'todayTransactions': todayTransactions,
      'totalProducts': inventoryStats['totalProducts'],
      'totalInventory': inventoryStats['totalQuantity'],
      'lowStock': inventoryStats['lowStock'],
      'outOfStock': inventoryStats['outOfStock'],
      'averageSales': averageSales,
    };

    _cachedStats = stats;
    _statsCacheTime = DateTime.now();

    return stats;
  }

  void _clearStatsCache() {
    _cachedStats = null;
    _statsCacheTime = null;
  }

  Future<void> closeBoxes() async {
    await _productsBox.close();
    await _salesBox.close();
    await _metadataBox.close();
    await _movementsBox.close();
    await _suppliersBox.close();
    await _purchasesBox.close();
    await _customersBox.close();
    await _debtTransactionsBox.close();
    await _syncLogBox.close();
  }
}
