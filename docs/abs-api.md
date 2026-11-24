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
- Not yet recorded: `POST /api/items/{id}/play`, session sync/close, cover bytes (a `HEAD` failed because of a client issue, not the server).
- Dev account is `root` type (admin). Use a read-only user for anything shipped.
