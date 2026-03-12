class ProductCategory {
  final String slug;
  final String name;
  final String url;

  const ProductCategory({
    required this.slug,
    required this.name,
    required this.url,
  });

  factory ProductCategory.fromJson(dynamic json) {
    if (json is String) {
      return ProductCategory(slug: json, name: json, url: '');
    }
    final map = json as Map<String, dynamic>;
    return ProductCategory(
      slug: map['slug'] as String? ?? '',
      name: map['name'] as String? ?? '',
      url: map['url'] as String? ?? '',
    );
  }
}
