-- The 8 default categories; fixed ids so every environment (and the tests) agree. Never edited: a change is a new migration.
-- PT: As 8 categorias padrão; ids fixos para todos os ambientes (e os testes) concordarem. Nunca editada: mudança é migration nova.
-- Notes / Notas: docs/code-notes/category.md#v7__seed_default_categories
insert into categories (id, user_id, key, name, created_at) values
    ('c0000000-0000-4000-8000-000000000001', null, 'food',      'Food',      timestamptz '2026-11-01 00:00:00+00'),
    ('c0000000-0000-4000-8000-000000000002', null, 'groceries', 'Groceries', timestamptz '2026-11-01 00:00:00+00'),
    ('c0000000-0000-4000-8000-000000000003', null, 'transport', 'Transport', timestamptz '2026-11-01 00:00:00+00'),
    ('c0000000-0000-4000-8000-000000000004', null, 'housing',   'Housing',   timestamptz '2026-11-01 00:00:00+00'),
    ('c0000000-0000-4000-8000-000000000005', null, 'health',    'Health',    timestamptz '2026-11-01 00:00:00+00'),
    ('c0000000-0000-4000-8000-000000000006', null, 'leisure',   'Leisure',   timestamptz '2026-11-01 00:00:00+00'),
    ('c0000000-0000-4000-8000-000000000007', null, 'education', 'Education', timestamptz '2026-11-01 00:00:00+00'),
    ('c0000000-0000-4000-8000-000000000008', null, 'other',     'Other',     timestamptz '2026-11-01 00:00:00+00');
