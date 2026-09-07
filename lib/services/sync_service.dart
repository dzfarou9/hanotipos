// lib/services/sync_service.dart

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';
import '../models/product_model.dart';
import '../models/sale_model.dart';
import '../models/inventory_movement_model.dart';
import '../models/supplier_model.dart';
import '../models/purchase_model.dart';
import '../models/customer_model.dart';
import '../models/debt_transaction_model.dart';
import 'database_service.dart';
import 'firebase_service.dart';
import '../helpers/localization_helper.dart';
import '../helpers/quantity_format.dart';
import '../helpers/sync_policy.dart';
import '../helpers/suppliers_stock_policy.dart';

/// حالة المزامنة
enum SyncStatus {
  idle,
  syncing,
  success,
  error,
}

/// تقدم المزامنة
class SyncProgress {
  final int totalProducts;
  final int syncedProducts;
  final int totalSales;
  final int syncedSales;
  final int totalMovements;
  final int syncedMovements;
  final int conflicts;
  final String currentAction;
  final double progress;

  SyncProgress({
    this.totalProducts = 0,
    this.syncedProducts = 0,
    this.totalSales = 0,
    this.syncedSales = 0,
    this.totalMovements = 0,
    this.syncedMovements = 0,
    this.conflicts = 0,
    this.currentAction = '',
    this.progress = 0.0,
  });

