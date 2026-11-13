-- Accounts; CHECKs repeat the request validation on purpose. PT: Contas; os CHECKs repetem a validação de propósito.
-- Notes / Notas: docs/code-notes/user.md#v1__create_users
create table users (
    id            uuid         not null,
    -- Code points, like @CodePointLength(max = 80). PT: Code points, como o @CodePointLength(max = 80).
    -- Notes / Notas: docs/code-notes/user.md#name-column
    name          varchar(80)  not null,
    email         varchar(254) not null,
    -- Bcrypt (60) plus the {bcrypt} prefix fits. PT: Cabe o bcrypt (60) mais o prefixo {bcrypt}.
    -- Notes / Notas: docs/code-notes/user.md#password_hash-column
    password_hash varchar(72)  not null,
    -- No column default: the contract default (BRL) is applied once, in the application.
    -- PT: Sem default na coluna: o default do contrato (BRL) é aplicado uma vez só, na aplicação.
    currency      varchar(3)   not null,
    created_at    timestamptz  not null,

    constraint pk_users primary key (id),
    -- Case-insensitive because emails are stored lowercase. PT: Insensível a maiúsculas, pois o email é gravado em minúsculas.
    -- Notes / Notas: docs/code-notes/user.md#uk_users_email
    constraint uk_users_email unique (email),
    constraint ck_users_email_lowercase check (email = lower(email)),
    -- Printable ASCII without space (0x21 to 0x7E): rejects accents and any whitespace anywhere.
    -- PT: ASCII imprimível sem espaço (0x21 a 0x7E): rejeita acentos e qualquer espaço em qualquer posição.
    constraint ck_users_email_ascii_no_whitespace check (email ~ '^[!-~]+$'),
    -- Notes / Notas: docs/code-notes/user.md#ck_users_name_trimmed
    constraint ck_users_name_trimmed check (name <> '' and name = btrim(name)),
    -- Unicode Cc only; Cf is checked by the application. PT: Só Unicode Cc; o Cf é conferido pela aplicação.
    -- Notes / Notas: docs/code-notes/user.md#ck_users_name_no_control_chars
    constraint ck_users_name_no_control_chars check (name !~ '[\u0001-\u001f\u007f-\u009f]'),
    -- Only a real bcrypt hash, never plain text. PT: Só um hash bcrypt real, nunca texto puro.
    -- Notes / Notas: docs/code-notes/user.md#ck_users_password_hash_bcrypt
    constraint ck_users_password_hash_bcrypt
        check (password_hash ~ '^(\{bcrypt\})?\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$'),
    constraint ck_users_currency_format check (currency ~ '^[A-Z]{3}$')
);
