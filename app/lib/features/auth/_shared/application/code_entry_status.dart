/// Where a 6-digit code entry stands; both code screens keep it in their state and the View draws it.
/// PT: Em que pé está a digitação de um código de 6 dígitos; as duas telas de código o guardam no estado e a View o desenha.
/// Notes: docs/code-notes/app-auth.md#otpcodeinput
enum CodeEntryStatus {
  /// Waiting for the digits.
  /// PT: Esperando os dígitos.
  idle,

  /// The 6th digit went out; waiting for the server.
  /// PT: O 6º dígito foi enviado; esperando o servidor.
  verifying,

  /// The code was refused (or the check failed): boxes red and cleared.
  /// PT: O código foi recusado (ou a checagem falhou): caixas vermelhas e limpas.
  error,

  /// The code was accepted: boxes green for a moment, then the screen moves on.
  /// PT: O código foi aceito: caixas verdes por um instante, depois a tela avança.
  success,
}
