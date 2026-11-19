# 0015. Money as exact decimals, dates as calendar days

- Status: Accepted
- Date: 2026-11-19

## Context

Expenses carry an amount and a date, and the monthly summary adds amounts up and groups them by
month. Two classic mistakes hide here: binary floating point turning `0.10 + 0.20` into
`0.30000000000000004`, and a timestamp with a timezone moving an expense to another month for a
user who travels or whose phone is ahead of UTC. The decisions must hold in the database, the API,
the JSON and (later) the app.

## Decision

**Money**

1. The column is `numeric(12,2)`, the Java type is `BigDecimal`, the JSON form is a **decimal
   string with exactly 2 places** (`"12.50"`), in requests and responses (contract rule).
2. Input is strict: at most 2 decimals, greater than zero, ASCII digits only (`@MoneyAmount`).
   `12.345` is `400`, it is **never rounded** to `12.35` or `12.34`. The user must see and confirm
   exactly what will be stored.
3. Rounding exists only for **derived** values, which are not stored: the category percentage of
   the summary is `categoryTotal / monthTotal * 100`, scale 2, `RoundingMode.HALF_UP`, computed in
   `BigDecimal` (never `double`). A zero total is never a divisor (the percentage reads `0.00`).
   Rounded percentages may not add up to exactly 100; the contract says so.
4. Sums are done by PostgreSQL on `numeric` (`sum(amount)` grouped by category). Adding the exact
   per-category sums in Java is exact too, so no rounding enters a total.

**Dates**

5. An expense date is a calendar day: `date` column, `LocalDate`, JSON `YYYY-MM-DD`. No time, no
   zone, no conversion: the day the user picked is the day stored and returned.
6. A **month** is `YYYY-MM` of `expense_date` (`YearMonth`, validated 2000-01 to 9999-12). The
   query range is **half-open**: `expense_date >= first day and expense_date < first day of the
   next month`. There is no function on the column, so `idx_expenses_user_date` serves it, and
   there is no "last day of the month" to compute. The previous month is the same range one month
   earlier (December of the previous year for January).
7. "Today" for the upper bound of an expense date comes from the injected `Clock`, read in **UTC**,
   plus **one day** of tolerance (`@ValidExpenseDate`): a phone ahead of UTC may already be on
   tomorrow's date. The lower bound is `2000-01-01` (`ck_expenses_date_min`).
8. Audit timestamps (`createdAt`, `updatedAt`) are `Instant`s in UTC and are a different concept:
   they never decide which month an expense belongs to.

## Consequences

- Totals are exact to the cent and the same on every machine; tests can assert `0.10 + 0.20 =
  0.30`.
- A client that sends `12.345` gets a clear `400` and must round on its side. The app has to keep
  money as text or a decimal type, never `double`, when it talks to the API.
- Two users in different timezones who log "today" may disagree on the calendar day at the edges;
  accepted, because the user's own device is the reference for what "today" means to them.
- Changing the currency precision (zero or three decimals, such as JPY or KWD) needs a new
  decision and a migration; v1 assumes 2 decimals for every supported currency.

## Alternatives considered

- **Cents as `long`/`bigint`.** Exact and fast, but every boundary needs a conversion (JSON, app,
  display), the contract would show `1250` for 12.50, and the value hides the currency's decimal
  places. `numeric` does the same job with readable data.
- **`double`/`float` (or `real`).** Cannot represent most decimal cents; sums drift. Rejected.
- **`timestamptz` for the expense date.** Brings the timezone problem: the same expense lands in
  another month depending on who reads it and from where. The domain only needs a day.
- **Rounding the input** (`12.345` to `12.35`). Silent changes to a financial value; the user
  never confirmed that number. Rejected in favor of a `400`.
- **Month as `date_trunc('month', expense_date)` or `to_char(...)` in the query.** A function on
  the column defeats the index. The half-open range gives the same rows and uses it.
- **Inclusive end date (`<= last day`).** Works for `date`, but needs the month length and is a
  trap the moment the column becomes a timestamp. The half-open range does not change.
