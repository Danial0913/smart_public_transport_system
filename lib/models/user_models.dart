class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.createdAt,
  });

  final int id;
  final String fullName;
  final String email;
  final String phone;
  final DateTime createdAt;

  factory AppUser.fromMap(Map<String, Object?> map) {
    return AppUser(
      id: map['id'] as int,
      fullName: map['full_name'] as String,
      email: map['email'] as String,
      phone: map['phone'] as String,
      createdAt: DateTime.parse(
        map['created_at'] as String,
      ),
    );
  }
}