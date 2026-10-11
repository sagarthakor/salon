# Hair Inspiration Gallery & Instagram Connection

A customer-facing "Our Work" gallery of haircut/colour/styling videos, plus an owner tool to curate it from the salon's own uploads and (optionally) its Instagram Professional account. Builds on the existing tenant, authorization, subscription, and booking architecture without changing any of it. See also `SERVICE_ARCHITECTURE.md` (the older per-service `instagram_url`, untouched) and `MULTI_TENANCY.md`.

## What it does — and deliberately does not do

| Capability | How |
|---|---|
| Native in-app playback | Only for **salon-owned video files uploaded by the owner**, stored on the configured disk and streamed with Flutter's `video_player`. |
| Instagram items | Metadata only (id, permalink, caption, type, thumbnail URL). The app shows the thumbnail and a **"View on Instagram"** link-out. **Never a play button.** |
| Instagram media files | **Never downloaded, scraped, or re-hosted.** `media_url` is not even requested from the API. A reel permalink / oEmbed is never treated as a video URL. |
| Any public Instagram account | **Not supported.** Only the owner's own Professional (Business/Creator) account, authorized by the owner. |

If an owner wants an Instagram reel to play inside the app, they upload the original video file for that item (they own the content); the item then has both a hosted video and its Instagram link.

## Data model (migration `2026_10_10_000000_create_salon_media_tables.php`)

- **`salon_media`** — tenant-owned (`BelongsToTenant`). `branch_id` nullable (null = salon-wide), `service_id` nullable (`nullOnDelete`; powers "Book This Style"), `source` (`instagram`|`upload` = origin), `media_type`, `category`, `instagram_media_id` (unique per tenant), `instagram_url` (canonical `https://www.instagram.com/{type}/{code}/` when added manually), `instagram_shortcode` (case-sensitive, unique per tenant; derived from the URL by the model so every spelling of one Reel maps to the same row), `instagram_thumbnail_url`, `video_path`, `thumbnail_path`, `caption`, `is_active`, `sort_order`. Deleting a row deletes its stored files.
- **`instagram_connections`** — one per tenant (`tenant_id` unique). `access_token` uses the `encrypted` cast and is `$hidden`; it is never returned by any API, logged, or sent to Flutter.

Synced Instagram items are created **hidden** (`is_active = false`): nothing the owner posted appears to customers until they switch it on. A re-sync refreshes only Instagram-owned fields (permalink, thumbnail URL, type, timestamp; caption only while still empty) and never touches visibility, category, service link, order, or an uploaded video.

## API (all under `/api/v1`, existing `{success,message,data}` envelope; lists are plain arrays paginated with `page`/`per_page`, like every other list)

Owner (`auth:sanctum`, `tenant.context`, `subscription.active`, `managedTenant()` — owner/super-admin only):

| Method | Path | Purpose |
|---|---|---|
| GET | `/salon-media` | List all items (filters: `source`, `category`, `media_type`, `branch_id`, `is_active`) |
| POST | `/salon-media` | Create: multipart `video` (+ optional `thumbnail`) and/or `instagram_url` |
| GET/PUT/PATCH/DELETE | `/salon-media/{media}` | Show / update (`caption`, `category`, `service_id`, `branch_id`, `is_active`, `sort_order`, `video`, `thumbnail`, `remove_video`, `remove_thumbnail`) / delete. Multipart updates use `POST` + `_method=PUT` like service images. |
| POST | `/salon-media/reorder` | `{ids: [...]}` — sets display order |
| GET | `/instagram/connection` | Status only (`configured`, `connected`, `needs_reconnect`, `username`, `last_synced_at`, …) |
| POST | `/instagram/connect` | Returns the official `authorization_url` |
| DELETE | `/instagram/connection` | Disconnect (deletes our stored token; gallery items stay) |
| POST | `/instagram/sync` | Pull metadata (throttled) → `{created, updated, skipped}` |

Customer (`auth:sanctum`, like the services catalog; tenant resolved from the branch, `X-App-Brand` guard enforced):

| GET | `/branches/{branch}/gallery?category=&page=&per_page=` | Active items that are salon-wide or for this branch. Returns `playback` = `native`\|`instagram`\|`none`; `video_url` is non-null only for hosted videos; `service` only if that service is still active. |

Public: `GET /instagram/callback` (OAuth redirect target; no bearer token — authenticity is the single-use, tenant+user-bound `state` in cache, 10-minute TTL; renders a static page, never echoes provider output).

## Instagram connection (official API only)

**API product:** Instagram API with Instagram Login (Business Login for Instagram). Scope: `instagram_business_basic` only. Accounts: Instagram **Professional** (Business or Creator) accounts; personal accounts are not supported.

Flow: owner taps *Connect* → app calls `POST /instagram/connect` → opens `https://www.instagram.com/oauth/authorize` in the browser → Instagram redirects to `/api/v1/instagram/callback?code&state` → server exchanges the code (`api.instagram.com/oauth/access_token`), swaps it for a 60-day long-lived token (`graph.instagram.com/access_token`, server-side because it uses the app secret), reads the profile, stores the encrypted token. The app re-checks the connection when the owner returns to it.

