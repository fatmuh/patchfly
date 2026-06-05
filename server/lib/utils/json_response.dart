// Convenience for building JSON responses.

import 'dart:convert';
import 'package:shelf/shelf.dart';

Response jsonResponse(Object? data, {int status = 200}) {
  return Response(
    status,
    body: jsonEncode(data),
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
