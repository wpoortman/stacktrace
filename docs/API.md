# Stacktrace Team API (contract)

The macOS app (employee) talks to a backend (the agency's Laravel service) when
a **Pro / Team** license is active **and** the member has opted in to team sync.
The web admin (agency owner) is a separate UI on the same backend — not covered
here.

- Base URL: configured per install (e.g. `https://api.stacktrace.app`).
- Versioned under `/v1`.
- All requests/responses are JSON (`Content-Type: application/json`).
- Auth: `Authorization: Bearer <seatToken>` — issued by the backend when a seat
  is activated with a license key (see licensing). The token identifies the
  member + agency.

## Privacy

The app only sends **coarse daily summaries** the member has consented to —
never raw note text. Wellbeing is a single aggregate number, not individual
entries. Sync is opt-in and off by default.

## Endpoints

### POST /v1/activate

Exchange a license key for a **seat token**. Consumes a seat (enforced against
the plan's cap) and returns the token used as `Authorization: Bearer` on every
other call. Re-activating the same device rotates/returns its token.

Request (no auth):

```json
{ "key": "TEAM-XXXX-XXXX-XXXX", "deviceID": "uuid-per-install" }
```

Response:

```json
{ "token": "sanctum-seat-token" }
```

Errors: `409` when all seats are used; `4xx` for an unknown/expired key. The app
stores the token in the Keychain and re-activates automatically on a later
`401`.

### GET /v1/me

Returns the signed-in member's profile and current rate.

```json
{
  "memberId": "mbr_123",
  "name": "Alex Doe",
  "role": "Developer",
  "currency": "EUR",
  "baseRateCents": 8000,
  "effectiveRateCents": 7600,
  "qualityFactor": 0.95
}
```

- `baseRateCents` — the member's rate (override) or the role's global rate.
- `effectiveRateCents` — what the agency bills the client after the quality
  adjustment (`baseRateCents * qualityFactor`), computed server-side.
- `qualityFactor` — 0…1, derived from recent wellbeing / day-scores.

### POST /v1/metrics

Push one day's summary. Idempotent per `(member, date)` — re-posting replaces.

Request:

```json
{
  "date": "2026-06-18",
  "entries": 5,
  "wins": 3,
  "losses": 1,
  "wellbeing": 4.2,
  "dayScore": 8
}
```

- `wellbeing` — average per-entry mood that day (1–5), or null.
- `dayScore` — the overall 1–10 day rating, or null.

Response:

```json
{ "stored": true, "effectiveRateCents": 7600 }
```

### GET /v1/metrics?from=YYYY-MM-DD&to=YYYY-MM-DD (optional)

Returns the member's own pushed metrics for a range, for display in-app.

```json
{ "metrics": [ { "date": "2026-06-18", "effectiveRateCents": 7600, "dayScore": 8 } ] }
```

## Errors

Standard HTTP codes. Body: `{ "error": "message" }`. `401` → token invalid /
seat revoked (app should prompt re-activation).

## Rate model (server-side)

```
baseRateCents      = member.rateOverride ?? role.baseRate
qualityFactor      = f(recent wellbeing, day-scores)   // 0..1, tunable
effectiveRateCents = round(baseRateCents * qualityFactor)
```

Kept on the server so the formula can change without an app release.
