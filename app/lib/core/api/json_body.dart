import 'dart:convert';

/// Decodes a raw response body into a JSON array of objects, or null when it is anything else.
/// PT: Decodifica o corpo bruto de uma resposta num array JSON de objetos, ou null quando é outra coisa.
/// Notes: docs/code-notes/app-core.md#apiclient
List<Map<String, Object?>>? decodeJsonList(Object? body) {
  final Object? decoded;
  if (body is List<Object?>) {
    decoded = body;
  } else if (body is String && body.isNotEmpty) {
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
  } else {
    return null;
  }
  if (decoded is! List<Object?>) return null;
  final items = <Map<String, Object?>>[];
  for (final item in decoded) {
    if (item is! Map<String, Object?>) return null;
    items.add(item);
  }
  return List.unmodifiable(items);
}

/// Decodes a raw response body into a JSON object, or null when it is anything else.
/// PT: Decodifica o corpo bruto de uma resposta num objeto JSON, ou null quando é outra coisa.
/// Notes: docs/code-notes/app-core.md#apiclient
Map<String, Object?>? decodeJsonObject(Object? body) {
  if (body is Map<String, Object?>) return body;
  if (body is! String || body.isEmpty) return null;
  try {
    final decoded = jsonDecode(body);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}