Token lifecycle: `php artisan instagram:refresh-tokens` (scheduled daily) refreshes tokens expiring within 20 days via `refresh_access_token` (Meta requires a token ≥ 24 h old and not yet expired). A token Meta rejects, or one past expiry, flips the connection to `expired`; the owner sees "Reconnect". Sync also flags `expired` on an auth error (code 190 / OAuth). Rate limits (HTTP 429 or error codes 4/17/32/613) surface as 429 "try again later" without disconnecting. Sync is capped at `INSTAGRAM_SYNC_MAX_PAGES` × 50 items per run and the endpoint is throttled.

Disconnect: Meta provides no token-revoke call for this login type, so we delete our copy; owners can also remove the app under Instagram → Settings → Apps and websites.

### What you must configure at Meta (nothing is pre-configured; no credentials exist in the repo)

1. developers.facebook.com → create an app of type **Business**; add the **Instagram** product → *API setup with Instagram login*.
2. Copy the **Instagram app ID / secret** (distinct from the parent Meta app ID/secret) into `INSTAGRAM_APP_ID` / `INSTAGRAM_APP_SECRET`.
3. Under *Business login settings* add the valid OAuth redirect URI `https://salon.primecodesystems.in/api/v1/instagram/callback` and set `INSTAGRAM_REDIRECT_URI` to the identical string (Meta may display it with a trailing slash — it must match exactly in both places).
4. **Development mode / Standard Access** works for Instagram accounts you own or manage: add the salon's Instagram account as an *Instagram Tester* (App roles → Roles) and accept the invite in Instagram (Settings → Apps and websites → Tester invites). That is enough to connect `nil_hairport_unisex`.
5. **Advanced Access + App Review** (and typically Business Verification, a privacy-policy URL and a data-deletion callback/instructions, app in Live mode) is required before *other* salons' owners — accounts you don't own or manage — can connect. Plan for this before offering the feature to other tenants. Verify current requirements in Meta's docs at that time; they change.

Environment variables: `INSTAGRAM_APP_ID`, `INSTAGRAM_APP_SECRET`, `INSTAGRAM_REDIRECT_URI`, optional `SALON_MEDIA_DISK` (default `public`), `SALON_MEDIA_MAX_VIDEO_KB` (default 51200), `INSTAGRAM_SYNC_MAX_PAGES` (default 10). Without the three Instagram variables the feature degrades cleanly: the app says the connection isn't set up, and Reel links + video uploads still work.

## Uploads, storage and security

- Video: `mp4`/`mov`, validated by extension **and** sniffed content type (`video/mp4`, `video/quicktime`), default max 50 MB. Thumbnail: jpg/png/webp image, max 5 MB. Client filenames are never used; files go to `salon-media/{tenant_id}/{videos|thumbnails}/<generated name>`.
- Every query is tenant-scoped (`BelongsToTenant`): another tenant's item is a 404; `tenant_id` in a request body is ignored; `branch_id` / `service_id` are validated against the caller's tenant (and a service must belong to the chosen branch).
- `instagram_url` must be an `https://instagram.com` `/p|reel|tv/` link (existing `InstagramUrl` rules) and unique within the tenant.
- Hosted files are public marketing content served from the `public` disk behind unguessable generated paths, same as service images. For private/signed delivery switch `SALON_MEDIA_DISK` to an S3-compatible disk; `Storage::url()` is the only place URLs are produced.

## Customer & owner apps (Flutter)

- Customer: `features/gallery/` — "Our Work" entry on the salon card (main app) and home (branded app) → `/salons/:id/gallery` (category chips, 2-column thumbnail grid, incremental loading, loading/empty/error+retry) → `/gallery/viewer` full-screen. Only thumbnails exist in the grid; **one** `VideoPlayerController` exists, in the viewer, disposed with it (also if disposed mid-initialize), paused when the app is backgrounded, with buffering indicator, tap pause/resume, error + retry, and a fullscreen (landscape/immersive) toggle that is restored on exit. *Book This Style* re-validates the linked service against the live branch catalog, then preloads the existing booking flow and opens the cart.
- Owner: More → *Hair inspiration gallery* (`features/owner/gallery/`): Instagram connect/sync/disconnect/reconnect card, reorderable list showing "Hosted video" vs "Instagram only" and hidden state, visibility switch, add (upload video or Instagram link), edit (caption, category, linked service, replace/remove video, thumbnail), delete. Owner screens are absent from the branded single-salon app, as with every owner route.
- Dependency added: `video_player` (official Flutter package; ExoPlayer on Android, AVPlayer on iOS). Android already has `INTERNET`; iOS needs nothing extra for HTTPS.

## Production deployment (do not run until approved)

