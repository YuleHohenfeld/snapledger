/// Why a category name was refused on the device; the View turns it into text.
/// PT: Por que um nome de categoria foi recusado no aparelho; a View o transforma em texto.
enum CategoryNameError { required, tooLong, invalidChars }

/// Limit copied from docs/api-contract.md (categories); the API stays the authority.
/// PT: Limite copiado do docs/api-contract.md (categorias); a API continua sendo a autoridade.
const categoryNameMaxCodePoints = 40;

// Control (Cc), format (Cf) and lone surrogate (Cs) code points, like the API's NoControlCharacters.
// PT: Code points de controle (Cc), formatação (Cf) e surrogate sozinho (Cs), como o NoControlCharacters da API.
final _invisible = RegExp(r'[\p{Cc}\p{Cf}\p{Cs}]', unicode: true);

/// Category name: ends trimmed, 1-40 code points (an emoji is one), no invisible characters.
/// PT: Nome de categoria: pontas aparadas, 1-40 code points (um emoji é um), sem caracteres invisíveis.
/// Notes: docs/code-notes/app-categories.md#validatecategoryname
CategoryNameError? validateCategoryName(String? value) {
  final name = (value ?? '').trim();
  if (name.isEmpty) return CategoryNameError.required;
  if (_invisible.hasMatch(name)) return CategoryNameError.invalidChars;
  if (name.runes.length > categoryNameMaxCodePoints) return CategoryNameError.tooLong;
  return null;
}
