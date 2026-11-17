-- The short-lived grant a verified reset code buys (ADR 0014); only the SHA-256 of the token is stored.
-- PT: A permissão de vida curta que um código de redefinição verificado compra (ADR 0014); só o SHA-256 do token é gravado.
-- Notes / Notas: docs/code-notes/auth.md#v5__create_password_reset_grants
create table password_reset_grants (
    id         uuid        not null,
    user_id    uuid        not null,
    -- SHA-256 hex of a 256-bit random token. Not char(64): it would pad a broken hash silently.
    -- PT: SHA-256 em hex de um token aleatório de 256 bits. Não char(64): ele completaria um hash quebrado sem avisar.
    token_hash varchar(64) not null,
    expires_at timestamptz not null,
    used_at    timestamptz,
    created_at timestamptz not null,

    constraint pk_password_reset_grants primary key (id),
    -- Deleting a user deletes the grant. PT: Apagar um usuário apaga a permissão.
    constraint fk_password_reset_grants_user foreign key (user_id) references users (id) on delete cascade,
    -- One live grant per user; a new verify replaces the row. Its index also serves the foreign key.
    -- PT: Uma permissão viva por usuário; um verify novo substitui a linha. O índice dela também atende a chave estrangeira.
    constraint uk_password_reset_grants_user unique (user_id),
    -- Confirm looks the grant up by this hash (a credential lookup). PT: O confirm busca a permissão por este hash (busca de credencial).
    constraint uk_password_reset_grants_token_hash unique (token_hash),
    constraint ck_password_reset_grants_token_hash_hex check (token_hash ~ '^[0-9a-f]{64}$'),
    constraint ck_password_reset_grants_expires_after_created check (expires_at > created_at)
);
