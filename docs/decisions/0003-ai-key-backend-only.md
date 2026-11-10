# 0003. AI provider key lives only in the backend

- Status: Accepted
- Date: 2026-11-10

## Context

In Phase 3 the user takes a photo of a receipt and an AI vision model extracts the amount,
date, merchant and a suggested category to pre-fill an expense.

Calling the AI provider requires a secret API key that is billed per use. The app ships
to iOS, Android and the Web:

- Anything compiled into a mobile app, including values passed with `--dart-define`, can be
  extracted from the binary with freely available tools. Obfuscation slows this down but
  does not prevent it.
- A Flutter Web build is JavaScript downloaded by the browser, so any embedded key is
  simply public.

A leaked key means anyone can spend our quota, use it for unrelated purposes, or get the
account suspended.

## Decision

The AI key **never reaches the client**.

1. The app sends the image to the API: `POST /api/v1/receipts/scan` (multipart, authenticated
   with the normal access token).
2. The API validates the upload, calls the AI provider with `AI_API_KEY` read from an
   environment variable, and returns a **draft** `ExpenseRequest` (amount, date,
   description, suggested `categoryId`), plus a confidence indicator.
3. The app shows the draft in the normal expense form. **Nothing is saved until the user
   confirms**, because the AI can be wrong.

Backend rules for this endpoint:

- Accept only `image/jpeg`, `image/png`, `image/heic`, `image/webp`, checked by magic
  bytes and not only by the declared MIME type. Max upload size 5 MB.
- Per-user rate limit (for example 20 scans per day) so a compromised account cannot burn the quota.
- The image is processed in memory and **not stored** in v1. Image content and extracted
  text are **not logged** (receipts may contain personal data).
- The provider sits behind an interface (`ReceiptExtractor`) with one adapter per provider.
  The rest of the code does not know which AI vendor is used, so it can be swapped or
  faked in tests (Dependency Inversion).
- The AI response is untrusted input: it is parsed into a typed DTO and validated with the
  same rules as a manual expense. The suggested category must be one the user can see.
- If the provider fails or times out, the API returns a ProblemDetail and the user can
  still type the expense manually.

## Consequences

- The key can be rotated without releasing a new app version.
- Usage can be limited, measured and audited per user on the server.
- Every scan costs an extra network hop (app → API → provider) and the API must handle
  larger request bodies.
- The backend becomes responsible for the privacy of receipt images in transit.
- The app needs no AI SDK, which keeps it smaller.

## Alternatives considered

- **Key in the app via `--dart-define` or an `.env` asset**: extractable from the binary,
  public on the Web. Rejected.
- **On-device OCR (for example ML Kit) with no AI provider**: free and private, but does not
  work on the Web and is much weaker at understanding receipt structure (which number is the
  total, which line is the merchant). Could complement the backend later as an offline fallback.
- **Short-lived provider tokens issued by our backend to the app**: only some providers
  support it. It still exposes provider details to the client and complicates rate
  limiting. Rejected for v1.
