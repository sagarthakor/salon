# Notification Architecture (Phase 11)

Phase 11 adds a multi-channel notification system — in-app, push, email, WhatsApp, SMS — on top of Phases 1–10's booking engine and SaaS billing. Nothing here rewrites existing architecture: it listens to events Phases 6/10 already fire (plus a handful of new ones for transitions that had no event yet) and adds its own domain sitting alongside them.

## The pipeline

```
Business Event (BookingCreated, PaymentFailed, SubscriptionExpired, ...)
      ↓
Notification Listener/Subscriber  — resolves WHO (customer/staff/owner), never trusts a client-supplied recipient
      ↓
NotificationDispatcher            — the one entry point; builds the message, writes the in-app row, queues external channels
      ↓
NotificationMessageBuilder        — renders title/body/deep-link data from backend-resolved context only
      ↓
NotificationPreferenceResolver    — personal override > tenant default > config('notifications.default_channels')
      ↓
 ┌────────┬────────┬──────────┬─────────┐
 │ In-app │  Push  │  Email   │WhatsApp/SMS│
 │(sync DB│(queued)│ (queued) │ (queued)  │
 │ write) │        │          │           │
 └────────┴────────┴──────────┴─────────┘
      ↓ (external channels only)
SendNotificationDeliveryJob → NotificationChannelInterface → Provider (Fcm / Meta WhatsApp / SMS) → NotificationDelivery row updated
```

Controllers/services never call a channel or provider directly. `BookingService`/`SubscriptionService`/`BillingService` only ever do `event(new SomeEvent($model))` — exactly as they already did before this phase; the notification system listens, it never gets called into.

## Business events

Reused unmodified from Phases 6/10: `BookingCreated`, `BookingConfirmed`, `BookingRescheduled`, `BookingCancelled`, `BookingCompleted`, `PaymentSucceeded`, `PaymentFailed`, `SubscriptionActivated`, `SubscriptionExpired`, `SubscriptionCancelled`.

New (Phase 6/10 had no event for these transitions yet): `BookingCheckedIn`, `BookingStarted`, `BookingNoShow` (fired from `BookingService::transition()`, same place `BookingConfirmed`/`BookingCompleted` already fired from), `SubscriptionPastDue`, `SubscriptionGracePeriod` (fired from `SubscriptionService::markPastDue()`/`processLifecycle()`, the same methods that already existed).

## Listeners are the "dispatcher" in the diagram above

`BookingNotificationSubscriber` and `BillingNotificationSubscriber` (`app/Listeners/Notifications/`) are Laravel event subscribers — one `subscribe()` method mapping several events to `handle*` methods, registered explicitly in `AppServiceProvider::boot()` via `Event::subscribe(...)`.

Both implement `ShouldQueue` with `public bool $afterCommit = true`, which is what guarantees a notification is never sent before the originating transaction commits (`BookingService`/`SubscriptionService` fire these events as the last statement inside `DB::transaction()`). Both also implement `Illuminate\Contracts\Events\ShouldBeDiscovered` returning `false` — **this is required, not decorative**: `Application::configure()` in `bootstrap/app.php` enables Laravel's automatic event discovery by default, which scans `app/Listeners` for any public `handle*(SomeEvent $event)` method and registers it *again* on top of the explicit `Event::subscribe()` call. Without opting out, every notification fired twice. This was caught by the Phase 11 test suite and is exactly the kind of bug the "do not assume, verify" instruction in this phase's brief was for.

`BookingRecipientResolver` resolves customer/staff/owner recipients purely server-side from the `Booking` model (`booking->customer->user`, `booking->items->staff->user`, `tenant->users()->wherePivot('role', 'salon_owner')`) — a Flutter client can never submit a `recipient_user_id`.

### Tenant context inside a queued/afterCommit listener

Booking's related models (`Customer`, `Staff`, `Service`, `Branch`, ...) all use the `BelongsToTenant` global scope, which returns nothing at all when no `TenantContext` is set. Two things had to be handled carefully here:

1. **Setting it.** `BookingNotificationSubscriber::withBooking()` sets `TenantContext` to `$booking->tenant` (itself unscoped — `Tenant` has no `BelongsToTenant`) before touching any related model.
2. **Restoring, not clearing, the previous value.** Because `afterCommit` listeners run under the `sync` queue driver *inside the same call stack* as the original controller — before `BookingService::create()` even returns to its caller — an unconditional `$context->clear()` in the listener's `finally` block would wipe out the *outer* controller's own tenant context mid-request. The fix mirrors the existing `SubscriptionService::startTrialFor()` pattern: save `$context->get()` first, restore it (not `null`) in `finally`. `BookingReminderService` does the same thing per-booking in its scan loop, since it iterates bookings across many tenants in one run.

