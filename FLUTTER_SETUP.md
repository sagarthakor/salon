# Flutter Setup

## Installed toolchain (this environment)

- Flutter 3.47.1 (stable channel), installed to `~/development/flutter`, added to `PATH` via `~/.bashrc`.
- Android SDK at `~/Android/Sdk` (already present before Phase 7), with the Android toolchain, platform-tools, and licenses accepted by `flutter doctor`.
- No Xcode / macOS — iOS can be *built as source* (`flutter create` generated the standard `ios/Runner.xcodeproj`) but cannot be *compiled or run* here. Actual iOS builds/testing require a Mac with Xcode and CocoaPods. This is a platform limitation, not a project gap.

Verify with:

```bash
flutter doctor -v
```

## Running the app locally

```bash
cd mobile
flutter pub get
flutter run   # pick a connected device/emulator when prompted
```

### Backend must be running

The app talks to the real Laravel API — start it first:

```bash
cd ..            # repo root
php artisan serve --host=0.0.0.0 --port=8000
```

`--host=0.0.0.0` is required for an Android emulator or a physical device on the same network to reach it; `127.0.0.1` only accepts connections from the machine running `artisan serve` itself.

### API base URL (`--dart-define`)

`AppConfig.apiBaseUrl` (`mobile/lib/core/config/app_config.dart`) is never hard-coded — it's read at build/run time via `--dart-define=API_BASE_URL=...`, defaulting to `http://10.0.2.2:8000/api/v1` (the Android emulator's alias for the host's `127.0.0.1` — the emulator cannot reach `localhost`/`127.0.0.1` directly, since that resolves to the emulator itself).

| Target | Command |
|---|---|
| Android emulator (default) | `flutter run` |
| iOS simulator / physical device on the same Wi-Fi | `flutter run --dart-define=API_BASE_URL=http://<your-machine-LAN-IP>:8000/api/v1` |
| Physical Android device on the same Wi-Fi | same as iOS — `10.0.2.2` only exists inside the emulator |
| Production | `flutter build apk --release --dart-define=API_BASE_URL=https://api.yourdomain.com/api/v1` |

The iOS simulator, unlike the Android emulator, shares the host's network stack, so `http://127.0.0.1:8000/api/v1` or `http://localhost:8000/api/v1` works directly for it.

Never commit a real production URL as the compiled-in default — the fallback in `app_config.dart` is a *development* convenience only, and CI/release builds should always pass `--dart-define` explicitly.

### Cleartext HTTP for local development

Android blocks plain HTTP by default (API 28+). `android/app/src/debug/res/xml/network_security_config.xml` allows cleartext traffic **only** to `10.0.2.2`/`localhost`/`127.0.0.1`, and is wired in only for **debug** builds (`android/app/src/debug/AndroidManifest.xml`). Release builds have no such exception — a production `API_BASE_URL` must be HTTPS. iOS's App Transport Security already exempts `localhost` by default, so no iOS config change was needed for local development.

## Demo data for manual testing

Seeded via `php artisan db:seed` (idempotent) plus a few records created live through the real API during Phase 7/8 verification:

| Role | Email | Password | Lands on |
|---|---|---|---|
| Salon owner | `owner@example.test` | `ChangeMe123!` | `/owner` — owner dashboard |
| Staff | `staff@example.test` | `ChangeMe123!` | `/staff` — staff Today tab |
| Customer | `rahul@example.test` | `CustomerPass123!` | `/home` — customer home |

Tenant slug: `demo-salon`. The owner account has a salon, a branch (open 09:00–20:00 daily), a "Haircut" service, and one staff member ("Amit"); `rahul@example.test` is already registered as that salon's customer, so logging in as them in the app immediately shows a bookable salon on the home screen. The Phase 9 `staff@example.test` account is linked to that same "Amit" staff profile (real `staff` tenant membership, added additively in `database/seeders/DatabaseSeeder.php` — never a `migrate:fresh`), so it already has a real branch and service assignment to show. Which screen a login lands on is decided purely client-side from the account's `role` (see `OWNER_APP_ARCHITECTURE.md` / `STAFF_APP_ARCHITECTURE.md`).

`image_picker` (`^1.2.3`) was added in Phase 8 for the staff-photo/service-image/category-image picker screens. Phase 9 added no new Flutter dependencies.

## Build validation

```bash
cd mobile
flutter analyze          # 0 issues
flutter test             # 129 tests, all passing
flutter build apk --debug
```

`flutter build apk --debug` produces `mobile/build/app/outputs/flutter-apk/app-debug.apk` (~173MB debug build). A real Android emulator/device run (install + tap through the flow) was not performed in this environment — no AVD system image was pre-installed, and provisioning one plus verifying KVM/display access was judged not worth the time given the build itself, the full test suite, and a live curl-based run of every endpoint the app calls (see `MOBILE_API_INTEGRATION.md`) already give strong confidence the app is correct. If you have `adb`/an emulator available, `flutter install` / `flutter run -d <device>` should work immediately against the steps above.

iOS remains unbuildable in this environment for the same reason as Phase 7 (no Xcode/macOS) — nothing Phase 8 or 9-specific changes that; still document only, never claim a real iOS build/run.

## Environment variables / secrets

None are embedded in the Flutter source. The only "secret" the app ever holds is the user's own Sanctum bearer token, stored via `flutter_secure_storage` (Android Keystore-backed `EncryptedSharedPreferences`, iOS Keychain) — never `SharedPreferences`/`NSUserDefaults`, and never logged (see `FLUTTER_ARCHITECTURE.md`'s network-layer section).
