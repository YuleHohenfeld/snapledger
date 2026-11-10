# SnapLedger API Contract — v1

This document is the source of truth between the Flutter app and the Spring Boot API.
The app builds its models and repositories from it; the API implements exactly what it
promises. Once the API exists, the live OpenAPI spec is served at `/docs` and must match
this file. If they diverge, fix one of them in the same pull request.

## Conventions

| Topic | Rule |
|---|---|
| Base URL | `{API_BASE_URL}/api/v1` — every path below is relative to it |
| Format | JSON, UTF-8, `camelCase` field names |
| IDs | UUID v4 strings |
| Money | **Decimal string** with exactly 2 decimal places (`"12.50"`), never a JSON number — floats lose cents. Stored as `NUMERIC(12,2)`, handled as `BigDecimal` |
| Dates | `date`: ISO-8601 calendar date (`"2026-11-10"`). Timestamps: ISO-8601 UTC (`"2026-11-10T14:03:22Z"`) |
| Month filter | `month=YYYY-MM` (`"2026-11"`), based on the expense `date`, so there is no timezone ambiguity |
| Currency | One currency per user (ISO 4217, default `BRL`). No conversion in v1 |
| Auth | `Authorization: Bearer <accessToken>` on every endpoint not marked **Public** |
| Ownership | The user is **always** taken from the access token. No endpoint accepts a `userId`. A resource owned by another user returns **404**, never 403, so its existence is not revealed |
| Errors | `application/problem+json` (RFC 9457), see [Errors](#errors) |

## Endpoint overview

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/auth/register` | Public | Create account and start a session |
| POST | `/auth/login` | Public | Start a session |
| POST | `/auth/refresh` | Public | Rotate the refresh token, get a new access token |
| POST | `/auth/logout` | Public | Revoke the session |
| GET | `/users/me` | Bearer | Current user profile |
| PATCH | `/users/me` | Bearer | Update name / currency |
| GET | `/categories` | Bearer | Default + own categories |
| POST | `/categories` | Bearer | Create own category |
| PATCH | `/categories/{id}` | Bearer | Rename own category |
| DELETE | `/categories/{id}` | Bearer | Delete own category (only if unused) |
| GET | `/expenses?month=` | Bearer | List expenses of a month |
| POST | `/expenses` | Bearer | Create expense |
| GET | `/expenses/{id}` | Bearer | Get one expense |
| PUT | `/expenses/{id}` | Bearer | Replace an expense |
| DELETE | `/expenses/{id}` | Bearer | Delete an expense |
| GET | `/expenses/summary?month=` | Bearer | Monthly totals per category (chart data) |

---

## Auth

### Session model

- **Access token**: signed JWT (HS256), valid for **15 minutes**. Claims: `sub` (user id), `iat`, `exp`, `iss`. No personal data inside it.
- **Refresh token**: opaque random string (256 bits, base64url), valid for **30 days**. The server stores only its SHA-256 hash.
- **Rotation**: each `/auth/refresh` call consumes the refresh token and returns a new pair.
- **Reuse detection**: presenting an already-used refresh token revokes the **whole session family**. It means the token leaked, so both the attacker and the legitimate user are logged out.
- Rationale: [ADR 0002](decisions/0002-refresh-token-rotation.md).

### `TokenResponse` (shared by register, login and refresh)

```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiJ9...",
  "tokenType": "Bearer",
  "expiresIn": 900,
  "refreshToken": "kq3V9tq0b2...base64url",
  "refreshExpiresIn": 2592000
}
```

`expiresIn` / `refreshExpiresIn` are in seconds.

### POST `/auth/register` — Public

Creates the account and logs the user in, so the app does not need a second request.

Request:

```json
{
  "name": "Ana Souza",
  "email": "ana@example.com",
  "password": "correct-horse-battery",
  "currency": "BRL"
}
```

| Field | Rules |
|---|---|
| `name` | required, trimmed, 1–80 chars |
| `email` | required, valid email, max 254 chars, stored lowercase |
| `password` | required, 8–72 chars (72 is the bcrypt input limit) |
| `currency` | optional, ISO 4217 code, default `BRL` |

Response `201 Created`: `{ "user": UserResponse, "tokens": TokenResponse }`

Errors: `400 validation-error`, `409 email-already-registered`.

> Trade-off: `409` on register tells someone that an email has an account. It is accepted
> for v1 because the alternative (email confirmation flow) is out of scope. Login does
> **not** leak this (see below).

### POST `/auth/login` — Public

Request:

```json
{ "email": "ana@example.com", "password": "correct-horse-battery" }
```

Response `200 OK`: `{ "user": UserResponse, "tokens": TokenResponse }`

Errors: `400 validation-error`, `401 invalid-credentials`. Unknown email and wrong password
return the **same** error, with the same message and a similar response time, so nobody can
use login to find out which emails have accounts.

### POST `/auth/refresh` — Public

Request:

```json
{ "refreshToken": "kq3V9tq0b2...base64url" }
```

Response `200 OK`: `TokenResponse` (new access token **and** new refresh token; the old
refresh token is now invalid).

Errors: `400 validation-error`, `401 invalid-refresh-token` (unknown, expired, revoked
or reused, deliberately indistinguishable to the client).

App behavior: on `401 invalid-refresh-token` the app wipes the stored tokens and goes to
the login screen. Only **one** refresh may be in flight at a time; concurrent requests
wait for it.

### POST `/auth/logout` — Public

Public on purpose: the user must be able to log out even when the access token has
already expired. The refresh token itself proves the session.

Request:

```json
{ "refreshToken": "kq3V9tq0b2...base64url" }
```

Response `204 No Content`, **always**, even if the token is unknown or already revoked
(idempotent; reveals nothing). The session family is revoked server-side. Access tokens
already issued remain valid until they expire (max 15 min), a deliberate stateless
trade-off.

---

## Users

### `UserResponse`

```json
{
  "id": "6f1c2a4e-8b0d-4c39-9a51-2f7e0d3b9c11",
  "name": "Ana Souza",
  "email": "ana@example.com",
  "currency": "BRL",
  "createdAt": "2026-11-10T14:03:22Z"
}
```

### GET `/users/me`

Response `200 OK`: `UserResponse`. Errors: `401 unauthorized`.

### PATCH `/users/me`

Partial update; omitted fields stay unchanged. Email and password changes are out of scope for v1.

```json
{ "name": "Ana S.", "currency": "USD" }
```

Response `200 OK`: `UserResponse`. Errors: `400 validation-error`, `401 unauthorized`.

> Changing `currency` only changes the label. Amounts are **not** converted.

---

## Categories

Two kinds:

- **Default** (`"isDefault": true`): seeded by a Flyway migration, shared by all users, read-only.
  Seed: Food, Groceries, Transport, Housing, Health, Leisure, Education, Other.
- **Own** (`"isDefault": false`): created by the user, visible only to that user.

### `CategoryResponse`

```json
{
  "id": "0b8a3f52-1d2e-4c7a-9f60-5a4b3c2d1e0f",
  "name": "Pets",
  "isDefault": false
}
```

### GET `/categories`

Response `200 OK`: `CategoryResponse[]`, defaults first, then own categories, each group
ordered by name.

### POST `/categories`

```json
{ "name": "Pets" }
```

| Field | Rules |
|---|---|
| `name` | required, trimmed, 1–40 chars, unique (case-insensitive) among the defaults and the user's own categories |

Response `201 Created` + `Location: /api/v1/categories/{id}`: `CategoryResponse`.

Errors: `400 validation-error`, `409 category-name-taken`.

### PATCH `/categories/{id}`

```json
{ "name": "Pet care" }
```

Response `200 OK`: `CategoryResponse`.

Errors: `400 validation-error`, `403 default-category-read-only`, `404 not-found`
(does not exist **or** belongs to another user), `409 category-name-taken`.

### DELETE `/categories/{id}`

Response `204 No Content`.

Errors: `403 default-category-read-only`, `404 not-found`, `409 category-in-use`
(the category still has expenses; the user must move or delete them first).

---

## Expenses

### `ExpenseResponse`

```json
{
  "id": "c3d4e5f6-a7b8-4c9d-8e0f-1a2b3c4d5e6f",
  "amount": "42.90",
  "description": "Weekly groceries",
  "date": "2026-11-08",
  "category": { "id": "0b8a3f52-1d2e-4c7a-9f60-5a4b3c2d1e0f", "name": "Groceries", "isDefault": true },
  "createdAt": "2026-11-08T21:15:00Z",
  "updatedAt": "2026-11-08T21:15:00Z"
}
```

### `ExpenseRequest` (POST and PUT)

```json
{
  "amount": "42.90",
  "description": "Weekly groceries",
  "date": "2026-11-08",
  "categoryId": "0b8a3f52-1d2e-4c7a-9f60-5a4b3c2d1e0f"
}
```

| Field | Rules |
|---|---|
| `amount` | required, decimal string, `> 0`, max 2 decimal places, max `9999999999.99` |
| `description` | required, trimmed, 1–120 chars |
| `date` | required, ISO date, not more than 1 day in the future (tolerates timezone differences) |
| `categoryId` | required, must be a default category or one of the user's own |

### GET `/expenses?month=YYYY-MM`

| Query | Rules |
|---|---|
| `month` | **required**, `YYYY-MM` |
| `categoryId` | optional filter |

Response `200 OK`: `ExpenseResponse[]` ordered by `date` desc, then `createdAt` desc.
v1 has no pagination: a month is a naturally bounded window. Revisit if a month can exceed ~1,000 items.

Errors: `400 validation-error` (missing or malformed `month`), `404 not-found` (unknown `categoryId`).

### POST `/expenses`

Body: `ExpenseRequest`. Response `201 Created` + `Location: /api/v1/expenses/{id}`: `ExpenseResponse`.

Errors: `400 validation-error`, `404 not-found` (`categoryId` does not exist or belongs to another user).

### GET `/expenses/{id}`

Response `200 OK`: `ExpenseResponse`. Errors: `404 not-found`.

### PUT `/expenses/{id}`

Full replacement. Body: `ExpenseRequest` (all fields required). Response `200 OK`: `ExpenseResponse`.

Errors: `400 validation-error`, `404 not-found` (expense or category).

### DELETE `/expenses/{id}`

Response `204 No Content`. Errors: `404 not-found`.

### GET `/expenses/summary?month=YYYY-MM`

Data for the monthly summary screen and its chart.

```json
{
  "month": "2026-11",
  "currency": "BRL",
  "total": "1234.56",
  "expenseCount": 37,
  "previousMonthTotal": "980.00",
  "byCategory": [
    { "categoryId": "0b8a3f52-...", "categoryName": "Groceries", "total": "612.30", "expenseCount": 9, "percentage": "49.60" },
    { "categoryId": "9e8d7c6b-...", "categoryName": "Transport", "total": "310.00", "expenseCount": 20, "percentage": "25.11" }
  ]
}
```

- `byCategory` contains only categories with expenses in the month, ordered by `total` desc.
- `percentage` is a decimal string with 2 places (`total / month total * 100`, rounded HALF_UP). Rounded values may not add up to exactly 100.
- An empty month returns `200` with `"total": "0.00"`, `"expenseCount": 0`, `"byCategory": []`.

Errors: `400 validation-error`.

---

## Errors

Every error is an RFC 9457 Problem Detail with `Content-Type: application/problem+json`,
produced by a single global exception handler (controllers never build error bodies).

```json
{
  "type": "urn:snapledger:problem:validation-error",
  "title": "Validation failed",
  "status": 400,
  "detail": "One or more fields are invalid.",
  "instance": "/api/v1/expenses",
  "errors": [
    { "field": "amount", "message": "must be greater than 0" }
  ]
}
```

- The app branches on `status` and `type`, **never** on `title`/`detail` text (that text may change).
- `errors` exists only on `validation-error`.
- `500` responses never contain exception class names, stack traces or SQL. The detail is logged server-side only.

| Status | `type` suffix | When |
|---|---|---|
| 400 | `validation-error` | Bean Validation failure, malformed JSON, bad query param |
| 401 | `unauthorized` | Missing, malformed or expired access token (also sends `WWW-Authenticate: Bearer`) |
| 401 | `invalid-credentials` | Login failed |
| 401 | `invalid-refresh-token` | Refresh token unknown, expired, revoked or reused |
| 403 | `default-category-read-only` | Attempt to change or delete a default category |
| 404 | `not-found` | Resource does not exist **or** belongs to another user |
| 409 | `email-already-registered` | Register with an existing email |
| 409 | `category-name-taken` | Duplicate category name |
| 409 | `category-in-use` | Delete a category that still has expenses |
| 500 | `internal-error` | Unexpected failure |

The app's interceptor tries a refresh **only** on `401 unauthorized` from non-`/auth/*`
endpoints. Every other `401` is final.

## Out of scope for v1 (see roadmap)

- `POST /receipts/scan` (Phase 3: AI reads a receipt photo and returns a pre-filled `ExpenseRequest`; the AI key lives only in the backend, see ADR 0003).
- Rate limiting on `/auth/*` (Phase 4, would add `429 too-many-requests`).
- Email verification, password reset, password change, account deletion.
- Pagination, multi-currency conversion, recurring expenses.
