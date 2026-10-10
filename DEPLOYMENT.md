# Deployment

Set production environment variables from a secret manager; never commit `.env`. Configure MySQL, Redis-compatible cache/queue drivers when enabled, a web worker, queue workers, the scheduler, TLS, backups, and centralized logs. Run `php artisan migrate --force` during deployment. Replace the local demo seeder credentials before any non-local deployment.

## Hair Inspiration gallery & Instagram connection

Design and Meta setup: `SALON_MEDIA_ARCHITECTURE.md`. Nothing here is automatic — apply each step deliberately.

1. **Migration.** `php artisan migrate --force` creates `salon_media` and `instagram_connections` (new tables only; no existing table is altered). Verify on a throwaway MySQL database first: the migration uses a `utf8mb4_bin` column on MySQL so Reel shortcodes (which are case-sensitive) are compared exactly.
2. **Storage.** Uploaded videos and thumbnails use `SALON_MEDIA_DISK` (default `public`) under `salon-media/{tenant_id}/…`. Ensure `php artisan storage:link` has been run, `APP_URL` is the real `https://` URL (media URLs are built from it), `storage/app/public` is writable by the PHP user, and there is disk space and backup coverage for videos. For heavy traffic point `SALON_MEDIA_DISK` at an S3-compatible bucket behind a CDN.
3. **Upload size.** The app accepts videos up to `SALON_MEDIA_MAX_VIDEO_KB` (default 51200 = 50 MB). Raise PHP `upload_max_filesize` and `post_max_size` and nginx `client_max_body_size` above that (e.g. 64M) or uploads fail before Laravel with a `413`.
4. **Scheduler.** The existing `* * * * * php artisan schedule:run` entry also runs the new daily `instagram:refresh-tokens` (refreshes Instagram tokens expiring within 20 days; flags rejected ones for reconnect). It is safe to run manually.
5. **Cache.** The OAuth `state` is stored in the cache for 10 minutes, so `CACHE_STORE` must be shared by all PHP workers (`database`, `redis`, or `file` on a single server — not `array`).
6. **Environment variables** (see `.env.example`; set from the secret manager, never committed): `INSTAGRAM_APP_ID`, `INSTAGRAM_APP_SECRET` (the *Instagram app* credentials from Meta's "API setup with Instagram login"), `INSTAGRAM_REDIRECT_URI` (exactly `https://<host>/api/v1/instagram/callback`, identical to the URI registered at Meta), optional `SALON_MEDIA_DISK`, `SALON_MEDIA_MAX_VIDEO_KB`, `INSTAGRAM_SYNC_MAX_PAGES` (default 10 pages × 50 items per sync). Without the three Instagram variables the connect button reports "not set up" and uploads / Reel links keep working. Run `php artisan config:cache` after changing them.
7. **Meta app.** Business-type app with the Instagram product; add the salon's Professional account as an Instagram Tester for development use. Other salons' owners need Advanced Access / App Review. Details in `SALON_MEDIA_ARCHITECTURE.md`.
8. **Logs.** The OAuth callback carries a single-use `code` in its query string; it is useless without the app secret, but exclude `/api/v1/instagram/callback` query strings from long-term access-log retention if your policy requires.

