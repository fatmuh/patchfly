// JWT helpers using dart_jsonwebtoken 2.x.

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import '../config.dart';

class JwtService {
  final AppConfig _cfg;

  JwtService(this._cfg);

  String issue({
    required String userId,
    required String email,
  }) {
    final jwt = JWT(
      {
        'sub': userId,
        'email': email,
      },
      issuer: 'patchfly',
    );
    return jwt.sign(
      SecretKey(_cfg.jwtSecret),
      expiresIn: Duration(hours: _cfg.jwtExpiryHours),
    );
  }

  JwtPayload verify(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_cfg.jwtSecret));
      final payload = jwt.payload as Map<String, dynamic>;
      return JwtPayload(
        userId: payload['sub'] as String,
        email: payload['email'] as String,
      );
    } on JWTExpiredException {
      throw AuthException('Token expired');
    } on JWTException catch (e) {
      throw AuthException('Invalid token: ${e.message}');
    } on FormatException {
      throw AuthException('Malformed token');
    }
  }
}

class JwtPayload {
  final String userId;
  final String email;
  JwtPayload({required this.userId, required this.email});
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => 'AuthException: $message';
}
