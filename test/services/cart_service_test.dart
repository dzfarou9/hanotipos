// test/services/cart_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/product_model.dart';
import 'package:pos_app/services/cart_service.dart';

Product p(String id, {double price = 100, String unit = 'piece'}) => Product(
      id: id, name: 'P$id', category: 'G', price: price, quantity: 50,
      userId: 'u1', unit: unit,
    );

void main() {
  test('addProduct accepts fractional quantity', () {
    final cart = CartService();
    cart.addProduct(p('p1'), quantity: 0.85);
    expect(cart.items.single.quantity, 0.85);
    expect(cart.items.single.subtotal, 85.0);
  });

  test('adding same weighted product twice accumulates fractions', () {
    final cart = CartService();
    cart.addProduct(p('p1'), quantity: 0.85);
    cart.addProduct(p('p1'), quantity: 0.4);
    expect(cart.items.single.quantity, closeTo(1.25, 0.0001));
  });

  test('totalItems is double sum', () {
    final cart = CartService();
    cart.addProduct(p('p1'), quantity: 0.5);
    cart.addProduct(p('p2'));
    expect(cart.totalItems, closeTo(1.5, 0.0001));
  });

  test('decrement removes when quantity reaches zero (epsilon)', () {
    final cart = CartService();
    cart.addProduct(p('p1'), quantity: 0.5);
    cart.decrementQuantity(0);
    expect(cart.isEmpty, isTrue);
  });

  test('updateQuantity accepts fractional', () {
    final cart = CartService();
    cart.addProduct(p('p1'));
    cart.updateQuantity(0, 2.75);
    expect(cart.items.single.quantity, 2.75);
  });
}
