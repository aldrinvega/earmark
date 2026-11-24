# Audiobookshelf API notes (verified against server 2.37.2, 2026-11-25)

Only shapes are recorded here: no host, token or library titles (the repo is public). Auth is `Authorization: Bearer <accessToken>`.

| Call | Verified result |
|---|---|
| `GET /status` | `{app, serverVersion, isInit, language, authMethods:["local"], authFormData}`, no auth needed |
| `POST /login` `{username,password}` + header `x-return-tokens: true` | `{user, userDefaultLibraryId, serverSettings, ereaderDevices, Source}`; `user` has `accessToken`, `refreshToken` (and legacy `token`), `mediaProgress`, `bookmarks`, `permissions`, `librariesAccessible`, `type` |
| `POST /auth/refresh` + header `x-refresh-token: <refreshToken>` | same shape as login, with a fresh `accessToken` and `refreshToken` |
| `GET /api/libraries` | `{libraries:[{id, mediaType:"book", name, …}]}` |
| `GET /api/libraries/{id}/items?limit=N` | `{results, total, limit, page, sortDesc, mediaType, minified, collapseseries, include, offset}`; each result has `id`, `media.metadata.title`, `media.duration`, `media.numChapters` |
| `GET /api/items/{id}?expanded=1&include=progress` | item keys include `id, libraryId, path, mediaType, media, numFiles, size, libraryFiles, userMediaProgress`; `media` keys: `metadata, coverPath, numTracks, numAudioFiles, numChapters, duration, size, audioFiles, chapters, ebookFile, tracks` |
| chapter | `{id, start, end, title}`, seconds from the start of the Book |
| `GET /api/me/progress/{itemId}` | `{id, libraryItemId, duration, progress, currentTime, isFinished, ebookLocation, ebookProgress, lastUpdate, startedAt, finishedAt, …}` (404 when never started) |

- A Book with one audio file has `tracks` of length 1; multi-file Books have several tracks, each with its own offset.
- `ebookFile` is empty for audio-only Books (the Textbook comes from Pocket Book Studio, not Audiobookshelf).
- Tokens are short-lived: a stale `accessToken` returns `401 Unauthorized`; log in again or `POST /auth/refresh`.
- Dev account is `root` type (admin). Use a read-only user for anything shipped.

## Playback (recorded 2026-11-25)
| Call | Verified result |
|---|---|
| `POST /api/items/{id}/play` body `{deviceInfo:{clientName,deviceId}, forceDirectPlay, forceTranscode, supportedMimeTypes:[…]}` | A play session: `id, libraryItemId, duration, playMethod (0 = direct play), startTime, currentTime, chapters, audioTracks, mediaMetadata, displayTitle, displayAuthor, coverPath, startedAt, updatedAt, …`. `currentTime` is the saved position |
| `audioTracks[i]` | the audio file's fields plus `startOffset` (seconds into the Book) and `contentUrl` (`/api/items/{id}/file/{ino}`) |
| `GET {contentUrl}` with `Authorization` and `Range: bytes=0-99` | `206 Partial Content`, `Accept-Ranges: bytes`, `Content-Range: bytes 0-99/<size>`, `Content-Type: audio/mp4` (a ~200 MB m4b), so AVPlayer can seek |
| `POST /api/session/{sid}/sync` `{currentTime, timeListened, duration}` | `200`, body `"OK"` |
| `POST /api/session/{sid}/close` `{currentTime, timeListened}` | `200` |
| `GET /api/items/{id}/cover` | `200 image/jpeg` (28 KB here) |

- Syncing `currentTime: 0, timeListened: 0` and closing left the saved progress at `currentTime 0`, so a probe session doesn't disturb a Book.
