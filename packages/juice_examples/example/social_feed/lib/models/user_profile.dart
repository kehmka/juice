class UserProfile {
  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final String image;
  final int age;

  const UserProfile({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.image,
    required this.age,
  });

  String get fullName => '$firstName $lastName';

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as int,
        username: json['username'] as String? ?? '',
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        email: json['email'] as String? ?? '',
        image: json['image'] as String? ?? '',
        age: json['age'] as int? ?? 0,
      );
}