## Notification model & delivery tracking

- **`notifications`** (`App\Models\Notification`) — one row per (event, recipient). `user_id`, `tenant_id`, a polymorphic `notifiable_type`/`notifiable_id` (manually declared, not `->morphs()`, since `Booking`/`Subscription` use ULID keys), `type` (a `NotificationEventType`), `title`, `body`, `data` (json, typed deep-link payload), `read_at`.

  **Deliberately not tenant-scoped** (no `BelongsToTenant`): a customer's inbox spans every tenant they hold a customer profile with — the same reason `CustomerBookingController` already uses `withoutGlobalScope('tenant')` for a customer's booking list. Every query and mutation in `NotificationController` filters by `user_id === $request->user()->id` instead, which is what makes cross-tenant/cross-user access structurally impossible rather than something each action has to remember to check.

- **`notification_deliveries`** (`App\Models\NotificationDelivery`) — one row per (notification, external channel). `channel`, `recipient` (the resolved destination: email address, phone number, or the recipient user id for push, since actual device tokens are looked up fresh at send time), `provider`, `provider_message_id`, `status` (`pending`/`processing`/`sent`/`failed`/`skipped`), `attempt_count`, `failure_reason`, `metadata`.

- **`user_device_tokens`** — `token` is globally unique; re-registering an existing token (e.g. the same device, a different login) reassigns it to the new user rather than erroring, since a push token can only ever be meaningfully delivered to whoever is currently signed in on that device.

- **`notification_preferences`** — a row with `user_id = null` is a tenant-wide default the owner set; a row with `user_id` set is one user's personal override, independent of tenant. See "Preferences" below.

- **`booking_reminders`** — idempotency ledger, see "Reminders".

## Preferences: who decides what gets sent

`NotificationPreferenceResolver::wants($tenant, $user, $event, $channel)` precedence: **personal override → tenant-wide default → `config('notifications.default_channels')`**. Nothing is hard-coded inside a notification/listener class — every default lives in `config/notifications.php`, keyed by `NotificationEventType` value (e.g. `booking.cancelled`) and `NotificationChannel` value (e.g. `whatsapp`).

**Important gotcha, and a real bug this caught**: `NotificationEventType` values (`'booking.confirmed'`, `'payment.succeeded'`, ...) contain a literal dot. Building a `config()` dot-path string like `"notifications.default_channels.{$event->value}.{$channel->value}"` gets *misparsed* by Laravel's dot-notation as extra nesting levels rather than a literal dotted key — silently returning `false` for every single event/channel combination. Every place that needs this value fetches the `default_channels` array once and does plain PHP array access (`$defaults[$event->value][$channel->value] ?? false`) instead of a dotted `config()` call. The same pitfall applies to `config('notifications.whatsapp.templates.' . $eventValue)` in `WhatsAppNotificationChannel` — fixed the same way.

Availability gates are separate from *wanting* a channel (`NotificationDispatcher::dispatch()`): PUSH requires an active `UserDeviceToken`; EMAIL requires the recipient have an email address; WhatsApp/SMS require both the provider be configured (`isConfigured()`) *and* a resolved phone number. A delivery row is only ever created when both the preference and the availability check pass — an unconfigured channel never silently "succeeds," and a configured-but-undesired channel is never sent.

Two APIs manage preferences (`NotificationPreferenceController`): `GET/PUT /api/v1/notifications/preferences` (personal, any authenticated user) and `GET/PUT /api/v1/salon/notification-settings` (tenant-wide, owner only — checked via `tenant->users()->wherePivot('role', 'salon_owner')`, not just tenant membership).

## Channels & providers

`NotificationChannelInterface` (`send(NotificationDelivery, Notification): void`) is the contract every *external* channel implements — `PushNotificationChannel`, `EmailNotificationChannel`, `WhatsAppNotificationChannel`, `SmsNotificationChannel`. In-app is not one of these; it's the synchronous `notifications` table write `InAppNotificationChannel` performs directly inside `NotificationDispatcher`, never queued, so a user's inbox is never stale behind a queue worker.

Each channel depends on a provider *interface*, never a concrete SDK:

