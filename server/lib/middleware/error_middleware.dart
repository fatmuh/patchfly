// Error middleware — converts thrown exceptions to JSON responses.

import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:logging/logging.dart';
import '../utils/json.dart';
import '../utils/json_response.dart';
import '../utils/jwt.dart' show AuthException;

Middleware errorMiddleware() {
  final log = Logger('ErrorHandler');
  return (inner) {
    return (request) async {
      try {
        return await inner(request);
      } on BadRequest catch (e) {
        return jsonResponse(
            {'error': 'bad_request', 'message': e.message}, status: 400);
      } on NotFound catch (e) {
        return jsonResponse(
            {'error': 'not_found', 'message': e.message}, status: 404);
      } on Conflict catch (e) {
        return jsonResponse(
            {'error': 'conflict', 'message': e.message}, status: 409);
      } on AuthException catch (e) {
        return jsonResponse(
            {'error': 'unauthorized', 'message': e.message}, status: 401);
      } on FormatException catch (e) {
        return jsonResponse(
            {'error': 'bad_request', 'message': e.message}, status: 400);
      } on StateError catch (e) {
        log.warning('StateError on ${request.method} ${request.url}: $e');
        return jsonResponse(
            {'error': 'internal', 'message': e.message}, status: 500);
      } on IOException catch (e) {
        log.warning('IO error on ${request.method} ${request.url}: $e');
        return jsonResponse(
            {'error': 'unavailable', 'message': 'Storage I/O error'},
            status: 503);
      } catch (e, st) {
        log.severe('Unhandled error on ${request.method} ${request.url}', e, st);
        return jsonResponse(
            {'error': 'internal', 'message': 'Internal server error'},
            status: 500);
      }
    };
  };
}
