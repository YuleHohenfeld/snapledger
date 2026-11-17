-- One-time codes for email verification and password reset (ADR 0012); only the HMAC is stored.
-- PT: Códigos de uso único para verificar email e redefinir senha (ADR 0012); só o HMAC é gravado.
-- Notes / Notas: docs/code-notes/account-code.md#v4__create_account_codes
create table account_codes (
    id                uuid        not null,
    user_id           uuid        not null,
    purpose           varchar(32) not null,
    -- Not char(64): it would pad a broken hash silently. PT: Não char(64): ele completaria um hash quebrado sem avisar.
    code_hash         varchar(64) not null,
    sent_at           timestamptz not null,
    expires_at        timestamptz not null,
    attempts          integer     not null,
    used_at           timestamptz,
    -- Resend limits live here, per (user, purpose), so they survive restarts and many instances.
    -- PT: Os limites de reenvio vivem aqui, por (usuário, finalidade), então sobrevivem a reinícios e a várias instâncias.
    -- Notes / Notas: docs/code-notes/account-code.md#resend-window
    window_started_at timestamptz not null,
    sends_in_window   integer     not null,
    -- Wrong-guess budget per (user, purpose): NOT reset by a new code, so asking for fresh codes does not buy fresh guesses.
    -- PT: Orçamento de palpites errados por (usuário, finalidade): um código novo NÃO o zera, então pedir códigos novos não compra palpites novos.
    -- Notes / Notas: docs/code-notes/account-code.md#failure-budget
    failed_window_started_at timestamptz,
    failed_in_window  integer     not null default 0,
    created_at        timestamptz not null,

    constraint pk_account_codes primary key (id),
    -- Deleting a user deletes their codes. PT: Apagar um usuário apaga os códigos dele.
    constraint fk_account_codes_user foreign key (user_id) references users (id) on delete cascade,
    -- One live code per (user, purpose); a new request replaces the row. Its index also serves the
    -- foreign key (user_id is its first column), so no separate idx_ is needed.
    -- PT: Um código vivo por (usuário, finalidade); um pedido novo substitui a linha. O índice dela
    --     também atende a chave estrangeira (user_id é a primeira coluna), então não há idx_ separado.
    -- Notes / Notas: docs/code-notes/account-code.md#uk_account_codes_user_purpose
    constraint uk_account_codes_user_purpose unique (user_id, purpose),
    constraint ck_account_codes_purpose check (purpose in ('EMAIL_VERIFICATION', 'PASSWORD_RESET')),
    constraint ck_account_codes_code_hash_hex check (code_hash ~ '^[0-9a-f]{64}$'),
    constraint ck_account_codes_attempts_not_negative check (attempts >= 0),
    constraint ck_account_codes_failed_in_window_not_negative check (failed_in_window >= 0),
    constraint ck_account_codes_sends_in_window_positive check (sends_in_window >= 1),
    constraint ck_account_codes_expires_after_sent check (expires_at > sent_at)
);
