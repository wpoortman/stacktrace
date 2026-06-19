# Team Backend — Status Pointer

The Laravel + Filament backend (part c) lives in a **separate private repo**
(not this one). Its `docs/BACKEND.md` has the full build log, run instructions,
data model, and implemented API. The wire contract this app builds against is
[`API.md`](API.md).

## What's ready (backend)
- Multi-tenant admin (tenant = Agency) + API v1: `POST /v1/activate`, `GET /v1/me`,
  `POST /v1/metrics`, `GET /v1/metrics`. Sanctum Bearer auth.
- `MemberProfile` and `DailyMetric` JSON match the Swift Codable structs field-for-field.

## ⚠️ Activation model changed (per-member key)
There is **no shared license key** anymore. Each employee gets their **own
activation key** (`STK-XXXX-XXXX-XXXX`) from their agency admin. A license is just
a seat pool; assigning a member consumes a seat and issues their key, and removing
the member frees it.

App impact:
- The activation field should collect a **personal activation key**, not a license key.
- `POST /v1/activate` body is now just `{ key, deviceId }` (no `name`/`email` — the
  member already exists server-side).
- Flow unchanged otherwise: store returned `token` in Keychain, send as
  `Authorization: Bearer`, re-activate on `401` (seat revoked / key invalidated).

## macOS app status
Done: `HTTPLicenseService` calls `POST /v1/activate`, stores the **seat token**
in the Keychain, sends it as `Authorization: Bearer`, and re-activates on `401`.
The offline `MockLicenseService` / `MockTeamAPI` paths are unaffected.
TODO: rename the activation input to "activation key" and drop name/email from the
activate call (see above).
