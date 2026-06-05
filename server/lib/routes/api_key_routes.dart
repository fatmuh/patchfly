// API key routes.

import 'package:shelf/shelf.dart';
import '../services/api_key_service.dart';
import '../utils/json.dart';
import '../utils/json_response.dart';

class ApiKeyRoutes {
  final ApiKeyService keys;
  ApiKeyRoutes(this.keys);

  Future<Response> list(Request request) async {
    final list = await keys.listForUser(_userId(request));
    return jsonResponse({'apiKeys': list.map((k) => k.toJson()).toList()});
  }

  Future<Response> create(Request request) async {
    final body = await _readJson(request);
    final name = Validation.requireString(body, 'name', min: 1, max: 100);
    final expiresInDays = Validation.optionalInt(body, 'expiresInDays');

    final result = await keys.create(
      userId: _userId(request),
      name: name,
      expiresIn: expiresInDays != null ? Duration(days: expiresInDays) : null,
    );
    return jsonResponse(
      {
        'apiKey': result.record.toJson(),
        'plaintext': result.plaintext,
      },
      status: 201,
    );
  }

  Future<Response> revoke(Request request, String id) async {
    await keys.revoke(_userId(request), id);
    return jsonResponse({'deleted': true});
  }

  String _userId(Request req) {
    final id = req.context['userId'] as String?;
    if (id == null) throw StateError('userId missing in context');
    return id;
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
