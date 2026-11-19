-- Expenses; CHECKs repeat the request validation on purpose. PT: Despesas; os CHECKs repetem a validação de propósito.
-- Notes / Notas: docs/code-notes/expense.md#v8__create_expenses
create table expenses (
    id           uuid          not null,
    user_id      uuid          not null,
    category_id  uuid          not null,
    amount       numeric(12,2) not null,
    description  varchar(120)  not null,
    expense_date date          not null,
    created_at   timestamptz   not null,
    updated_at   timestamptz   not null,

    constraint pk_expenses primary key (id),
    constraint fk_expenses_users foreign key (user_id) references users (id) on delete cascade,
    -- NO ACTION, not RESTRICT: backs the 409 category-in-use and lets a user's delete cascade finish.
    -- PT: NO ACTION, não RESTRICT: sustenta o 409 category-in-use e deixa o delete em cascata de um usuário terminar.
    -- Notes / Notas: docs/code-notes/expense.md#fk_expenses_categories
    constraint fk_expenses_categories foreign key (category_id) references categories (id) on delete no action,
    constraint ck_expenses_amount_positive check (amount > 0),
    constraint ck_expenses_description_trimmed check (description <> '' and description = btrim(description)),
    -- Unicode Cc only; Cf is checked by the application. PT: Só Unicode Cc; o Cf é conferido pela aplicação.
    constraint ck_expenses_description_no_control_chars check (description !~ '[\u0001-\u001f\u007f-\u009f]'),
    -- Notes / Notas: docs/code-notes/expense.md#ck_expenses_date_min
    constraint ck_expenses_date_min check (expense_date >= date '2000-01-01'),
    constraint ck_expenses_updated_after_created check (updated_at >= created_at)
);

-- Serves the month list and the foreign key on user_id. PT: Atende a lista do mês e a FK de user_id.
-- Notes / Notas: docs/code-notes/expense.md#idx_expenses_user_date
create index idx_expenses_user_date on expenses (user_id, expense_date desc, created_at desc);

-- The foreign key on category_id, also used by the "in use" check. PT: A FK de category_id, usada também na checagem "em uso".
create index idx_expenses_category on expenses (category_id);
