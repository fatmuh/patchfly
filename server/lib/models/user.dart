// User model.

import 'models.dart' show Row;

class User {
  final String id;
  final String email;
  final String? name;
  final DateTime createdAt;
  final String? passwordHash; // null when loaded without secret

  User({
    required this.id,
    required this.email,
    this.name,
    required this.createdAt,
    this.passwordHash,
  });

  factory User.fromRow(Row r) => User(
        id: r.col<String>('id'),
        email: r.col<String>('email'),
        name: r.nullable<String>('name'),
        createdAt: r.dateTime('created_at'),
        passwordHash: r.nullable<String>('password_hash'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
      };
}
