# Team Backend — Status Pointer

The Laravel + Filament backend (part c) lives in a **separate private repo**
(not this one). Its `docs/BACKEND.md` has the full build log, run instructions,
data model, and implemented API. The wire contract this app builds against is
[`API.md`](API.md).

## What's ready (backend)
- Multi-tenant admin (tenant = Agency) + API v1: `POST /v1/activate`, `GET /v1/me`,
  `POST /v1/metrics`, `GET /v1/metrics`. Sanctum Bearer auth.
- `MemberProfile` and `DailyMetric` JSON match the Swift Codable structs field-for-field.

## macOS app status
Done: `HTTPLicenseService` calls `POST /v1/activate`, stores the **seat token**
in the Keychain, sends it as `Authorization: Bearer`, and re-activates on `401`.
The offline `MockLicenseService` / `MockTeamAPI` paths are unaffected.
