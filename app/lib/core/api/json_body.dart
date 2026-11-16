import 'dart:convert';

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