  SyncProgress copyWith({
    int? totalProducts,
    int? syncedProducts,
    int? totalSales,
    int? syncedSales,
    int? totalMovements,
    int? syncedMovements,
    int? conflicts,
    String? currentAction,
    double? progress,
  }) {
    return SyncProgress(
      totalProducts: totalProducts ?? this.totalProducts,
      syncedProducts: syncedProducts ?? this.syncedProducts,
      totalSales: totalSales ?? this.totalSales,
      syncedSales: syncedSales ?? this.syncedSales,
      totalMovements: totalMovements ?? this.totalMovements,
      conflicts: conflicts ?? this.conflicts,
      currentAction: currentAction ?? this.currentAction,
      progress: progress ?? this.progress,
    );
  }
}

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final DatabaseService _db = DatabaseService.instance;
  final FirebaseService _firebase = FirebaseService();
  final Connectivity _connectivity = Connectivity();
  final Uuid _uuid = const Uuid();

  bool _isOnline = false;
  bool _isSyncing = false;
  bool _isInitialSyncDone = false;
  bool _isInitialized = false;

  DateTime? _lastFirebasePullAt;
  static const Duration _pullCooldown = Duration(minutes: 30);

  final ValueNotifier<SyncStatus> _syncStatusNotifier =
      ValueNotifier<SyncStatus>(SyncStatus.idle);
  ValueNotifier<SyncStatus> get syncStatusNotifier => _syncStatusNotifier;

  final ValueNotifier<SyncProgress> _syncProgressNotifier =
      ValueNotifier<SyncProgress>(SyncProgress());
  ValueNotifier<SyncProgress> get syncProgressNotifier => _syncProgressNotifier;

  final ValueNotifier<int> _dataChangeNotifier = ValueNotifier<int>(0);
  ValueNotifier<int> get dataChangeNotifier => _dataChangeNotifier;

  final List<Map<String, dynamic>> _syncErrors = [];
  List<Map<String, dynamic>> get syncErrors => List.unmodifiable(_syncErrors);

  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  bool get isInitialSyncDone => _isInitialSyncDone;

  // ⭐ إعادة ضبط حالة المزامنة عند تسجيل الخروج / تبديل الحساب،
  // حتى لا تُستعمل أعلام الحساب السابق (initialSyncDone / pull cooldown /
  // أخطاء متراكمة) على الحساب الجديد.
  void reset() {
    _isInitialSyncDone = false;
    _lastFirebasePullAt = null;
    _lastSuccessfulSync = null;
    _syncErrors.clear();
    _syncStatusNotifier.value = SyncStatus.idle;
    _syncProgressNotifier.value = SyncProgress();
  }

  // ⭐ Sync status details for UI indicator
  DateTime? _lastSuccessfulSync;
  DateTime? get lastSuccessfulSync => _lastSuccessfulSync;

  int get pendingSyncCount {
    final unsyncedProducts = _db.getUnsyncedProducts().length;
    final unsyncedSales = _db.getUnsyncedSales().length;
    final unsyncedMovements = _db.getUnsyncedMovements().length;
    final unsyncedSuppliers = _db.getUnsyncedSuppliers().length;
    final unsyncedPurchases = _db.getUnsyncedPurchases().length;
    final unsyncedCustomers = _db.getUnsyncedCustomers().length;
    final unsyncedDebtTxns = _db.getUnsyncedDebtTransactions().length;
    return unsyncedProducts + unsyncedSales + unsyncedMovements + unsyncedSuppliers + unsyncedPurchases + unsyncedCustomers + unsyncedDebtTxns;
  }

  // ==================== التهيئة ====================

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      _isOnline = await _checkConnectivity();

      _connectivity.onConnectivityChanged
          .listen((List<ConnectivityResult> results) {
        _handleConnectivityChange(results);
      });

      _isInitialized = true;

      try {
        await _firebase.init();
        AppConfig.log('✅ FirebaseService initialized in SyncService');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to init FirebaseService', e);
      }

      final userId = _db.getUserId();
      AppConfig.log('📝 Hive userId: ${userId ?? 'none'}');

      if (_isOnline && userId != null && _firebase.currentUser != null) {
        AppConfig.log('===== SyncService: Performing initial sync =====');
        await syncNow();
      } else {
        AppConfig.log('===== SyncService: Sync skipped =====');
        AppConfig.log('  - isOnline: $_isOnline');
        AppConfig.log('  - userId: $userId');
        AppConfig.log('  - firebaseUser: ${_firebase.currentUser?.uid ?? 'none'}');
      }

      AppConfig.log('===== SyncService initialized =====');
    } catch (e) {
      AppConfig.logError('===== SyncService init error =====', e);
      _isInitialized = true;
    }
  }

  Future<bool> _checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity().timeout(
            const Duration(seconds: 2),
            onTimeout: () => [ConnectivityResult.none],
          );
      return result.any((r) =>
          r != ConnectivityResult.none && r != ConnectivityResult.bluetooth);
    } catch (e) {
      return false;
    }
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    _isOnline = results.any((r) =>
        r != ConnectivityResult.none && r != ConnectivityResult.bluetooth);
    if (_isOnline && !wasOnline) {
      final userId = _db.getUserId();
      if (userId != null && _firebase.currentUser != null) {
        AppConfig.log('===== Connectivity restored, syncing... =====');
        syncNow();
      }
    }
  }

  // ==================== المزامنة الرئيسية (Offline First) ====================

  Future<void> syncNow({bool fullSync = false}) async {
    AppConfig.log('===== ===== ===== syncNow() called =====');
    AppConfig.log('  - fullSync: $fullSync');
    AppConfig.log('  - isOnline: $_isOnline');
    AppConfig.log('  - isSyncing: $_isSyncing');
    AppConfig.log('  - userId: ${_db.getUserId() ?? 'none'}');
    AppConfig.log('  - firebaseUser: ${_firebase.currentUser?.uid ?? 'none'}');

    if (!_isOnline) {
      AppConfig.log('⚠️ No internet connection, sync deferred.');
      _syncStatusNotifier.value = SyncStatus.idle;
      _syncErrors.add({
        'message': LocalizationHelper.noInternet,
        'timestamp': DateTime.now().toIso8601String(),
      });
      return;
    }

    final userId = _db.getUserId();
    if (userId == null) {
      AppConfig.log('⚠️ No user logged in (Hive), sync skipped.');
      _syncStatusNotifier.value = SyncStatus.error;
      _syncErrors.add({
        'message': LocalizationHelper.noUserLoggedIn,
        'timestamp': DateTime.now().toIso8601String(),
      });
      return;
    }

    if (_firebase.currentUser == null) {
      AppConfig.log('⚠️ No Firebase session, trying to restore...');
      await _tryRestoreSession();
      if (_firebase.currentUser == null) {
        _syncStatusNotifier.value = SyncStatus.error;
        _syncErrors.add({
          'message': LocalizationHelper.noFirebaseSession,
          'timestamp': DateTime.now().toIso8601String(),
        });
        return;
      }
    }

    // ⭐ H-1: حارس تطابق الهوية — لا نرفع بيانات Hive المحلي أبداً
    // لجلسة Firebase تخص مستخدماً آخر (تسريب بين المستأجرين).
    final firebaseUid = _firebase.currentUser?.uid;
    if (firebaseUid == null || firebaseUid != userId) {
      AppConfig.logError(
          '🚫 Sync aborted: Hive user ($userId) does not match '
          'Firebase session (${firebaseUid ?? 'none'})',
          null);
      _syncStatusNotifier.value = SyncStatus.error;
      _syncErrors.add({
        'message': LocalizationHelper.noUserLoggedIn,
        'timestamp': DateTime.now().toIso8601String(),
      });
      return;
    }

    if (_isSyncing) {
      AppConfig.log('⚠️ Sync already in progress');
      return;
    }

    try {
      _isSyncing = true;
      _syncStatusNotifier.value = SyncStatus.syncing;
      _syncErrors.clear();

      AppConfig.log('===== ===== Starting Offline-First sync for user: $userId =====');

      // ⭐ الخطوة 0: مزامنة عمليات الحذف غير المتزامنة (Tombsones)
      await _syncPendingDeletes();

      // ⭐ الخطوة 1: رفع البيانات غير المتزامنة إلى Firebase (Push)
      await _syncUnsyncedData();

      // ⭐ الخطوة 2: جلب البيانات الجديدة من Firebase (Pull)
      // مع حد زمني: لا نسحب قاعدة البيانات كاملة في كل مزامنة (تسبب بطئاً).
      // عند تسجيل الدخول (fullSync) نسحب دائماً كامل بيانات الحساب.
      final isInitialSync = !_isInitialSyncDone;
      final isPullCooldownElapsed = fullSync ||
          _lastFirebasePullAt == null ||
          DateTime.now().difference(_lastFirebasePullAt!) >= _pullCooldown;
      if (isInitialSync || isPullCooldownElapsed) {
        await _syncFromFirebase(fullPull: fullSync);
        _lastFirebasePullAt = DateTime.now();
      } else {
        AppConfig.log('⏭️ Skipping full Firebase pull (cooldown)');
      }

      _isInitialSyncDone = true;
      _isSyncing = false;

      // ⭐ إذا وقعت أخطاء جزئية (فشل رفع عنصر أو فشل جلب قسم)
      // لا نعلن النجاح — الحالة error حتى يراها المستخدم وتُعاد المحاولة.
      if (_syncErrors.isEmpty) {
        _lastSuccessfulSync = DateTime.now();
        _syncStatusNotifier.value = SyncStatus.success;
        AppConfig.log('===== ===== ===== SYNC COMPLETED SUCCESSFULLY =====');
      } else {
        _syncStatusNotifier.value = SyncStatus.error;
        AppConfig.log(
            '⚠️ SYNC FINISHED WITH ${_syncErrors.length} ERROR(S) — not marked successful');
      }

      _notifyDataChanged();

      AppConfig.log('📊 Final Hive state:');
      AppConfig.log('  - Products: ${_db.getProductCount()}');
      AppConfig.log('  - Sales: ${_db.getSaleCount()}');

      if (_syncStatusNotifier.value == SyncStatus.success) {
        _syncStatusNotifier.value = SyncStatus.idle;
      }
    } catch (e) {
      _isSyncing = false;
      _syncStatusNotifier.value = SyncStatus.error;

      _syncErrors.add({
        'message': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      });

      AppConfig.logError('===== ===== SYNC ERROR =====', e);
      AppConfig.logError('Stack trace', StackTrace.current);
    }
  }

  /// مزامنة ما بعد تسجيل الدخول (Offline First):
  /// رفع البيانات غير المتزامنة ثم سحب كامل لبيانات الحساب.
  ///
  /// لا ترمي استثناءً أبداً — فشل المزامنة لا يمنع الدخول.
  /// ⭐ H-6: حُدّت المحاولات إلى 2 كحد أقصى (كانت 3 + سحب مباشر إضافي =
  /// حتى 4 سحب كاملة لكل دخول). السحب المباشر الإضافي أُزيل لأن كل
  /// محاولة syncNow(fullSync: true) تسحب أصلاً؛ المزامنة الدورية
  /// لاحقاً تغطي أي فشل.
  Future<void> syncAfterLogin({int maxRetries = 2}) async {
    // ⭐ سقف صارم: لا أكثر من محاولتين مهما مرر المستدعي
    final attempts = maxRetries > 2 ? 2 : maxRetries;
    AppConfig.log('===== Post-login sync started (maxRetries: $attempts) =====');

    for (var attempt = 1; attempt <= attempts; attempt++) {
      await syncNow(fullSync: true);

      final lastOk = _syncStatusNotifier.value != SyncStatus.error;
      final hasData = !SyncPolicy.needsDirectPull(
        productCount: _db.getProductCount(),
        saleCount: _db.getSaleCount(),
      );

      if (lastOk || hasData) break;

      AppConfig.log('⚠️ Post-login sync incomplete (attempt $attempt/$attempts)');
      if (SyncPolicy.shouldRetryAfterFailure(attempt: attempt, maxRetries: attempts)) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    AppConfig.log('📊 Post-login sync finished:');
    AppConfig.log('  - Products: ${_db.getProductCount()}');
    AppConfig.log('  - Sales: ${_db.getSaleCount()}');
  }

  Future<void> _syncPendingDeletes() async {
    AppConfig.log('===== SYNCING PENDING DELETES =====');

    // ⭐ حذف المنتجات من Firebase
    final pendingProductDeletes = _db.getPendingDeletes('product');
    for (final id in pendingProductDeletes) {
      try {
        await _firebase.deleteProduct(id);
        await _db.removePendingDelete('product', id);
        AppConfig.log('  ✅ Pending product delete synced: $id');
      } catch (e) {
        AppConfig.logError('  ❌ Failed to sync product delete', e);
        _syncErrors.add({
          'type': 'product_delete',
          'id': id,
          'message': e.toString(),
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    }

    // ⭐ حذف المبيعات من Firebase
    final pendingSaleDeletes = _db.getPendingDeletes('sale');
    for (final id in pendingSaleDeletes) {
      try {
        await _firebase.deleteSale(id);
        await _db.removePendingDelete('sale', id);
        AppConfig.log('  ✅ Pending sale delete synced: $id');
      } catch (e) {
        AppConfig.logError('  ❌ Failed to sync sale delete', e);
        _syncErrors.add({
          'type': 'sale_delete',
          'id': id,
          'message': e.toString(),
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    }

    // ⭐ حذف الموردين من Firebase
    final pendingSupplierDeletes = _db.getPendingDeletes('supplier');
    for (final id in pendingSupplierDeletes) {
      try {
        await _firebase.deleteSupplier(id);
        await _db.removePendingDelete('supplier', id);
        AppConfig.log('  ✅ Pending supplier delete synced: $id');
      } catch (e) {
        AppConfig.logError('  ❌ Failed to sync supplier delete', e);
        _syncErrors.add({
          'type': 'supplier_delete',
          'id': id,
          'message': e.toString(),
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    }

    // ⭐ حذف المشتريات من Firebase
    final pendingPurchaseDeletes = _db.getPendingDeletes('purchase');
    for (final id in pendingPurchaseDeletes) {
      try {
        await _firebase.deletePurchase(id);
        await _db.removePendingDelete('purchase', id);
        AppConfig.log('  ✅ Pending purchase delete synced: $id');
      } catch (e) {
        AppConfig.logError('  ❌ Failed to sync purchase delete', e);
        _syncErrors.add({
          'type': 'purchase_delete',
          'id': id,
          'message': e.toString(),
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    }

    // ⭐ حذف العملاء من Firebase
    final pendingCustomerDeletes = _db.getPendingDeletes('customer');
    for (final id in pendingCustomerDeletes) {
      try {
        await _firebase.deleteCustomer(id);
        await _db.removePendingDelete('customer', id);
        AppConfig.log('  ✅ Pending customer delete synced: $id');
      } catch (e) {
        AppConfig.logError('  ❌ Failed to sync customer delete', e);
        _syncErrors.add({'type': 'customer_delete', 'id': id, 'message': e.toString(), 'timestamp': DateTime.now().toIso8601String()});
      }
    }

    // ⭐ حذف معاملات الديون من Firebase
    final pendingDebtTxnDeletes = _db.getPendingDeletes('debt_transaction');
    for (final id in pendingDebtTxnDeletes) {
      try {
        await _firebase.deleteDebtTransaction(id);
        await _db.removePendingDelete('debt_transaction', id);
        AppConfig.log('  ✅ Pending debt transaction delete synced: $id');
      } catch (e) {
        AppConfig.logError('  ❌ Failed to sync debt transaction delete', e);
        _syncErrors.add({'type': 'debt_transaction_delete', 'id': id, 'message': e.toString(), 'timestamp': DateTime.now().toIso8601String()});
      }
    }
  }

  // ⭐ رفع البيانات غير المتزامنة إلى Firebase باستخدام Batch Writes
  // يقلل عدد طلبات الشبكة بشكل كبير (طلب واحد لكل 500 عنصر بدلاً من طلب لكل عنصر)
  Future<void> _syncUnsyncedData() async {
    AppConfig.log('===== ===== SYNCING UNSYNCED DATA TO FIREBASE (BATCH) =====');

    // ⭐ 1. مزامنة المنتجات غير المتزامنة (Batch Write)
    final unsyncedProducts = _db.getUnsyncedProducts();
    AppConfig.log('📤 Found ${unsyncedProducts.length} unsynced products');

    if (unsyncedProducts.isNotEmpty) {
      try {
        final productsData = unsyncedProducts.map((product) => {
          'id': product.id,
          'name': product.name,
          'category': product.category,
          'price': product.price,
          'quantity': product.quantity,
          'description': product.description,
          'barcode': product.barcode,
          'minStockLevel': product.minStockLevel,
          'costPrice': product.costPrice,
          'unit': product.unit,
          'createdAt': product.createdAt,
        }).toList();

        await _firebase.addProductsBatch(productsData);

        // Mark all as synced
        for (final product in unsyncedProducts) {
          await _db.markProductAsSynced(product.id);
        }
        AppConfig.log('✅ ${unsyncedProducts.length} products synced via batch');
      } catch (e) {
        AppConfig.logError('  ❌ Failed to batch sync products', e);
        // Fallback to individual sync on batch failure
        for (final product in unsyncedProducts) {
          try {
            await _firebase.addProduct(
              id: product.id,
              name: product.name,
              category: product.category,
              price: product.price,
              quantity: product.quantity,
              description: product.description,
              barcode: product.barcode,
              minStockLevel: product.minStockLevel,
              costPrice: product.costPrice,
              unit: product.unit,
              createdAt: product.createdAt,
            );
            await _db.markProductAsSynced(product.id);
          } catch (e2) {
            AppConfig.logError('  ❌ Failed to sync product ${product.id}', e2);
            _syncErrors.add({
              'type': 'product',
              'id': product.id,
              'message': e2.toString(),
              'timestamp': DateTime.now().toIso8601String(),
            });
          }
        }
      }
    }

    // ⭐ 2. مزامنة المبيعات غير المتزامنة (Batch Write)
    final unsyncedSales = _db.getUnsyncedSales();
    AppConfig.log('📤 Found ${unsyncedSales.length} unsynced sales');

    if (unsyncedSales.isNotEmpty) {
      try {
        final salesData = unsyncedSales.map((sale) => {
          'id': sale.id,
          'items': sale.items.map((item) => {
            'id': item.id,
            'productId': item.productId,
            'productName': item.productName,
            'price': item.price,
            'quantity': item.quantity,
            'subtotal': item.subtotal,
          }).toList(),
          'subtotal': sale.subtotal,
          'discount': sale.discount,
          'tax': sale.tax,
          'total': sale.total,
          'paymentMethod': sale.paymentMethod,
          'customerName': sale.customerName,
          'customerPhone': sale.customerPhone,
          'customerId': sale.customerId,
          'saleType': sale.saleType,
          'originalSaleId': sale.originalSaleId,
          'returnedItems': sale.returnedItems?.map((item) => item.toJson()).toList(),
          'returnTotal': sale.returnTotal,
          'isFullyReturned': sale.isFullyReturned,
          'createdAt': sale.createdAt,
        }).toList();

        await _firebase.addSalesBatch(salesData);

        // Mark all as synced
        for (final sale in unsyncedSales) {
          await _db.markSaleAsSynced(sale.id);
        }
        AppConfig.log('✅ ${unsyncedSales.length} sales synced via batch');
      } catch (e) {
        AppConfig.logError('  ❌ Failed to batch sync sales', e);
        // Fallback to individual sync on batch failure
        for (final sale in unsyncedSales) {
          try {
            await _firebase.addSale(
              id: sale.id,
              items: sale.items,
              subtotal: sale.subtotal,
              discount: sale.discount,
              tax: sale.tax,
              total: sale.total,
              paymentMethod: sale.paymentMethod,
              customerName: sale.customerName,
              customerPhone: sale.customerPhone,
              customerId: sale.customerId,
              saleType: sale.saleType,
              originalSaleId: sale.originalSaleId,
              returnedItems: sale.returnedItems,
              returnTotal: sale.returnTotal,
              isFullyReturned: sale.isFullyReturned,
              createdAt: sale.createdAt,
            );
            await _db.markSaleAsSynced(sale.id);
          } catch (e2) {
            AppConfig.logError('  ❌ Failed to sync sale ${sale.id}', e2);
            _syncErrors.add({
              'type': 'sale',
              'id': sale.id,
              'message': e2.toString(),
              'timestamp': DateTime.now().toIso8601String(),
            });
          }
        }
      }
    }

    // ⭐ 3. مزامنة حركات المخزون غير المتزامنة (Batch Write)
    final unsyncedMovements = _db.getUnsyncedMovements();
    AppConfig.log('📤 Found ${unsyncedMovements.length} unsynced movements');

    if (unsyncedMovements.isNotEmpty) {
      try {
        final movementsData = unsyncedMovements.map((movement) => {
          'id': movement.id,
          'productId': movement.productId,
          'productName': movement.productName,
          'type': movement.type.name,
          'quantity': movement.quantity,
          'price': movement.price,
          'total': movement.total,
          'referenceId': movement.referenceId,
          'referenceNumber': movement.referenceNumber,
          'note': movement.note,
          'status': movement.status.name,
          'customerName': movement.customerName,
          'supplierName': movement.supplierName,
          'createdAt': movement.createdAt,
        }).toList();

        await _firebase.addMovementsBatch(movementsData);

        // Mark all as synced
        for (final movement in unsyncedMovements) {
          await _db.markMovementAsSynced(movement.id);
        }
        AppConfig.log('✅ ${unsyncedMovements.length} movements synced via batch');
      } catch (e) {
        AppConfig.logError('  ❌ Failed to batch sync movements', e);
        // Fallback to individual sync on batch failure
        for (final movement in unsyncedMovements) {
          try {
            await _firebase.addMovement(
              id: movement.id,
              productId: movement.productId,
              productName: movement.productName,
              type: movement.type,
              quantity: movement.quantity,
              price: movement.price,
              total: movement.total,
              referenceId: movement.referenceId,
              referenceNumber: movement.referenceNumber,
              note: movement.note,
              userId: movement.userId,
              status: movement.status,
              customerName: movement.customerName,
              supplierName: movement.supplierName,
              createdAt: movement.createdAt,
            );
            await _db.markMovementAsSynced(movement.id);
          } catch (e2) {
            AppConfig.logError('  ❌ Failed to sync movement ${movement.id}', e2);
            _syncErrors.add({
              'type': 'movement',
              'id': movement.id,
              'message': e2.toString(),
              'timestamp': DateTime.now().toIso8601String(),
            });
          }
        }
      }
    }

    // ⭐ 4. مزامنة الموردين غير المتزامنين
    final unsyncedSuppliers = _db.getUnsyncedSuppliers();
    AppConfig.log('📤 Found ${unsyncedSuppliers.length} unsynced suppliers');

    if (unsyncedSuppliers.isNotEmpty) {
      try {
        await _firebase.addSuppliersBatch(unsyncedSuppliers
            .map((s) => {
                  'id': s.id,
                  'name': s.name,
                  'phone': s.phone,
                  'address': s.address,
                  'notes': s.notes,
                  'created_at': s.createdAt.toIso8601String(),
                  'updated_at': s.updatedAt.toIso8601String(),
                })
            .toList());
        for (final s in unsyncedSuppliers) {
          await _db.markSupplierAsSynced(s.id);
        }
        AppConfig.log('✅ ${unsyncedSuppliers.length} suppliers synced via batch');
      } catch (e) {
        AppConfig.logError('❌ Failed to batch sync suppliers', e);
        for (final s in unsyncedSuppliers) {
          try {
            await _firebase.addSupplier(
                id: s.id,
                name: s.name,
                phone: s.phone,
                address: s.address,
                notes: s.notes,
                createdAt: s.createdAt);
            await _db.markSupplierAsSynced(s.id);
          } catch (e2) {
            AppConfig.logError('❌ Failed to sync supplier ${s.id}', e2);
            _syncErrors.add({
              'type': 'supplier',
              'id': s.id,
              'message': e2.toString(),
              'timestamp': DateTime.now().toIso8601String(),
            });
          }
        }
      }
    }

    // ⭐ 5. مزامنة المشتريات غير المتزامنة
    final unsyncedPurchases = _db.getUnsyncedPurchases();
    AppConfig.log('📤 Found ${unsyncedPurchases.length} unsynced purchases');

    if (unsyncedPurchases.isNotEmpty) {
      try {
        await _firebase.addPurchasesBatch(
            unsyncedPurchases.map((p) => p.toJson()).toList());
        for (final p in unsyncedPurchases) {
          await _db.markPurchaseAsSynced(p.id);
        }
        AppConfig.log('✅ ${unsyncedPurchases.length} purchases synced via batch');
      } catch (e) {
        AppConfig.logError('❌ Failed to batch sync purchases', e);
        for (final p in unsyncedPurchases) {
          try {
            await _firebase.addPurchase(purchase: p);
            await _db.markPurchaseAsSynced(p.id);
          } catch (e2) {
            AppConfig.logError('❌ Failed to sync purchase ${p.id}', e2);
            _syncErrors.add({
              'type': 'purchase',
              'id': p.id,
              'message': e2.toString(),
              'timestamp': DateTime.now().toIso8601String(),
            });
          }
        }
      }
    }

    // ⭐ 6. مزامنة العملاء غير المتزامنين
    final unsyncedCustomers = _db.getUnsyncedCustomers();
    AppConfig.log('📤 Found ${unsyncedCustomers.length} unsynced customers');
    if (unsyncedCustomers.isNotEmpty) {
      try {
        await _firebase.addCustomersBatch(unsyncedCustomers
            .map((c) => {
                  'id': c.id, 'name': c.name, 'phone': c.phone,
                  'address': c.address, 'notes': c.notes,
                  'created_at': c.createdAt.toIso8601String(),
                })
            .toList());
        for (final c in unsyncedCustomers) {
          await _db.markCustomerAsSynced(c.id);
        }
        AppConfig.log('✅ ${unsyncedCustomers.length} customers synced via batch');
      } catch (e) {
        AppConfig.logError('❌ Failed to batch sync customers', e);
        for (final c in unsyncedCustomers) {
          try {
            await _firebase.addCustomer(
                id: c.id, name: c.name, phone: c.phone,
                address: c.address, notes: c.notes, createdAt: c.createdAt);
            await _db.markCustomerAsSynced(c.id);
          } catch (e2) {
            AppConfig.logError('❌ Failed to sync customer ${c.id}', e2);
            _syncErrors.add({'type': 'customer', 'id': c.id, 'message': e2.toString(), 'timestamp': DateTime.now().toIso8601String()});
          }
        }
      }
    }

    // ⭐ 7. مزامنة معاملات الديون غير المتزامنة
    final unsyncedDebtTxns = _db.getUnsyncedDebtTransactions();
    AppConfig.log('📤 Found ${unsyncedDebtTxns.length} unsynced debt transactions');
    if (unsyncedDebtTxns.isNotEmpty) {
      try {
        await _firebase.addDebtTransactionsBatch(
            unsyncedDebtTxns.map((t) => t.toJson()).toList());
        for (final t in unsyncedDebtTxns) {
          await _db.markDebtTransactionAsSynced(t.id);
        }
        AppConfig.log('✅ ${unsyncedDebtTxns.length} debt transactions synced via batch');
      } catch (e) {
        AppConfig.logError('❌ Failed to batch sync debt transactions', e);
        for (final t in unsyncedDebtTxns) {
          try {
            await _firebase.addDebtTransaction(
                id: t.id, customerId: t.customerId, type: t.type.name,
                amount: t.amount, saleId: t.saleId, note: t.note, createdAt: t.createdAt);
            await _db.markDebtTransactionAsSynced(t.id);
          } catch (e2) {
            AppConfig.logError('❌ Failed to sync debt txn ${t.id}', e2);
            _syncErrors.add({'type': 'debt_transaction', 'id': t.id, 'message': e2.toString(), 'timestamp': DateTime.now().toIso8601String()});
          }
        }
      }
    }

    AppConfig.log('===== ===== UNSYNCED DATA SYNC COMPLETED =====');
  }

  // ⭐ جلب البيانات من Firebase وتحديث Hive
  // fullPull: عند تسجيل الدخول نسحب كل بيانات الحساب (تجاهل آخر توقيت)
  Future<void> _syncFromFirebase({bool fullPull = false}) async {
    AppConfig.log('===== ===== SYNCING FROM FIREBASE TO HIVE =====');

    final userId = _db.getUserId();
    if (userId == null) {
      AppConfig.log('⚠️ No user ID in Hive, skipping pull');
      return;
    }

    // ⭐ قائمة IDs المحذوفة محلياً بانتظار رفع الحذف للسيرفر.
    // يجب ألا يُعيد السحب إضافة أي منها، وإلا ظهر "شبح" محذوف مجدداً.
    final pendingDeleteIds = <String>{
      ..._db.getPendingDeletes('product'),
      ..._db.getPendingDeletes('sale'),
      ..._db.getPendingDeletes('supplier'),
      ..._db.getPendingDeletes('purchase'),
      ..._db.getPendingDeletes('customer'),
      ..._db.getPendingDeletes('debt_transaction'),
    };

    // ⭐ يتقدم watermark فقط إذا نجحت كل عمليات الجلب.
    // لو فشل أي قسم، الوثائق غير المسحوبة ستصبح أقدم من watermark
    // ولن تُسحب أبداً (فقدان بيانات صامت دائم).
    bool allPullsSucceeded = true;

    // ⭐ 1. جلب المنتجات من Firebase (سحب تزايدي بعد أول مزامنة كاملة)
    List<Product> serverProducts = [];
    try {
      AppConfig.log('📥📥📥 Fetching products from Firebase...');
      final lastSync = fullPull ? null : _db.getLastSyncTime();
      serverProducts = await _firebase.getProducts(lastSync: lastSync);
      AppConfig.log('📥📥📥 Fetched ${serverProducts.length} products from Firebase');
    } catch (e) {
      allPullsSucceeded = false;
      AppConfig.logError('❌ Error fetching products from Firebase', e);
    }

    // ⭐ 2. تحديث Hive بالمنتجات الجديدة (مع الحفاظ على isSynced)
    if (serverProducts.isNotEmpty) {
      int addedCount = 0;
      int updatedCount = 0;

      for (var serverProduct in serverProducts) {
        // ⭐ تجاهل إعادة إضافة منتج محذوف محلياً بانتظار رفع الحذف (شبح)
        if (pendingDeleteIds.contains(serverProduct.id)) continue;
        final localProduct = _db.getProductById(serverProduct.id);

        if (localProduct == null) {
          // ⭐ منتج جديد من Firebase (isSynced = true)
          await _db.addProductWithId(
            id: serverProduct.id,
            name: serverProduct.name,
            category: serverProduct.category,
            price: serverProduct.price,
            quantity: serverProduct.quantity,
            description: serverProduct.description,
            barcode: serverProduct.barcode,
            userId: serverProduct.userId,
            minStockLevel: serverProduct.minStockLevel,
            costPrice: serverProduct.costPrice,
            isSynced: true,
            unit: serverProduct.unit,
          );
          addedCount++;
        } else if (localProduct.isSynced) {
          // ⭐ تحديث المنتج الموجود والمتزامن
          // نستخدم updatedAt للمقارنة
          if (serverProduct.updatedAt.isAfter(localProduct.updatedAt)) {
            await _db.updateProduct(
              id: localProduct.id,
              name: serverProduct.name,
              category: serverProduct.category,
              price: serverProduct.price,
              quantity: serverProduct.quantity,
              description: serverProduct.description,
              barcode: serverProduct.barcode,
              minStockLevel: serverProduct.minStockLevel,
              costPrice: serverProduct.costPrice,
              unit: serverProduct.unit,
            );
            await _db.markProductAsSynced(localProduct.id);
            updatedCount++;
          }
        }
        // ⭐ إذا كان المنتج غير متزامن (isSynced = false)، نتركه كما هو
        // لأنه تم تعديله محلياً وسيتم رفعه في المزامنة القادمة
      }

      AppConfig.log('  ✅ Added $addedCount products, Updated $updatedCount products');
    }

    // ⭐ 3. جلب المبيعات من Firebase (سحب تزايدي)
    List<Sale> serverSales = [];
    try {
      AppConfig.log('📥📥📥 Fetching sales from Firebase...');
      final lastSync = fullPull ? null : _db.getLastSyncTime();
      serverSales = await _firebase.getSales(lastSync: lastSync);
      AppConfig.log('📥📥📥 Fetched ${serverSales.length} sales from Firebase');
    } catch (e) {
      allPullsSucceeded = false;
      AppConfig.logError('❌ Error fetching sales from Firebase', e);
    }

    // ⭐ 4. تحديث Hive بالمبيعات الجديدة (مع الحفاظ على isSynced)
    if (serverSales.isNotEmpty) {
      int addedCount = 0;

      for (var serverSale in serverSales) {
        // ⭐ تجاهل إعادة إضافة مبيعة محذوفة محلياً بانتظار رفع الحذف (شبح)
        if (pendingDeleteIds.contains(serverSale.id)) continue;
        final localSale = _db.getSaleById(serverSale.id);

        if (localSale == null) {
          // ⭐ مبيعة جديدة من Firebase (isSynced = true)
          await _db.addSaleWithId(
            id: serverSale.id,
            items: serverSale.items,
            subtotal: serverSale.subtotal,
            discount: serverSale.discount,
            tax: serverSale.tax,
            total: serverSale.total,
            paymentMethod: serverSale.paymentMethod,
            userId: serverSale.userId,
            customerName: serverSale.customerName,
            customerPhone: serverSale.customerPhone,
            customerId: serverSale.customerId,
            saleType: serverSale.saleType,
            originalSaleId: serverSale.originalSaleId,
            returnedItems: serverSale.returnedItems,
            returnTotal: serverSale.returnTotal,
            isFullyReturned: serverSale.isFullyReturned,
            createdAt: serverSale.createdAt,
            isSynced: true,
          );
          addedCount++;
        } else if (localSale.isSynced) {
          // ⭐ مبيعة موجودة ومتزامنة محلياً: لم يمسها هذا الجهاز،
          // والسيرفر وصله تحديث منها (وصلت في سحب updated_at > lastSync)
          // — غالباً إرجاع من جهاز آخر. نعتمد نسخة السيرفر حتى تنتقل
          // المرتجعات بين الأجهزة (كانت تُتجاهل سابقاً).
          await _db.addSaleWithId(
            id: serverSale.id,
            items: serverSale.items,
            subtotal: serverSale.subtotal,
            discount: serverSale.discount,
            tax: serverSale.tax,
            total: serverSale.total,
            paymentMethod: serverSale.paymentMethod,
            userId: serverSale.userId,
            customerName: serverSale.customerName,
            customerPhone: serverSale.customerPhone,
            customerId: serverSale.customerId,
            saleType: serverSale.saleType,
            originalSaleId: serverSale.originalSaleId,
            returnedItems: serverSale.returnedItems,
            returnTotal: serverSale.returnTotal,
            isFullyReturned: serverSale.isFullyReturned,
            createdAt: serverSale.createdAt,
            isSynced: true,
          );
        }
        // ⭐ إذا كانت المبيعة موجودة وغير متزامنة (isSynced=false)، نتركها
        // كما هي لأنها معدّلة محلياً وستُرفع في المزامنة القادمة
      }

      AppConfig.log('  ✅ Added $addedCount sales');
    }

    // ⭐ 5. جلب حركات المخزون من Firebase (سحب تزايدي)
    List<InventoryMovement> serverMovements = [];
    try {
      AppConfig.log('📥📥📥 Fetching movements from Firebase...');
      final lastSync = fullPull ? null : _db.getLastSyncTime();
      serverMovements = await _firebase.getMovements(lastSync: lastSync);
      AppConfig.log('📥📥📥 Fetched ${serverMovements.length} movements from Firebase');
    } catch (e) {
      allPullsSucceeded = false;
      AppConfig.logError('❌ Error fetching movements from Firebase', e);
    }

    // ⭐ 6. تحديث Hive بالحركات الجديدة
    if (serverMovements.isNotEmpty) {
      int addedCount = 0;
      for (var serverMovement in serverMovements) {
        final exists = _db.getMovementById(serverMovement.id) != null;
        if (!exists) {
          await _db.addMovementWithId(
            id: serverMovement.id,
            productId: serverMovement.productId,
            productName: serverMovement.productName,
            type: serverMovement.type,
            quantity: serverMovement.quantity,
            price: serverMovement.price,
            total: serverMovement.total,
            referenceId: serverMovement.referenceId,
            referenceNumber: serverMovement.referenceNumber,
            note: serverMovement.note,
            userId: serverMovement.userId,
            status: serverMovement.status,
            isSynced: true,
            customerName: serverMovement.customerName,
            supplierName: serverMovement.supplierName,
            createdAt: serverMovement.createdAt,
          );
          addedCount++;
        }
      }
      AppConfig.log('  ✅ Added $addedCount movements');
    }

    // ⭐ 7. جلب الموردين من Firebase
    try {
      AppConfig.log('📥📥📥 Fetching suppliers from Firebase...');
      final lastSync = fullPull ? null : _db.getLastSyncTime();
      final serverSuppliers = await _firebase.getSuppliers(lastSync: lastSync);
      AppConfig.log('📥📥📥 Fetched ${serverSuppliers.length} suppliers');

      for (var serverSupplier in serverSuppliers) {
        // ⭐ تجاهل إعادة إضافة مورد محذوف محلياً بانتظار رفع الحذف (شبح)
        if (pendingDeleteIds.contains(serverSupplier.id)) continue;
        final local = _db.getSupplierById(serverSupplier.id);
        if (local == null) {
          await _db.addSupplierWithId(
            id: serverSupplier.id,
            name: serverSupplier.name,
            phone: serverSupplier.phone,
            address: serverSupplier.address,
            notes: serverSupplier.notes,
            userId: serverSupplier.userId,
            isSynced: true,
          );
        } else if (local.isSynced &&
            serverSupplier.updatedAt.isAfter(local.updatedAt)) {
          await _db.updateSupplier(
            id: local.id,
            name: serverSupplier.name,
            phone: serverSupplier.phone,
            address: serverSupplier.address,
            notes: serverSupplier.notes,
          );
          // ⭐ updateSupplier يضبط isSynced=false، نعيد ضبطه بعد التحديث في سياق السحب
          await _db.markSupplierAsSynced(local.id);
        }
      }
    } catch (e) {
      allPullsSucceeded = false;
      AppConfig.logError('❌ Error fetching suppliers from Firebase', e);
    }

    // ⭐ 8. جلب المشتريات من Firebase (LWW بـ updated_at):
    // غير موجود → إضافة؛ موجود ومتزامن وسيرفر أحدث → تحديث شامل؛ غير متزامن → يُترك
    try {
      AppConfig.log('📥📥📥 Fetching purchases from Firebase...');
      final lastSync = fullPull ? null : _db.getLastSyncTime();
      final serverPurchases = await _firebase.getPurchases(lastSync: lastSync);
      AppConfig.log('📥📥📥 Fetched ${serverPurchases.length} purchases');

      for (var sp in serverPurchases) {
        // ⭐ تجاهل إعادة إضافة مشتري محذوف محلياً بانتظار رفع الحذف (شبح)
        if (pendingDeleteIds.contains(sp.id)) continue;
        final local = _db.getPurchaseById(sp.id);
        if (local == null) {
          await _db.addPurchaseWithId(
            id: sp.id,
            items: sp.items,
            supplierId: sp.supplierId,
            supplierName: sp.supplierName,
            total: sp.total,
            note: sp.note,
            purchaseType: sp.purchaseType,
            originalPurchaseId: sp.originalPurchaseId,
            userId: sp.userId,
            isSynced: true,
            createdAt: sp.createdAt,
            invoiceNumber: sp.invoiceNumber,
            returnedItems: sp.returnedItems,
            returnTotal: sp.returnTotal,
            isFullyReturned: sp.isFullyReturned,
            updatedAt: sp.updatedAt,
          );
        } else if (local.isSynced && sp.updatedAt.isAfter(local.updatedAt)) {
          // تحديث شامل (يشمل حالة المرتجع ورقم الفاتورة)
          await _db.addPurchaseWithId(
            id: sp.id,
            items: sp.items,
            supplierId: sp.supplierId,
            supplierName: sp.supplierName,
            total: sp.total,
            note: sp.note,
            purchaseType: sp.purchaseType,
            originalPurchaseId: sp.originalPurchaseId,
            userId: sp.userId,
            isSynced: true,
            createdAt: sp.createdAt,
            invoiceNumber: sp.invoiceNumber,
            returnedItems: sp.returnedItems,
            returnTotal: sp.returnTotal,
            isFullyReturned: sp.isFullyReturned,
            updatedAt: sp.updatedAt,
          );
        }
      }
    } catch (e) {
      allPullsSucceeded = false;
      AppConfig.logError('❌ Error fetching purchases from Firebase', e);
    }

    // ⭐ 9. جلب العملاء من Firebase (سحب تزديدي + LWW بـ updated_at)
    try {
      AppConfig.log('📥📥📥 Fetching customers from Firebase...');
      final lastSync = fullPull ? null : _db.getLastSyncTime();
      final serverCustomers = await _firebase.getCustomers(lastSync: lastSync);
      AppConfig.log('📥📥📥 Fetched ${serverCustomers.length} customers');

      for (var serverCustomer in serverCustomers) {
        // ⭐ تجاهل إعادة إضافة عميل محذوف محلياً بانتظار رفع الحذف (شبح)
        if (pendingDeleteIds.contains(serverCustomer.id)) continue;
        final local = _db.getCustomerById(serverCustomer.id);
        if (local == null) {
          await _db.addCustomerWithId(
            id: serverCustomer.id,
            name: serverCustomer.name,
            phone: serverCustomer.phone,
            address: serverCustomer.address,
            notes: serverCustomer.notes,
            userId: serverCustomer.userId,
            isSynced: true,
            createdAt: serverCustomer.createdAt,
            updatedAt: serverCustomer.updatedAt,
          );
        } else if (local.isSynced &&
            serverCustomer.updatedAt.isAfter(local.updatedAt)) {
          await _db.updateCustomer(
            id: local.id,
            name: serverCustomer.name,
            phone: serverCustomer.phone,
            address: serverCustomer.address,
            notes: serverCustomer.notes,
          );
          // ⭐ updateCustomer يضبط isSynced=false، نعيد ضبطه في سياق السحب
          await _db.markCustomerAsSynced(local.id);
        }
      }
    } catch (e) {
      allPullsSucceeded = false;
      AppConfig.logError('❌ Error fetching customers from Firebase', e);
    }

    // ⭐ 10. جلب معاملات الديون من Firebase
    // مضافة فقط (دفتر الديون لا يُعدَّل بعد الإنشاء — الحذف عبر tombstones)
    try {
      AppConfig.log('📥📥📥 Fetching debt transactions from Firebase...');
      final lastSync = fullPull ? null : _db.getLastSyncTime();
      final serverDebtTxns =
          await _firebase.getDebtTransactions(lastSync: lastSync);
      AppConfig.log('📥📥📥 Fetched ${serverDebtTxns.length} debt transactions');

      for (var serverTxn in serverDebtTxns) {
        // ⭐ تجاهل إعادة إضافة معاملة محذوفة محلياً بانتظار رفع الحذف (شبح)
        if (pendingDeleteIds.contains(serverTxn.id)) continue;
        final exists = _db.getDebtTransactionById(serverTxn.id) != null;
        if (!exists) {
          await _db.addDebtTransactionWithId(
            id: serverTxn.id,
            customerId: serverTxn.customerId,
            type: serverTxn.type,
            amount: serverTxn.amount,
            saleId: serverTxn.saleId,
            note: serverTxn.note,
            userId: serverTxn.userId,
            isSynced: true,
            createdAt: serverTxn.createdAt,
            updatedAt: serverTxn.updatedAt,
          );
        }
      }
    } catch (e) {
      allPullsSucceeded = false;
      AppConfig.logError('❌ Error fetching debt transactions from Firebase', e);
    }

    // ⭐ حفظ آخر توقيت سحب مع هامش 5 دقائق (overlap) حتى لا تُفوَّت
    // أي وثيقة حُدِّثت أثناء تنفيذ الاستعلام بسبب تباين الساعات.
    // ⭐ لا يُقدَّم watermark إذا فشل أي جلب — وإلا ستُفقد الوثائق
    // غير المسحوبة نهائياً حتى مزامنة كاملة.
    if (allPullsSucceeded) {
      await _db.saveLastSyncTime(
          DateTime.now().subtract(const Duration(minutes: 5)));
    } else {
      AppConfig.log('⚠️ Pull had failures — lastSyncTime NOT advanced');
    }

    AppConfig.log('===== ===== SYNC FROM FIREBASE COMPLETED =====');
  }

  Future<void> _tryRestoreSession() async {
    try {
      await _firebase.init();
      if (_firebase.currentUser != null) {
        AppConfig.log('✅ Session restored successfully');
      } else {
        AppConfig.log('⚠️ Could not restore session');
      }
    } catch (e) {
      AppConfig.logError('⚠️ Failed to restore session', e);
    }
  }

  // ==================== دوال القراءة (Offline First) ====================

  Future<List<Product>> getProducts({int offset = 0, int limit = 50}) async {
    // ⭐ Offline First: القراءة من Hive فقط (لا قراءة من Firebase)
    // المزامنة الأولية تتم في شاشة البداية (Splash) ويتم تحديث Hive هناك
    final localProducts = _db.getProductsPaginated(offset: offset, limit: limit);
    AppConfig.log('📊 getProducts: ${localProducts.length} products in Hive');
    return localProducts;
  }

  Future<List<Sale>> getSales({int offset = 0, int limit = 50}) async {
    // ⭐ Offline First: القراءة من Hive فقط (لا قراءة من Firebase)
    // المزامنة الأولية تتم في شاشة البداية (Splash) ويتم تحديث Hive هناك
    final localSales = _db.getSalesPaginated(offset: offset, limit: limit);
    AppConfig.log('📊 getSales: ${localSales.length} sales in Hive');
    return localSales;
  }

  // ⭐ كل المبيعات (للإحصائيات والشاشات الكبيرة بدون سقف)
  Future<List<Sale>> getAllSales() async {
    return _db.getAllSales();
  }

  // ⭐ كل المنتجات (للإحصائيات والشاشات الكبيرة بدون سقف)
  Future<List<Product>> getAllProducts() async {
    return _db.getAllProducts();
  }

  Future<List<Supplier>> getSuppliers() async {
    return _db.getAllSuppliers();
  }

  Future<List<Purchase>> getPurchases() async {
    return _db.getAllPurchases();
  }

  Future<Sale> updateSaleWithReturn({
    required String saleId,
    required List<SaleItem> returnedItems,
    required double returnTotal,
  }) async {
    // ⭐ أولاً: تحديث Hive محلياً (isSynced = false)
    // Hive هو مصدر الحقيقة لحساب حالة الإرجاع الكامل (من الكميات المدمجة)
    final updatedSale = await _db.updateSaleWithReturn(
      saleId: saleId,
      returnedItems: returnedItems,
      returnTotal: returnTotal,
    );

    _notifyDataChanged();

    // ⭐ ثانياً: محاولة المزامنة مع Firebase إذا كان هناك اتصال
    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.updateSaleWithReturn(
          id: saleId,
          returnedItems: returnedItems,
          returnTotal: returnTotal,
          isFullyReturned: updatedSale.isFullyReturned,
        );
        await _db.markSaleAsSynced(saleId);
        AppConfig.log('✅ Sale updated with return in Firebase: $saleId');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to update sale with return in Firebase', e);
        // ⭐ ستبقى isSynced = false وسيتم رفعها في المزامنة القادمة
      }
    }

    return updatedSale;
  }

  Future<List<String>> getCategories() async {
    return _db.getCategories();
  }

  Future<Map<String, dynamic>> getInventoryStats() async {
    return _db.getInventoryStats();
  }

  // ==================== دوال الكتابة (Offline First) ====================

  Future<Product> addProduct({
    required String name,
    required String category,
    required double price,
    required double quantity,
    String? description,
    String? barcode,
    int minStockLevel = 10,
    double? costPrice,
    String unit = 'piece',
  }) async {
    final userId = _db.getUserId();
    if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);

    final productId = _uuid.v4();

    // ⭐ أولاً: حفظ في Hive محلياً (isSynced = false)
    await _db.addProductWithId(
      id: productId,
      name: name,
      category: category,
      price: price,
      quantity: quantity,
      description: description,
      barcode: barcode,
      userId: userId,
      minStockLevel: minStockLevel,
      costPrice: costPrice,
      isSynced: false,
      unit: unit,
    );

    _notifyDataChanged();

    // ⭐ ثانياً: محاولة المزامنة مع Firebase إذا كان هناك اتصال
    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.addProduct(
          id: productId,
          name: name,
          category: category,
          price: price,
          quantity: quantity,
          description: description,
          barcode: barcode,
          minStockLevel: minStockLevel,
          costPrice: costPrice,
          unit: unit,
          createdAt: _db.getProductById(productId)?.createdAt,
        );
        await _db.markProductAsSynced(productId);
        AppConfig.log('✅ Product synced to Firebase: $name');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to sync product to Firebase', e);
        // ⭐ ستبقى isSynced = false وسيتم رفعها في المزامنة القادمة
      }
    }

    return _db.getProductById(productId)!;
  }

  Future<Sale> addSale({
    required List<SaleItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required String paymentMethod,
    String? customerName,
    String? customerPhone,
    String? customerId,
    double paidNow = 0.0,
    String saleType = 'sale',
    String? originalSaleId,
  }) async {
    final userId = _db.getUserId();
    if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);

    final saleId = _uuid.v4();

    final saleItems = items
        .map((item) => SaleItem(
              id: _uuid.v4(),
              productId: item.productId,
              productName: item.productName,
              price: item.price,
              quantity: item.quantity,
              subtotal: item.subtotal,
            ))
        .toList();

    // ⭐ أولاً: حفظ في Hive محلياً (isSynced = false)
    final sale = await _db.addSaleWithId(
      id: saleId,
      items: saleItems,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: total,
      paymentMethod: paymentMethod,
      userId: userId,
      customerName: customerName,
      customerPhone: customerPhone,
      customerId: customerId,
      saleType: saleType,
      originalSaleId: originalSaleId,
      isSynced: false,
    );

    // ⭐ If this is a debt sale, create ledger rows
    if (paymentMethod == 'Debt' && customerId != null && total > paidNow) {
      final debtTxId = _uuid.v4();
      await _db.addDebtTransactionWithId(
        id: debtTxId, customerId: customerId,
        type: DebtTransactionType.debt, amount: total,
        saleId: saleId, userId: userId,
      );
      if (paidNow > 0) {
        await _db.addDebtTransactionWithId(
          id: _uuid.v4(), customerId: customerId,
          type: DebtTransactionType.payment, amount: -paidNow,
          saleId: saleId, note: LocalizationHelper.posPaidOnPurchase,
          userId: userId,
        );
      }
    }

    _notifyDataChanged();

    // ⭐ ثانياً: محاولة المزامنة مع Firebase إذا كان هناك اتصال
    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.addSale(
          id: saleId,
          items: saleItems,
          subtotal: subtotal,
          discount: discount,
          tax: tax,
          total: total,
          paymentMethod: paymentMethod,
          customerName: customerName,
          customerPhone: customerPhone,
          customerId: customerId,
          saleType: saleType,
          originalSaleId: originalSaleId,
          createdAt: sale.createdAt,
        );
        await _db.markSaleAsSynced(saleId);
        AppConfig.log('✅ Sale synced to Firebase: $saleId');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to sync sale to Firebase', e);
        // ⭐ ستبقى isSynced = false وسيتم رفعها في المزامنة القادمة
      }
    }

    return sale;
  }

  Future<void> updateProduct({
    required String id,
    required String name,
    required String category,
    required double price,
    required double quantity,
    String? description,
    String? barcode,
    int? minStockLevel,
    double? costPrice,
    String? unit,
  }) async {
    // ⭐ أولاً: تحديث في Hive محلياً (isSynced = false)
    await _db.updateProduct(
      id: id,
      name: name,
      category: category,
      price: price,
      quantity: quantity,
      description: description,
      barcode: barcode,
      minStockLevel: minStockLevel,
      costPrice: costPrice,
      unit: unit,
    );

    _notifyDataChanged();

    // ⭐ ثانياً: محاولة المزامنة مع Firebase إذا كان هناك اتصال
    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.updateProduct(
          id: id,
          name: name,
          category: category,
          price: price,
          quantity: quantity,
          description: description,
          barcode: barcode,
          minStockLevel: minStockLevel,
          costPrice: costPrice,
          unit: unit,
        );
        await _db.markProductAsSynced(id);
        AppConfig.log('✅ Product updated in Firebase: $name');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to update product in Firebase', e);
        // ⭐ ستبقى isSynced = false وسيتم رفعها في المزامنة القادمة
      }
    }
  }

  Future<void> deleteProduct(String id) async {
    await _db.deleteProduct(id);
    _notifyDataChanged();

    // ⭐ تسجيل الحذف كعملية معلّقة حتى يتم رفعها للخادم (منع عودة المنتج بعد المزامنة)
    await _db.addPendingDelete('product', id);

    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.deleteProduct(id);
        await _db.removePendingDelete('product', id);
        AppConfig.log('✅ Product deleted from Firebase: $id');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to delete product from Firebase', e);
      }
    }
  }

  Future<void> deleteSale(String id) async {
    await _db.deleteSale(id);
    _notifyDataChanged();

    await _db.addPendingDelete('sale', id);

    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.deleteSale(id);
        await _db.removePendingDelete('sale', id);
        AppConfig.log('✅ Sale deleted from Firebase: $id');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to delete sale from Firebase', e);
      }
    }
  }

  // ==================== عمليات الموردين ====================

  Future<Supplier> addSupplier({
    required String name,
    String? phone,
    String? address,
    String? notes,
  }) async {
    final userId = _db.getUserId();
    if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);

    final supplierId = _uuid.v4();

    // ⭐ أولاً: حفظ محلي
    await _db.addSupplierWithId(
      id: supplierId,
      name: name,
      phone: phone,
      address: address,
      notes: notes,
      userId: userId,
      isSynced: false,
    );

    _notifyDataChanged();

    // ⭐ ثانياً: رفع مباشر إن أمكن
    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.addSupplier(
            id: supplierId,
            name: name,
            phone: phone,
            address: address,
            notes: notes,
            createdAt: DateTime.now());
        await _db.markSupplierAsSynced(supplierId);
        AppConfig.log('✅ Supplier synced to Firebase: $name');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to sync supplier to Firebase', e);
      }
    }

    return _db.getSupplierById(supplierId)!;
  }

  Future<void> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? address,
    String? notes,
  }) async {
    await _db.updateSupplier(id: id, name: name, phone: phone, address: address, notes: notes);
    _notifyDataChanged();

    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.updateSupplier(id: id, name: name, phone: phone, address: address, notes: notes);
        await _db.markSupplierAsSynced(id);
        AppConfig.log('✅ Supplier updated in Firebase: $id');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to update supplier in Firebase', e);
      }
    }
  }

  Future<void> deleteSupplier(String id) async {
    await _db.deleteSupplierLocal(id);
    _notifyDataChanged();

    await _db.addPendingDelete('supplier', id);

    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.deleteSupplier(id);
        await _db.removePendingDelete('supplier', id);
        AppConfig.log('✅ Supplier deleted from Firebase: $id');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to delete supplier from Firebase', e);
      }
    }
  }

  // ==================== Customer write-through methods ====================

  Future<Customer> addCustomer({
    required String name, String? phone,
    String? address, String? notes,
  }) async {
    final userId = _db.getUserId();
    if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);
    final customerId = _uuid.v4();
    await _db.addCustomerWithId(
      id: customerId, name: name, phone: phone,
      address: address, notes: notes, userId: userId, isSynced: false,
    );
    _notifyDataChanged();
    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.addCustomer(id: customerId, name: name, phone: phone, address: address, notes: notes, createdAt: DateTime.now());
        await _db.markCustomerAsSynced(customerId);
      } catch (e) {
        AppConfig.logError('⚠️ Failed to sync customer to Firebase', e);
      }
    }
    return _db.getCustomerById(customerId)!;
  }

  Future<void> updateCustomer({
    required String id, required String name,
    String? phone, String? address, String? notes,
  }) async {
    await _db.updateCustomer(id: id, name: name, phone: phone, address: address, notes: notes);
    _notifyDataChanged();
    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.updateCustomer(id: id, name: name, phone: phone, address: address, notes: notes);
        await _db.markCustomerAsSynced(id);
      } catch (e) {
        AppConfig.logError('⚠️ Failed to update customer in Firebase', e);
      }
    }
  }

  Future<void> deleteCustomer(String id) async {
    await _db.deleteCustomerLocal(id);
    _notifyDataChanged();
    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.deleteCustomer(id);
      } catch (e) {
        await _db.addPendingDelete('customer', id);
        AppConfig.logError('⚠️ Customer delete queued for sync', e);
      }
    }
  }

  // ==================== Debt ledger write-through methods ====================

  Future<void> addPayment({
    required String customerId, required double amount,
    String? note,
  }) async {
    final userId = _db.getUserId();
    if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);
    final txId = _uuid.v4();
    await _db.addDebtTransactionWithId(
      id: txId, customerId: customerId,
      type: DebtTransactionType.payment, amount: -amount,
      note: note, userId: userId, isSynced: false,
    );
    _notifyDataChanged();
    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.addDebtTransaction(
          id: txId, customerId: customerId, type: 'payment',
          amount: -amount, note: note, createdAt: DateTime.now(),
        );
        await _db.markDebtTransactionAsSynced(txId);
      } catch (e) {
        AppConfig.logError('⚠️ Failed to sync payment to Firebase', e);
      }
    }
  }

  Future<void> addManualDebt({
    required String customerId, required double amount,
    String? note,
  }) async {
    final userId = _db.getUserId();
    if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);
    final txId = _uuid.v4();
    await _db.addDebtTransactionWithId(
      id: txId, customerId: customerId,
      type: DebtTransactionType.debt, amount: amount,
      note: note, userId: userId, isSynced: false,
    );
    _notifyDataChanged();
    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.addDebtTransaction(
          id: txId, customerId: customerId, type: 'debt',
          amount: amount, note: note, createdAt: DateTime.now(),
        );
        await _db.markDebtTransactionAsSynced(txId);
      } catch (e) {
        AppConfig.logError('⚠️ Failed to sync manual debt to Firebase', e);
      }
    }
  }

  Future<void> addDebtAdjustment({
    required String customerId, required double amount,
    String? saleId, String? note,
  }) async {
    final userId = _db.getUserId();
    if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);
    final txId = _uuid.v4();
    await _db.addDebtTransactionWithId(
      id: txId, customerId: customerId,
      type: DebtTransactionType.adjustment, amount: amount,
      saleId: saleId, note: note, userId: userId, isSynced: false,
    );
    _notifyDataChanged();
    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.addDebtTransaction(
          id: txId, customerId: customerId, type: 'adjustment',
          amount: amount, saleId: saleId, note: note, createdAt: DateTime.now(),
        );
        await _db.markDebtTransactionAsSynced(txId);
      } catch (e) {
        AppConfig.logError('⚠️ Failed to sync debt adjustment to Firebase', e);
      }
    }
  }

  Future<void> deleteDebtTransaction(String id) async {
    await _db.deleteDebtTransactionLocal(id);
    _notifyDataChanged();
    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.deleteDebtTransaction(id);
      } catch (e) {
        await _db.addPendingDelete('debt_transaction', id);
        AppConfig.logError('⚠️ Debt transaction delete queued for sync', e);
      }
    }
  }

  // ==================== عمليات المشتريات ====================

  // ⭐ شراء من مورد: يرفع كميات المخزون ويسجل حركة incoming
  Future<Purchase> createPurchase({
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    String? note,
    String? invoiceNumber,
  }) async {
    final userId = _db.getUserId();
    if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);
    if (items.isEmpty) throw Exception(LocalizationHelper.purchasesEmptyCart);

    final purchaseId = _uuid.v4();
    final total = items.fold<double>(0, (sum, i) => sum + i.subtotal);

    // ⭐ أولاً: حفظ الشراء محلياً
    final purchase = await _db.addPurchaseWithId(
      id: purchaseId,
      items: items,
      supplierId: supplierId,
      supplierName: supplierName,
      total: total,
      note: note,
      userId: userId,
      isSynced: false,
      invoiceNumber: (invoiceNumber == null || invoiceNumber.trim().isEmpty)
          ? null
          : invoiceNumber.trim(),
    );

    // ⭐ ثانياً: رفع كميات المخزون + تحديث تكلفة الشراء + تسجيل حركة لكل صنف
    for (final item in items) {
      final product = _db.getProductById(item.productId);
      if (product == null) continue;
      await _db.updateQuantity(item.productId, product.quantity + item.quantity);
      // ⭐ التكلفة تتبع آخر عملية شراء (المصدر الوحيد لتكلفة المنتج)
      if (item.costPrice > 0) {
        await _db.updateProductCost(item.productId, item.costPrice);
      }
      await _db.addMovement(
        productId: item.productId,
        productName: item.productName,
        type: MovementType.incoming,
        quantity: item.quantity,
        price: item.costPrice,
        total: item.subtotal,
        referenceId: purchaseId,
        note: note,
        userId: userId,
        supplierName: supplierName,
      );
    }

    _notifyDataChanged();

    // ⭐ ثالثاً: رفع مباشر إن أمكن
    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.addPurchase(purchase: purchase);
        await _db.markPurchaseAsSynced(purchaseId);
        AppConfig.log('✅ Purchase synced to Firebase: $purchaseId');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to sync purchase to Firebase', e);
      }
    }

    return purchase;
  }

  // ⭐ إرجاع للمورد: يدمج المرتجع داخل نفس سجل الشراء الأصلي
  // (لا ينشئ سجل مرتجع جديد) وينقص كميات المخزون ويسجل حركة return_out.
  // يرفض أي صنف ليس في الشراء الأصلي أو يتجاوز سقف الإرجاع.
  Future<Purchase> createSupplierReturn({
    required String originalPurchaseId,
    required List<PurchaseItem> returnItems,
    String? note,
  }) async {
    final userId = _db.getUserId();
    if (userId == null) throw Exception(LocalizationHelper.authUserNotAuthenticated);

    final original = _db.getPurchaseById(originalPurchaseId);
    if (original == null) {
      throw Exception(LocalizationHelper.purchasesOriginalNotFound);
    }
    if (!original.canBeReturned) {
      throw Exception(LocalizationHelper.purchasesAlreadyFullyReturned);
    }
    if (returnItems.isEmpty ||
        returnItems.every((i) => i.quantity <= QuantityFormat.epsilon)) {
      throw Exception(LocalizationHelper.purchasesEmptyCart);
    }

    // ⭐ التحقق من السقوف: المرتجع المحفوظ داخل السجل + المرتجعات القديمة المستقلة
    final returnedSoFar = <String, double>{};
    for (final item in original.returnedItems ?? const <PurchaseItem>[]) {
      returnedSoFar[item.productId] =
          (returnedSoFar[item.productId] ?? 0.0) + item.quantity;
    }
    for (final r in _db.getReturnPurchasesFor(originalPurchaseId)) {
      for (final item in r.items) {
        returnedSoFar[item.productId] = (returnedSoFar[item.productId] ?? 0) + item.quantity;
      }
    }
    final invalid = SuppliersStockPolicy.invalidReturnProducts(
      originalItems: original.items,
      returnedSoFarByProductId: returnedSoFar,
      newReturnByProductId:
          {for (final i in returnItems) i.productId: i.quantity},
    );
    if (invalid.isNotEmpty) {
      throw Exception('${LocalizationHelper.purchasesReturnExceedsCap}: $invalid');
    }

    // ⭐ منع النقص تحت الصفر
    for (final item in returnItems) {
      final product = _db.getProductById(item.productId);
      if (product == null) {
        throw Exception('${LocalizationHelper.purchasesProductNotFound}: ${item.productName}');
      }
      if (SuppliersStockPolicy.wouldGoNegative(
          currentQuantity: product.quantity, change: -item.quantity)) {
        throw Exception('${LocalizationHelper.purchasesInsufficientStock}: ${item.productName}');
      }
    }

    final returnTotalValue = returnItems.fold<double>(0, (sum, i) => sum + i.subtotal);

    // ⭐ خصم كميات المخزون + تسجيل حركة لكل صنف
    for (final item in returnItems) {
      final product = _db.getProductById(item.productId);
      if (product == null) continue;
      await _db.updateQuantity(item.productId, product.quantity - item.quantity);
      await _db.addMovement(
        productId: item.productId,
        productName: item.productName,
        type: MovementType.return_out,
        quantity: item.quantity,
        price: item.costPrice,
        total: item.subtotal,
        referenceId: originalPurchaseId,
        note: note,
        userId: userId,
        supplierName: original.supplierName,
      );
    }

    // ⭐ دمج المرتجع داخل سجل الشراء الأصلي نفسه
    final updatedOriginal = await _db.updatePurchaseWithReturn(
      purchaseId: originalPurchaseId,
      returnedItems: returnItems,
      returnTotal: returnTotalValue,
    );

    _notifyDataChanged();

    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.updatePurchaseWithReturn(
          id: originalPurchaseId,
          returnedItems: updatedOriginal.returnedItems ?? [],
          returnTotal: updatedOriginal.returnTotal ?? 0.0,
          isFullyReturned: updatedOriginal.isFullyReturned,
        );
        await _db.markPurchaseAsSynced(originalPurchaseId);
        AppConfig.log('✅ Purchase return merged into Firebase: $originalPurchaseId');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to sync purchase return to Firebase', e);
      }
    }

    return updatedOriginal;
  }

  // ⭐ حذف عملية (شراء أو مرتجع قديم مستقل): يعكس أثرها الصافي على المخزون
  // ثم يحذف من Hive وFirebase.
  // حذف شراء عليه إرجاع داخلي → يخصم الصافي فقط (المشترى − المرتجَع).
  Future<void> deletePurchaseById(String id) async {
    final purchase = _db.getPurchaseById(id);
    if (purchase == null) return;

    // ⭐ اتجاه العكس: حذف شراء ينقص، وحذف مرتجع يُرجع الكميات
    final isReturnRecord = purchase.isReturn;

    // صافي أثر كل منتج: للشراء = المشترى − المرتجع الداخلي؛ للمرتجع = كميته
    final netByProduct = <String, double>{};
    final nameByProduct = <String, String>{};
    for (final item in purchase.items) {
      netByProduct[item.productId] =
          (netByProduct[item.productId] ?? 0.0) + item.quantity;
      nameByProduct[item.productId] = item.productName;
    }
    if (!isReturnRecord) {
      for (final item in purchase.returnedItems ?? const <PurchaseItem>[]) {
        final current = netByProduct[item.productId];
        if (current == null) continue;
        netByProduct[item.productId] = current - item.quantity;
      }
    }

    // ⭐ تحقق شامل قبل أي تعديل (منع التطبيق الجزئي)
    netByProduct.forEach((productId, effect) {
      if (QuantityFormat.isZeroQty(effect)) return;
      final product = _db.getProductById(productId);
      if (product == null) return;
      final change = isReturnRecord ? effect : -effect;
      if (SuppliersStockPolicy.wouldGoNegative(
          currentQuantity: product.quantity, change: change)) {
        throw Exception(
            '${LocalizationHelper.purchasesDeleteBlockedNegative}: ${nameByProduct[productId]}');
      }
    });

    // ⭐ تطبيق الأثر
    for (final entry in netByProduct.entries) {
      if (QuantityFormat.isZeroQty(entry.value)) continue;
      final product = _db.getProductById(entry.key);
      if (product == null) continue;
      final change = isReturnRecord ? entry.value : -entry.value;
      await _db.updateQuantity(entry.key, product.quantity + change);
    }

    await _db.deletePurchaseLocal(id);
    _notifyDataChanged();

    await _db.addPendingDelete('purchase', id);

    if (_isOnline && _firebase.currentUser != null) {
      try {
        await _firebase.deletePurchase(id);
        await _db.removePendingDelete('purchase', id);
        AppConfig.log('✅ Purchase deleted from Firebase: $id');
      } catch (e) {
        AppConfig.logError('⚠️ Failed to delete purchase from Firebase', e);
      }
    }
  }

  // ==================== دوال مساعدة ====================

  void _notifyDataChanged() {
    _dataChangeNotifier.value++;
  }

  void clearErrors() {
    _syncErrors.clear();
  }

  // ⭐ دالة إجبارية للمزامنة - يمكن استدعاؤها من أي مكان
  Future<void> forceSync() async {
    AppConfig.log('===== ===== FORCE SYNC CALLED =====');
    await syncNow();
  }

  // ⭐ دالة للتحقق من عدد العناصر غير المتزامنة
  Map<String, int> getUnsyncedCount() {
    return {
      'products': _db.getUnsyncedProducts().length,
      'sales': _db.getUnsyncedSales().length,
      'movements': _db.getUnsyncedMovements().length,
      'suppliers': _db.getUnsyncedSuppliers().length,
      'purchases': _db.getUnsyncedPurchases().length,
      'customers': _db.getUnsyncedCustomers().length,
      'debt_transactions': _db.getUnsyncedDebtTransactions().length,
    };
  }
}
