<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Requires the standard Laravel scheduler cron entry to actually run in
// production: `* * * * * php artisan schedule:run >> /dev/null 2>&1`. See
// SAAS_BILLING_ARCHITECTURE.md, "Scheduler".
Schedule::command('subscriptions:process-lifecycle')->daily();

// Booking reminders — frequency must stay <=
// config('notifications.reminders.window_minutes') or a booking could fall
// between two runs and never get a reminder. See NOTIFICATION_ARCHITECTURE.md,
// "Scheduler". Also requires a running queue worker
// (`php artisan queue:work`) to actually deliver the queued push/email/
// WhatsApp/SMS jobs this command enqueues — see NOTIFICATION_ARCHITECTURE.md,
// "Queue worker".
Schedule::command('notifications:process-reminders')->everyTenMinutes();

// Coupons/membership/loyalty (Phase 12) — see
// LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md, "Scheduler". Both are
// idempotent sweeps; running either twice in the same day is a safe no-op.
Schedule::command('memberships:expire')->daily();
Schedule::command('loyalty:expire-points')->daily();
