class User {
  final String id;
  final String login_id;
  final String name;
  final int? isActive;
  final String? createdAt;

  User({
    required this.id,
    required this.login_id,
    required this.name,
    this.isActive,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {

    return User(
      id: json['id'] as String,
      login_id: json['login_id'] as String,
      name: json['name'] as String,
      isActive: json['is_active'] != null ? json['is_active'] as int : 0,
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'login_id': login_id,
      'name':name,
      'isActive': isActive?.toString(),
      'created_at': createdAt,
    };
  }
}