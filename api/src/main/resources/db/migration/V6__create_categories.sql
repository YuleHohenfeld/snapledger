-- Default (user_id null) and own categories; CHECKs repeat the request validation on purpose.
-- PT: Categorias padrão (user_id nulo) e próprias; os CHECKs repetem a validação de propósito.
-- Notes / Notas: docs/code-notes/category.md#v6__create_categories
create table categories (
    id         uuid        not null,
    -- Null = default category, shared by every user. PT: Nulo = categoria padrão, de todos os usuários.
    -- Notes / Notas: docs/code-notes/category.md#user_id-column
    user_id    uuid,
    -- Stable code the app translates; null for own categories. PT: Código estável que o app traduz; nulo nas próprias.
    -- Notes / Notas: docs/code-notes/category.md#key-column
    key        varchar(30),
    -- Code points, like @CodePointLength(max = 40). PT: Code points, como o @CodePointLength(max = 40).
    name       varchar(40) not null,
    created_at timestamptz not null,

    constraint pk_categories primary key (id),
    constraint fk_categories_users foreign key (user_id) references users (id) on delete cascade,
    constraint ck_categories_name_trimmed check (name <> '' and name = btrim(name)),
    -- Unicode Cc only; Cf is checked by the application. PT: Só Unicode Cc; o Cf é conferido pela aplicação.
    constraint ck_categories_name_no_control_chars check (name !~ '[\u0001-\u001f\u007f-\u009f]'),
    -- Notes / Notas: docs/code-notes/category.md#ck_categories_key_only_default
    constraint ck_categories_key_only_default check (key is null or user_id is null),
    constraint ck_categories_key_format check (key is null or key ~ '^[a-z][a-z0-9_]{0,29}$')
);

-- Also serves the foreign key on user_id (it is the leading column). PT: Atende também a FK de user_id (é a primeira coluna).
-- Notes / Notas: docs/code-notes/category.md#uk_categories_user_name
create unique index uk_categories_user_name on categories (user_id, lower(name)) where user_id is not null;

-- Notes / Notas: docs/code-notes/category.md#uk_categories_default_name
create unique index uk_categories_default_name on categories (lower(name)) where user_id is null;

create unique index uk_categories_key on categories (key) where key is not null;
