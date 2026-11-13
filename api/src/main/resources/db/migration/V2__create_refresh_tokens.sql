-- Refresh tokens (ADR 0002, ADR 0008); only the SHA-256 is stored. PT: Só o SHA-256 é gravado.
-- Notes / Notas: docs/code-notes/auth.md#v2__create_refresh_tokens

-- One row per session; rotation locks it, revocation updates it. PT: Uma linha por sessão; a rotação a trava, a revogação a atualiza.
-- Notes / Notas: docs/code-notes/auth.md#refresh_token_families
create table refresh_token_families (
    id         uuid        not null,
    user_id    uuid        not null,
    created_at timestamptz not null,
    revoked_at timestamptz,

    constraint pk_refresh_token_families primary key (id),
    -- Deleting a user (out of scope in v1) must not leave live sessions behind.
    -- PT: Apagar um usuário (fora do escopo da v1) não pode deixar sessões vivas para trás.
    constraint fk_refresh_token_families_user foreign key (user_id) references users (id) on delete cascade
);

-- Every foreign key has an index: the cascade delete and per-user cleanup search by user_id.
-- PT: Toda chave estrangeira tem índice: o delete em cascata e a limpeza por usuário buscam por user_id.
create index idx_refresh_token_families_user on refresh_token_families (user_id);

-- No user_id and no revoked_at here: both belong to the family, so they cannot disagree.
-- PT: Sem user_id e sem revoked_at aqui: os dois pertencem à família, então não podem divergir.
create table refresh_tokens (
    id         uuid        not null,
    family_id  uuid        not null,
    -- Not char(64): it would pad a broken hash silently. PT: Não char(64): ele completaria um hash quebrado sem avisar.
    -- Notes / Notas: docs/code-notes/auth.md#token_hash-column
    token_hash varchar(64) not null,
    expires_at timestamptz not null,
    used_at    timestamptz,
    created_at timestamptz not null,

    constraint pk_refresh_tokens primary key (id),
    -- Deleting a family (user deleted, future cleanup) deletes its tokens.
    -- PT: Apagar uma família (usuário apagado, limpeza futura) apaga os tokens dela.
    constraint fk_refresh_tokens_family foreign key (family_id) references refresh_token_families (id) on delete cascade,
    -- Also the index of the lookup by hash on every refresh and logout.
    -- PT: Também é o índice da busca por hash em todo refresh e logout.
    constraint uk_refresh_tokens_token_hash unique (token_hash),
    constraint ck_refresh_tokens_token_hash_hex check (token_hash ~ '^[0-9a-f]{64}$'),
    constraint ck_refresh_tokens_expires_after_creation check (expires_at > created_at)
);

-- Every foreign key has an index: the cascade delete from a family searches by family_id.
-- PT: Toda chave estrangeira tem índice: o delete em cascata a partir de uma família busca por family_id.
create index idx_refresh_tokens_family on refresh_tokens (family_id);