```bash
cd /var/www/salon.primecodesystems.in
git pull origin main
composer install --no-dev --optimize-autoloader
php artisan migrate --force          # creates salon_media, instagram_connections
php artisan config:clear && php artisan config:cache
php artisan route:cache
php artisan storage:link             # only if public/storage does not already exist
```

1. Add the three `INSTAGRAM_*` variables to the server `.env` only after step 2–3 of the Meta setup; `config:cache` afterwards.
2. **Upload limits:** raise `upload_max_filesize` / `post_max_size` (php.ini, FPM pool) and nginx `client_max_body_size` above 50 MB (e.g. 64M) or video uploads fail before reaching Laravel with a 413.
3. The scheduler already needs `* * * * * php artisan schedule:run`; `instagram:refresh-tokens` rides on it.
4. Ensure `storage/app/public` is writable by the PHP user and has disk space for videos.

Video bandwidth: the `public` disk serves MP4 straight from nginx (range requests supported, so seeking works). Phone videos are large — advise owners to upload ≤ 1080p H.264 MP4 of 15–60 s. If traffic grows, put an S3-compatible bucket behind a CDN (`SALON_MEDIA_DISK`), and consider generating HLS renditions; neither is needed for a single salon.

## Known limitations

- Instagram thumbnail URLs come from Instagram's CDN and expire; the app falls back to a placeholder until the owner re-syncs or uploads their own thumbnail.
- No server-side thumbnail generation / transcoding (no `ffmpeg` dependency was introduced). Uploads without a thumbnail show the placeholder tile.
- Items are salon-wide from the owner UI; the API supports per-branch items (`branch_id`).
- Items deleted on Instagram are not removed from the gallery automatically.
- Concurrent-sync recovery is covered by a test that simulates the losing side of the race (a competing row appearing between lookup and insert); a true multi-process race is not reproduced in the test suite.
- Sync matches a Reel the owner already added by link via its shortcode and adopts that row (sets its Instagram id and refreshes thumbnail/timestamp) rather than duplicating it; the owner's caption, visibility, category, service and order are kept.

## Sync guarantees

- **Owner deletions stick.** Deleting an item that came from Instagram records its Instagram id in `instagram_ignored_media` (tenant-scoped, primary key `(tenant_id, instagram_media_id)`); later syncs skip that id. Pasting the Reel's link again is an explicit re-add: the sync adopts that row and clears the marker. Manually added items (no Instagram id) leave no marker.
- **Captions.** `salon_media.caption_customized` becomes true when the owner sets a caption or changes it to a different value (including clearing it). A sync only fills a caption that is empty **and** not customized. Re-saving an unchanged caption does not count.
- **Races.** If another sync inserts the same item between lookup and insert, the resulting unique-key violation (and only that exception type) is caught, the existing row is reused and updated with Instagram-owned fields only; if no matching row can be found the original exception is rethrown.

## Instagram error handling

`InstagramClient::decode()` classifies failures: rate limit (HTTP 429 or codes 4/17/32/613/80002) → `429`; **token problem** (code 190 or 102, HTTP 401, or OAuth subcodes 458/459/460/463/467; during the code exchange any client error) → `409` and the connection is flagged `expired`; missing permission (code 10 or 200–299) → `409` without expiring; invalid field/parameter (code 100) and everything else → `502` without expiring. Only the token class ever changes the connection's status. Every failed `/instagram/connect` and `/instagram/sync` response also carries a stable top-level `kind` (`reconnect_required`, `permission_denied`, `not_connected`, `rate_limited`, `invalid_request`, `unavailable`, `not_configured`) so clients need not parse messages; see `API_DOCUMENTATION.md`.

## Unverified against real Meta (no credentials were available)

The `/me/media` edge, the field list `id,caption,media_type,permalink,thumbnail_url,timestamp`, `limit`/`after` cursor paging, `caption` availability under Instagram Login (Meta's reference labels it Facebook-Login-only), and the exact error shapes for the classes above are taken from Meta's docs and general Graph behaviour, not from live calls. Confirm them on the first real sync with the tester account.

## Book This Style → booking (persisted)

- `bookings.salon_media_id` (nullable FK → `salon_media`, `nullOnDelete`) and `bookings.style_label` (caption/category snapshot) — migration `2026_10_11_000000_add_salon_media_to_bookings_table.php`.
- `POST /customer/bookings` accepts optional `salon_media_id`. It must be an **active** item of the booking's tenant that is salon-wide or belongs to the booking's branch, otherwise `422` on `salon_media_id` and nothing is booked. The linked service is still validated and priced by the normal booking engine; the style never affects price or availability.
- `BookingResource.style` = `{id, label, category_label, thumbnail_url}` (null when no style). Deleting the gallery item keeps the booking, nulls `id`, keeps `label`. Owner and customer booking `show` endpoints load it.
- Photos: owners may upload `image` (jpg/png/webp, `SALON_MEDIA_MAX_IMAGE_KB`, default 10 MB) instead of a video; stored in `thumbnail_path`, `media_type = photo`, `playback = image`, `image_url` set.
