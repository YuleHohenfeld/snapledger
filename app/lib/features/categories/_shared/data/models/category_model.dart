import 'package:flutter/foundation.dart';

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// The contract's `CategoryResponse`: a default (read-only, has a [key]) or one the user created.
/// PT: O `CategoryResponse` do contrato: uma padrão (somente leitura, tem [key]) ou uma criada pelo usuário.
/// Notes: docs/code-notes/app-categories.md#categorymodel
@immutable
final class CategoryModel {
  const CategoryModel({required this.id, required this.name, required this.isDefault, this.key});

  /// Throws [FormatException] naming the missing or malformed field, never its value.
  /// PT: Lança [FormatException] citando o campo ausente ou malformado, nunca o valor dele.
  factory CategoryModel.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final isDefault = json['isDefault'];
    if (id is! String || id.isEmpty) throw const FormatException('CategoryModel.id is missing');
    if (!_uuid.hasMatch(id)) throw const FormatException('CategoryModel.id is not a UUID');
    if (name is! String || name.isEmpty) throw const FormatException('CategoryModel.name is missing');
    if (isDefault is! bool) throw const FormatException('CategoryModel.isDefault is not a boolean');
    // The contract always sends `key` (null for own categories): a missing one is a contract break.
    // PT: O contrato sempre manda `key` (null nas próprias): ausente é quebra de contrato.
    if (!json.containsKey('key')) throw const FormatException('CategoryModel.key is missing');
    final key = json['key'];
    if (key != null && key is! String) throw const FormatException('CategoryModel.key is not text');
    return CategoryModel(id: id, name: name, isDefault: isDefault, key: key as String?);
  }

  final String id;

  /// The English name for a default; the user's own text for an own category.
  /// PT: O nome em inglês de uma padrão; o texto do próprio usuário numa categoria própria.
  final String name;
  final bool isDefault;

  /// Stable code of a default (`groceries`), used to translate it; null for own categories.
  /// PT: Código estável de uma padrão (`groceries`), usado para traduzi-la; null nas próprias.
  final String? key;

  @override
  bool operator ==(Object other) =>
      other is CategoryModel &&
      other.id == id &&
      other.name == name &&
      other.isDefault == isDefault &&
      other.key == key;

  @override
  int get hashCode => Object.hash(id, name, isDefault, key);

  // The name of an own category is personal data: it never reaches a log.
  // PT: O nome de uma categoria própria é dado pessoal: nunca vai para um log.
  @override
  String toString() => 'CategoryModel(id: $id, isDefault: $isDefault)';
}
