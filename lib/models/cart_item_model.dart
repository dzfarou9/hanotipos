import 'product_model.dart';

class CartItem {
  final Product product;
  int quantity;
  double get subtotal => product.price * quantity;

  CartItem({
    required this.product,
    this.quantity = 1,
  });
}