| Channel | Interface | Bound to | Notes |
|---|---|---|---|
| Push | `PushProviderInterface` | `FcmHttpV1Provider` | Firebase Cloud Messaging HTTP v1 API. Authenticates with a hand-signed (openssl RS256) service-account JWT — no new Composer dependency needed for this phase. |
| Email | *(uses Laravel Mail directly)* | — | `App\Mail\NotificationMail`, Laravel's existing `config/mail.php` — not a second mail system. |
| WhatsApp | `WhatsAppProviderInterface` | `MetaWhatsAppProvider` | Official Meta WhatsApp Cloud API only — never unofficial automation or WhatsApp Web scraping. Sends only pre-approved templates (`config('notifications.whatsapp.templates')`), never arbitrary free text. |
| SMS | `SmsProviderInterface` | `LogSmsProvider` | No production SMS vendor has been selected — this placeholder logs and reports itself unconfigured, so deliveries are always marked SKIPPED, never falsely SENT. |

Tests bind `FakePushProvider`/`FakeWhatsAppProvider`/`FakeSmsProvider` (same pattern as Phase 10's `FakePaymentGateway`) — no real HTTP call is ever made from the test suite.

## Queue architecture & isolation from business transactions

```
Booking created → DB transaction commits → afterCommit listener resolves recipients →
NotificationDispatcher writes the in-app row synchronously →
one NotificationDelivery + SendNotificationDeliveryJob per wanted-and-available external channel
```

The booking API response is never slowed by a WhatsApp/push/email/SMS call — those only ever happen inside `SendNotificationDeliveryJob`, on the queue. A delivery failure updates that one `NotificationDelivery` row (`FAILED`, with `failure_reason`) and is retried by Laravel's normal queue retry mechanism (`config('notifications.retry')` — 5 tries, backoff `[30s, 2m, 10m, 30m]`); it never rolls back or affects the booking/payment/subscription it originated from. Proven by `test_booking_creation_succeeds_even_when_every_external_channel_delivery_fails`.

**Retry policy**: providers return a `ProviderSendResult` with a `retryable` flag. A transient error (network blip, rate limit) → `FAILED`, retried. A permanent error (invalid phone number, an unregistered/expired push token, a rejected WhatsApp template) → `SKIPPED`, never retried again — retrying an input that can never succeed just wastes queue capacity. A push token found dead (`UNREGISTERED`/`INVALID_ARGUMENT` from FCM) is deactivated on the spot.

## Reminders

`BookingReminderService::processDueReminders()` (run every `config('notifications.reminders.run_frequency_minutes')` minutes via `notifications:process-reminders`, see `routes/console.php`) scans upcoming `PENDING`/`CONFIRMED` bookings and, for each configured offset (`24h`, `2h` — `config('notifications.reminders.offsets')`), checks whether now falls within `window_minutes` of that offset before the appointment's real branch-timezone instant.

**Idempotency**: a `booking_reminders` row is `insertOrIgnore`'d — unique on `(booking_id, reminder_type)` — *before* the reminder is actually sent. `insertOrIgnore` returns `0` inserted rows on a unique-constraint conflict, which is how a second scheduler run (or a retried/overlapping run) is guaranteed to send at most one reminder per booking per reminder type, verified by `test_reminders_fire_once_are_not_duplicated_...`. A cancelled or completed booking is never a candidate in the first place (the query only selects `PENDING`/`CONFIRMED`).

## What Phase 11 does NOT claim

- **No real push/WhatsApp/SMS delivery has been performed or verified.** `FCM_PROJECT_ID`/`FCM_CLIENT_EMAIL`/`FCM_PRIVATE_KEY` and `WHATSAPP_ACCESS_TOKEN`/`WHATSAPP_PHONE_NUMBER_ID` are empty in `.env`/`.env.example`; both providers report `isConfigured() === false` until real credentials are supplied, and every channel treats "unconfigured" as SKIPPED, never SENT. Automated tests exercise every code path with fake providers instead (see each provider's `Fake*` counterpart).
- **No SMS vendor has been chosen.** `SmsProviderInterface`/`LogSmsProvider` is the full abstraction; swapping in a real vendor (Twilio, MSG91, ...) is a single `AppServiceProvider` binding change plus a new provider class — nothing else in the codebase needs to change.
- **Flutter does not yet obtain a real FCM token.** `firebase_messaging`/`firebase_core` were not added to `mobile/pubspec.yaml`, and no `google-services.json`/`GoogleService-Info.plist` exist — adding the Gradle plugin without real Firebase project files risks breaking the verified Android debug build for credentials that would still be inert. The backend device-token API (register/deactivate) is fully implemented and tested; wiring a real FCM SDK into Flutter is the remaining step, documented in the Phase 11 final report.
- **No WhatsApp/FCM delivery-status webhook** (e.g. Meta's message-status callback) was added — only outbound sending. Inbound provider callbacks would need the same signature-verification treatment `PaymentWebhookController` already gives Razorpay's webhook; out of scope until a real WhatsApp Business Account exists to test against.
