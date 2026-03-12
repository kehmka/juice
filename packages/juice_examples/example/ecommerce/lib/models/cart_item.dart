class CartItem {
  final int productId;
  final String title;
  final double price;
  final String thumbnail;
  final int quantity;

  const CartItem({
    required this.productId,
    required this.title,
    required this.price,
    this.thumbnail = '',
    this.quantity = 1,
  });

  CartItem copyWith({int? quantity}) {
    return CartItem(
      productId: productId,
      title: title,
      price: price,
      thumbnail: thumbnail,
      quantity: quantity ?? this.quantity,
    );
  }

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'title': title,
        'price': price,
        'thumbnail': thumbnail,
        'quantity': quantity,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        productId: json['productId'] as int,
        title: json['title'] as String,
        price: (json['price'] as num).toDouble(),
        thumbnail: json['thumbnail'] as String? ?? '',
        quantity: json['quantity'] as int? ?? 1,
      );
}
