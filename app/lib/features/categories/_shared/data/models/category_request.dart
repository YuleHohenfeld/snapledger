import 'package:flutter/foundation.dart';

/// Body of `POST /categories` and `PATCH /categories/{id}`: `{ "name": ... }`.
/// PT: Corpo de `POST /categories` e `PATCH /categories/{id}`: `{ "name": ... }`.
/// Notes: docs/code-notes/app-categories.md#categorymodel
@immutable
final class CategoryRequest {
  const CategoryRequest({required this.name});

  final String name;

  Map<String, Object?> toJson() => {'name': name};

  // The name is personal data: `toString` never shows it.
  // PT: O nome é dado pessoal: o `toString` nunca o mostra.
  @override
  String toString() => 'CategoryRequest(name: ***)';
}
