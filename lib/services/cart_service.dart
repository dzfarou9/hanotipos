import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../helpers/localization_helper.dart';
import '../models/product_model.dart';
import '../models/cart_item_model.dart';

class CartService extends ChangeNotifier {
  static const Uuid _uuid = Uuid();
  final List<CartItem> _items = [];
  double _discount = 0;
  double _taxRate = 0;
  String _paymentMethod = 'Cash';
  String? _customerName;
  String? _customerId;
  
  // Hold orders
  final List<HeldOrder> _heldOrders = [];

  List<CartItem> get items => List.unmodifiable(_items);
  double get discount => _discount;
  double get taxRate => _taxRate;
  String get paymentMethod => _paymentMethod;
  String? get customerName => _customerName;
  String? get customerId => _customerId;
  List<HeldOrder> get heldOrders => List.unmodifiable(_heldOrders);
  bool get hasHeldOrders => _heldOrders.isNotEmpty;

  int get totalItems => _items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal => _items.fold(0, (sum, item) => sum + item.subtotal);

  double get taxAmount => subtotal * (_taxRate / 100);

  double get total {
    final t = subtotal - _discount + taxAmount;
    return t < 0 ? 0 : t;
  }

  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  void setPaymentMethod(String method) {
    _paymentMethod = method;
    notifyListeners();
  }

  void setCustomer(String? name, String? id) {
    _customerName = name;
    _customerId = id;
    notifyListeners();
  }

  void setDiscount(double discount) {
    // ⭐ منع خصم سالب أو أكبر من قيمة السلة
    final maxDiscount = subtotal;
    _discount = discount.clamp(0.0, maxDiscount);
    notifyListeners();
  }

  void setTaxRate(double taxRate) {
    // ⭐ منع قيم ضريبية سلبية
    _taxRate = taxRate < 0 ? 0 : taxRate;
    notifyListeners();
  }

  void addProduct(Product product, {int quantity = 1}) {
    final existingIndex = _items.indexWhere(
      (item) => item.product.id == product.id,
    );

    if (existingIndex != -1) {
      _items[existingIndex].quantity += quantity;
    } else {
      _items.add(CartItem(product: product, quantity: quantity));
    }
    notifyListeners();
  }

  void addProducts(List<Product> products) {
    for (var product in products) {
      final existingIndex = _items.indexWhere(
        (item) => item.product.id == product.id,
      );
      if (existingIndex != -1) {
        _items[existingIndex].quantity += 1;
      } else {
        _items.add(CartItem(product: product, quantity: 1));
      }
    }
    notifyListeners();
  }

  void updateQuantity(int index, int quantity) {
    if (index >= 0 && index < _items.length) {
      if (quantity <= 0) {
        _items.removeAt(index);
      } else {
        _items[index].quantity = quantity;
      }
      notifyListeners();
    }
  }

  void incrementQuantity(int index) {
    if (index >= 0 && index < _items.length) {
      _items[index].quantity += 1;
      notifyListeners();
    }
  }

  void decrementQuantity(int index) {
    if (index >= 0 && index < _items.length) {
      if (_items[index].quantity > 1) {
        _items[index].quantity -= 1;
      } else {
        _items.removeAt(index);
      }
      notifyListeners();
    }
  }

  void removeItem(int index) {
    if (index >= 0 && index < _items.length) {
      _items.removeAt(index);
      notifyListeners();
    }
  }

  /// ⭐ إعادة منتج محذوف إلى نفس موقعه (لتراجع عن الحذف).
  void reinsertItem(int index, CartItem item) {
    final safe = index.clamp(0, _items.length);
    _items.insert(safe, item);
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    _discount = 0;
    _taxRate = 0;
    _paymentMethod = 'Cash';
    _customerName = null;
    _customerId = null;
    notifyListeners();
  }

  // ==================== Hold Order Methods ====================

  /// Save current cart as held order
  String holdOrder({String? label}) {
    if (_items.isEmpty) return '';
    
    final heldOrder = HeldOrder(
      id: _uuid.v4(),
      label: label ?? LocalizationHelper.order(_heldOrders.length + 1),
      items: List<CartItem>.from(_items.map((e) => CartItem(
        product: e.product,
        quantity: e.quantity,
      ))),
      discount: _discount,
      taxRate: _taxRate,
      paymentMethod: _paymentMethod,
      createdAt: DateTime.now(),
    );
    
    _heldOrders.add(heldOrder);
    clearCart();
    notifyListeners();
    return heldOrder.id;
  }

  /// Restore a held order to the cart
  void restoreHeldOrder(String orderId) {
    final index = _heldOrders.indexWhere((o) => o.id == orderId);
    if (index != -1) {
      final heldOrder = _heldOrders[index];
      
      // Clear current cart and restore held order
      _items.clear();
      for (var item in heldOrder.items) {
        _items.add(CartItem(
          product: item.product,
          quantity: item.quantity,
        ));
      }
      _discount = heldOrder.discount;
      _taxRate = heldOrder.taxRate;
      _paymentMethod = heldOrder.paymentMethod;
      
      // Remove from held orders
      _heldOrders.removeAt(index);
      notifyListeners();
    }
  }

  /// Delete a held order
  void deleteHeldOrder(String orderId) {
    _heldOrders.removeWhere((o) => o.id == orderId);
    notifyListeners();
  }

  /// Get total count of held orders
  int get heldOrderCount => _heldOrders.length;
}

class HeldOrder {
  final String id;
  final String label;
  final List<CartItem> items;
  final double discount;
  final double taxRate;
  final String paymentMethod;
  final DateTime createdAt;

  HeldOrder({
    required this.id,
    required this.label,
    required this.items,
    required this.discount,
    required this.taxRate,
    this.paymentMethod = 'Cash',
    required this.createdAt,
  });

  double get subtotal => items.fold(0, (sum, item) => sum + item.subtotal);
  double get taxAmount => subtotal * (taxRate / 100);
  double get total {
    final t = subtotal - discount + taxAmount;
    return t < 0 ? 0 : t;
  }

  int get totalItems => items.fold(0, (sum, item) => sum + item.quantity);
}