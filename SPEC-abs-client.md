# Spec: abs-client — Swift client for the Audiobookshelf API

> Status: **DRAFT** (2026-11-24), not yet approved. Implements the `abs-client` row of SPEC.md's capability map.
> Server: Audiobookshelf 2.37.2 on the owner's Mac over the tailnet. Endpoint shapes below are from memory of the
> public API and **must be verified against the real server** (recordings in `docs/abs-api.md`) before coding.

## Objective
Give the app typed, tested access to Audiobookshelf: sign in, list **Books**, read a Book's chapters and cover, play,
and sync listening progress both ways. No UI. Lives in a new `ABSClient` target (Foundation only, depends on `Models`).

## Surface (first slice → Checkpoint D)
| Need | Endpoint (verify) |
|---|---|
| Server reachable | `GET /status` |
| Sign in, refresh | `POST /login`, `POST /auth/refresh` |
| Libraries, Books | `GET /api/libraries`, `GET /api/libraries/{id}/items` |
| One Book + chapters + tracks | `GET /api/items/{id}?expanded=1` |
| Cover | `GET /api/items/{id}/cover` |
| Start playback | `POST /api/items/{id}/play` |
| Sync a session | `POST /api/session/{id}/sync`, `POST /api/session/{id}/close` |
| Progress | `GET /api/me/progress/{id}`, `PATCH /api/me/progress/{id}` |

## Design
- `ABSClient` is an `actor` over an injected `URLSession`-like `HTTPTransport` protocol, so tests use recorded JSON.
- Typed `ABSError` enum (unreachable, unauthorized, notFound, decoding, server(status)); user text lives in `AppFeatures`.
- Token storage is a protocol (`TokenStore`); the app implements it with the Keychain. Never logged, never in fixtures.
- Progress rule (SPEC Boundaries): read the server's progress before writing; never move it backwards unless the user
  chose to; newest server `lastUpdate` wins.

## Testing
Decode recorded responses (scrubbed of tokens, hostnames, titles not in the public domain); token-refresh and 401-retry
with a fake transport; progress conflict rules. Coverage ≥80%. Live check is the manual `ios/smoke-servers.sh`.

## Boundaries
- Ask first: any new dependency; recording responses that contain the owner's library.
- Never: commit tokens or the real server address; send anything outside the tailnet.

## Open questions
1. Dev user and server URL (owner to provide, kept out of the repo).
2. ~~Exact response shapes on 2.37.2~~ recorded in `docs/abs-api.md` (2026-11-25); spec table above still to be reconciled.
