-- Email verification (ADR 0012); null = not verified yet. PT: Verificação de email; nulo = ainda não verificado.
-- Notes / Notas: docs/code-notes/account-code.md#v3__add_users_email_verified_at
-- Nullable on purpose: existing accounts start unverified, and the column needs no default.
-- PT: Anulável de propósito: as contas existentes começam não verificadas, e a coluna não precisa de default.
alter table users add column email_verified_at timestamptz;
