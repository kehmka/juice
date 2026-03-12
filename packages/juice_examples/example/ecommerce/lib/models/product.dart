class Product {
  final int id;
  final String title;
  final String description;
  final double price;
  final double discountPercentage;
  final double rating;
  final int stock;
  final String brand;
  final String category;
  final String thumbnail;
  final List<String> images;

  const Product({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    this.discountPercentage = 0,
    this.rating = 0,
    this.stock = 0,
    this.brand = '',
    this.category = '',
    this.thumbnail = '',
    this.images = const [],
  });

  double get discountedPrice => price * (1 - discountPercentage / 100);

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as int,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        price: (json['price'] as num).toDouble(),
        discountPercentage:
            (json['discountPercentage'] as num?)?.toDouble() ?? 0,
        rating: (json['rating'] as num?)?.toDouble() ?? 0,
        stock: json['stock'] as int? ?? 0,
        brand: json['brand'] as String? ?? '',
        category: json['category'] as String? ?? '',
        thumbnail: json['thumbnail'] as String? ?? '',
        images: (json['images'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );
}
