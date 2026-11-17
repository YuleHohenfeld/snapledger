import 'package:flutter/foundation.dart';
import 'package:snapledger/core/api/json_body.dart';

/// Every problem `type` slug of the contract's error table, plus [unknown].
/// PT: Todo slug de `type` da tabela de erros do contrato, mais [unknown].
/// Notes: docs/code-notes/app-core.md#apifailure
enum ProblemType {
  validationError('validation-error'),
  unauthorized('unauthorized'),
  invalidCredentials('invalid-credentials'),
  invalidRefreshToken('invalid-refresh-token'),
  forbidden('forbidden'),
  defaultCategoryReadOnly('default-category-read-only'),
  notFound('not-found'),
  methodNotAllowed('method-not-allowed'),
  notAcceptable('not-acceptable'),
  emailAlreadyRegistered('email-already-registered'),
  categoryNameTaken('category-name-taken'),
  categoryInUse('category-in-use'),
  unsupportedMediaType('unsupported-media-type'),
  invalidCode('invalid-code'),
  invalidResetToken('invalid-reset-token'),
  tooManyRequests('too-many-requests'),
  internalError('internal-error'),

  /// `about:blank`, a missing type or a slug this app version does not know: branch on status.
  /// PT: `about:blank`, type ausente ou slug que esta versão do app não conhece: decida pelo status.
  unknown('');

  const ProblemType(this.slug);

  final String slug;

  static const _prefix = 'urn:snapledger:problem:';

  /// Maps the `type` field of a ProblemDetail; anything unexpected becomes [unknown].
  /// PT: Converte o campo `type` de um ProblemDetail; qualquer coisa inesperada vira [unknown].
  static ProblemType fromType(Object? type) {
    if (type is! String || !type.startsWith(_prefix)) return unknown;
    final slug = type.substring(_prefix.length);
    for (final value in values) {
      if (value != unknown && value.slug == slug) return value;
    }
    return unknown;
  }
}

/// A request that did not produce the expected answer; repositories throw only these.
/// PT: Uma requisição que não produziu a resposta esperada; repositórios só lançam estas.
/// Notes: docs/code-notes/app-core.md#apifailure
@immutable
sealed class ApiFailure implements Exception {
  const ApiFailure();
}

/// No response at all: offline, DNS, timeout, TLS failure or a cancelled request.
/// PT: Nenhuma resposta: offline, DNS, timeout, falha de TLS ou requisição cancelada.
final class NetworkFailure extends ApiFailure {
  const NetworkFailure();

  @override
  String toString() => 'NetworkFailure()';
}

/// The server answered, but not with the expected success body (ProblemDetail or malformed).
/// PT: O servidor respondeu, mas não com o corpo de sucesso esperado (ProblemDetail ou malformado).
/// Notes: docs/code-notes/app-core.md#apifailure
final class ProblemFailure extends ApiFailure {
  const ProblemFailure({
    required this.status,
    required this.type,
    this.fieldErrors = const [],
    this.errorId,
  });

  /// Reads a raw or decoded ProblemDetail body; anything else gives [ProblemType.unknown].
  /// PT: Lê um corpo ProblemDetail bruto ou decodificado; qualquer outra coisa dá [ProblemType.unknown].
  factory ProblemFailure.fromResponse(int status, Object? rawBody) {
    final body = decodeJsonObject(rawBody);
    if (body == null) {
      return ProblemFailure(status: status, type: ProblemType.unknown);
    }
    final errors = body['errors'];
    final errorId = body['errorId'];
    return ProblemFailure(
      status: status,
      type: ProblemType.fromType(body['type']),
      fieldErrors: List.unmodifiable(<String>[
        if (errors is List<Object?>)
          for (final error in errors)
            if (error is Map<String, Object?> && error['field'] is String) error['field']! as String,
      ]),
      errorId: errorId is String && errorId.isNotEmpty ? errorId : null,
    );
  }

  /// HTTP status; for a malformed success body it is the 2xx status that carried it.
  /// PT: Status HTTP; para um corpo de sucesso malformado é o status 2xx que o trouxe.
  final int status;
  final ProblemType type;

  /// Field names only: the text shown comes from l10n, never from the server.
  /// PT: Só nomes de campos: o texto exibido vem do l10n, nunca do servidor.
  final List<String> fieldErrors;

  /// Id of a `500` in the server logs, safe to show for support.
  /// PT: Id de um `500` nos logs do servidor, seguro para mostrar ao suporte.
  final String? errorId;

  @override
  String toString() => 'ProblemFailure($status, ${type.name})';
}
