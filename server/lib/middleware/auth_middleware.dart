// Authentication middleware.

import 'package:shelf/shelf.dart';
import '../services/api_key_service.dart';
import '../services/user_service.dart';
import '../utils/json_response.dart';
import '../utils/jwt.dart';

const _bearerPrefix = 'Bearer ';

class AuthMiddleware {
  final JwtService jwt;
  final ApiKeyService apiKeys;
  final UserService users;

  AuthMiddleware(this.jwt, this.apiKeys, this.users);

  Middleware get middleware => (inner) {
        return (request) async {
          final header = request.headers['authorization'];
          if (header == null || !header.startsWith(_bearerPrefix)) {
            return _unauthorized('Missing bearer token');
          }
          final token = header.substring(_bearerPrefix.length).trim();

          try {
            final userId = await _resolve(token);
            final updated = request.change(context: {
              ...request.context,
              'userId': userId,
            });
            return inner(updated);
          } on AuthException catch (e) {
            return _unauthorized(e.message);
          } catch (_) {
            return _unauthorized('Authentication failed');
          }
        };
      };

  Future<String> _resolve(String token) async {
    if (token.startsWith(ApiKeyService.keyPrefixLiteral)) {
      final r = await apiKeys.verify(token);
      return r.userId;
    }
    final payload = jwt.verify(token);
    return payload.userId;
  }

  Response _unauthorized(String msg) => jsonResponse(
        {'error': 'unauthorized', 'message': msg},
        status: 401,
      );
}
