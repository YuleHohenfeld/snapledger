# Code notes

Code comments in SnapLedger are short: one line that says what the element guarantees (or a
warning the caller must see), its Portuguese translation, and a link to a note here. The long
**why** (trade-offs, race conditions, alternatives that were rejected, links to ADRs) lives in
these files, one per feature area.

**PT:** Os comentários de código do SnapLedger são curtos: uma linha que diz o que o elemento
garante (ou um aviso que quem chama precisa ver), a tradução em português e um link para uma nota
aqui. O **porquê** longo (trade-offs, condições de corrida, alternativas descartadas, links para
ADRs) fica nestes arquivos, um por área de feature.

## Convention

- One file per area: `docs/code-notes/<area>.md` (for example [`user.md`](user.md),
  [`auth.md`](auth.md); [`security.md`](security.md) holds shared security code and the database
  and logging configuration). Migrations go in the area of the table they create. App notes
  start with `app-` (`app-core.md`, `app-auth.md`, `app-expenses.md`...) and are created with the
  first code that links to them.
- One `##` section per class or file, one `###` section per method, column or constraint that
  needs an explanation. Headings use the code name (`## User`, `### markUsed`,
  `### ck_users_email_lowercase`), so anchors are stable lowercase slugs
  (`#user`, `#markused`, `#ck_users_email_lowercase`).
- Each section is bilingual: the English text first, then the Portuguese translation in
  paragraphs that start with **PT:**.
- The code points to the note with a repository-relative path, which VS Code and GitHub resolve
  from the workspace root:
  - Java: `Notes: docs/code-notes/auth.md#markused` inside the Javadoc or `//` comment.
  - SQL: `-- Notes / Notas: docs/code-notes/user.md#ck_users_email_lowercase`.
  - Dart: `/// Notes: docs/code-notes/app-core.md#authinterceptor` in the doc comment.
- When the code changes, update its note **in the same change**. When a note is renamed, update
  every link to its anchor.
- Decisions that affect more than one class still belong in an ADR (`docs/decisions/`); a note
  links to the ADR instead of repeating it.

**PT:**

- Um arquivo por área: `docs/code-notes/<area>.md` (por exemplo [`user.md`](user.md),
  [`auth.md`](auth.md); o [`security.md`](security.md) guarda o código de segurança compartilhado
  e a configuração de banco e de log). Migrations ficam na área da tabela que criam. As notas do
  app começam com `app-` (`app-core.md`, `app-auth.md`, `app-expenses.md`...) e são criadas junto
  com o primeiro código que aponta para elas.
- Uma seção `##` por classe ou arquivo, uma seção `###` por método, coluna ou constraint que
  precisa de explicação. Os títulos usam o nome do código (`## User`, `### markUsed`,
  `### ck_users_email_lowercase`), então as âncoras são slugs estáveis em minúsculas
  (`#user`, `#markused`, `#ck_users_email_lowercase`).
- Cada seção é bilíngue: o texto em inglês primeiro, depois a tradução em português em
  parágrafos que começam com **PT:**.
- O código aponta para a nota com um caminho relativo ao repositório, que o VS Code e o GitHub
  resolvem a partir da raiz do workspace:
  - Java: `Notes: docs/code-notes/auth.md#markused` dentro do Javadoc ou do comentário `//`.
  - SQL: `-- Notes / Notas: docs/code-notes/user.md#ck_users_email_lowercase`.
  - Dart: `/// Notes: docs/code-notes/app-core.md#authinterceptor` no comentário de documentação.
- Quando o código muda, atualize a nota dele **na mesma mudança**. Quando uma nota é renomeada,
  atualize todo link para a âncora dela.
- Decisões que afetam mais de uma classe continuam num ADR (`docs/decisions/`); a nota aponta
  para o ADR em vez de repeti-lo.
