// Auth routes — register & login.

import 'package:shelf/shelf.dart';
import '../services/user_service.dart';
import '../utils/json.dart';
import '../utils/json_response.dart';
import '../utils/jwt.dart';

class AuthRoutes {
  final UserService users;
  final JwtService jwt;
  AuthRoutes(this.users, this.jwt);

  Future<Response> register(Request request) async {
    final body = await _readJson(request);
    final email = Validation.requireString(body, 'email');
    final password = Validation.requireString(body, 'password', min: 8);
    final name = Validation.optionalString(body, 'name', max: 120);
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      throw BadRequest('email is not valid');
    }
    final user = await users.register(
      email: email,
      password: password,
      name: name,
    );
    final token = jwt.issue(userId: user.id, email: user.email);
    return jsonResponse({
      'user': user.toJson(),
      'token': token,
    }, status: 201);
  }

  Future<Response> login(Request request) async {
    final body = await _readJson(request);
    final email = Validation.requireString(body, 'email');
    final password = Validation.requireString(body, 'password');
    final user = await users.authenticate(
      email: email,
      password: password,
    );
    final token = jwt.issue(userId: user.id, email: user.email);
    return jsonResponse({
      'user': user.toJson(),
      'token': token,
    });
  }

  Future<Response> whoami(Request request) async {
    // The auth middleware sets request.context['userId'] before this runs.
    final userId = request.context['userId'] as String?;
    if (userId == null) {
      throw AuthException('Not authenticated');
    }
    final user = await users.findById(userId);
    if (user == null) {
      throw AuthException('User not found');
    }
    return jsonResponse({'user': user.toJson()});
  }
}

Future<Map<String, dynamic>> _readJson(Request request) async {
  final body = await request.readAsString();
  if (body.isEmpty) throw BadRequest('Request body is required');
  try {
    return JsonUtils.decodeMap(body);
  } on FormatException catch (e) {
    throw BadRequest('Invalid JSON: ${e.message}');
  }
}
