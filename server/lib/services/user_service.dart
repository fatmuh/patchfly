// User service: registration and authentication.

import '../db/database.dart';
import '../models/user.dart';
import '../models/models.dart' show firstRow;
import '../utils/hash.dart';
import '../utils/json.dart';
import '../utils/jwt.dart' show AuthException;

export '../utils/jwt.dart' show AuthException;

class UserService {
  final Database _db;
  UserService(this._db);

  Future<User> register({
    required String email,
    required String password,
    String? name,
  }) async {
    final existing = await _db.queryValue(
      'SELECT id FROM users WHERE email = @e',
      {'e': email.toLowerCase()},
    );
    if (existing != null) {
      throw Conflict('Email already registered');
    }

    final hash = PasswordHasher.hash(password);
    final rows = await _db.query(
      '''INSERT INTO users (email, password_hash, name)
         VALUES (@e, @p, @n)
         RETURNING id, email, name, created_at''',
      {'e': email.toLowerCase(), 'p': hash, 'n': name},
    );
    return firstRow(rows, User.fromRow)!;
  }

  Future<User> authenticate({
    required String email,
    required String password,
  }) async {
    final rows = await _db.query(
      '''SELECT id, email, name, created_at, password_hash
         FROM users WHERE email = @e''',
      {'e': email.toLowerCase()},
    );
    if (rows.isEmpty) {
      throw AuthException('Invalid credentials');
    }
    final user = firstRow(rows, User.fromRow)!;
    if (user.passwordHash == null ||
        !PasswordHasher.verify(password, user.passwordHash!)) {
      throw AuthException('Invalid credentials');
    }
    return user;
  }

  Future<User?> findById(String id) async {
    final rows = await _db.query(
      'SELECT id, email, name, created_at FROM users WHERE id = @i',
      {'i': id},
    );
    return firstRow(rows, User.fromRow);
  }
}
