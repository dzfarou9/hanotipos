// lib/config/firebase_config.dart

class FirebaseConfig {
  // ⭐ أسماء مجموعات Firestore
  static const String usersCollection = 'users';
  static const String productsCollection = 'products';
  static const String salesCollection = 'sales';
  static const String saleItemsCollection = 'sale_items';
  static const String subscriptionsCollection = 'subscriptions';
  static const String inventoryMovementsCollection = 'inventory_movements';
  static const String suppliersCollection = 'suppliers';
  static const String purchasesCollection = 'purchases';
  static const String customersCollection = 'customers';
  static const String debtTransactionsCollection = 'debt_transactions';

  // ⭐ فترة التجربة (7 أيام)
  static const int trialDays = 7;
}
