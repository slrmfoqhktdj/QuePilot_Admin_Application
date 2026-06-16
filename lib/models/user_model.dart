class User {
  final String id;
  final String login_id;
  final String name;
  final int? isActive;

  User({
    required this.id,
    required this.login_id,
    required this.name,
    this.isActive,
  });

  factory User.fromJson(Map<String, dynamic> json) {

    return User(
      id: json['id'] as String,
      login_id: json['login_id'] as String,
      name: json['name'] as String,
      // auth: (json['auth'] as List<dynamic>)
      //     .map((e) => UserAuth.fromJson(e as Map<String, dynamic>))
      //     .toList(),
      isActive: json['is_active'] != null ? json['is_active'] as int : 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'login_id': login_id,
      'name':name,
      // 'auth': auth?.map((e) => e.toJson()).toList(),
      'isActive': isActive?.toString(),
    };
  }
}