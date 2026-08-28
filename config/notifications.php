<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Default channel policy
    |--------------------------------------------------------------------------
    |
    | Per-event default channel enablement, used when neither a personal
    | (user) nor a tenant-level NotificationPreference row exists for a given
    | event/channel pair. Keyed by App\Enums\NotificationEventType value.
    | Deliberately conservative: WhatsApp/SMS default off for low-value
    | transitions so a booking never triggers a channel storm (see
    | NOTIFICATION_ARCHITECTURE.md, "Channel fallback").
    |
    */
    'default_channels' => [
        'booking.created' => ['in_app' => true, 'push' => true, 'email' => false, 'whatsapp' => true, 'sms' => false],
        'booking.confirmed' => ['in_app' => true, 'push' => true, 'email' => false, 'whatsapp' => true, 'sms' => false],
        'booking.rescheduled' => ['in_app' => true, 'push' => true, 'email' => false, 'whatsapp' => true, 'sms' => false],
        'booking.cancelled' => ['in_app' => true, 'push' => true, 'email' => true, 'whatsapp' => true, 'sms' => false],
        'booking.checked_in' => ['in_app' => true, 'push' => false, 'email' => false, 'whatsapp' => false, 'sms' => false],
        'booking.started' => ['in_app' => true, 'push' => false, 'email' => false, 'whatsapp' => false, 'sms' => false],
        'booking.completed' => ['in_app' => true, 'push' => true, 'email' => false, 'whatsapp' => false, 'sms' => false],
        'booking.no_show' => ['in_app' => true, 'push' => true, 'email' => false, 'whatsapp' => false, 'sms' => false],
        'booking.reminder' => ['in_app' => true, 'push' => true, 'email' => false, 'whatsapp' => true, 'sms' => false],
        'payment.succeeded' => ['in_app' => true, 'push' => true, 'email' => true, 'whatsapp' => false, 'sms' => false],
        'payment.failed' => ['in_app' => true, 'push' => true, 'email' => true, 'whatsapp' => false, 'sms' => false],
        'subscription.activated' => ['in_app' => true, 'push' => true, 'email' => true, 'whatsapp' => false, 'sms' => false],
        'subscription.past_due' => ['in_app' => true, 'push' => true, 'email' => true, 'whatsapp' => false, 'sms' => false],
        'subscription.grace_period' => ['in_app' => true, 'push' => true, 'email' => true, 'whatsapp' => false, 'sms' => false],
        'subscription.expired' => ['in_app' => true, 'push' => true, 'email' => true, 'whatsapp' => false, 'sms' => false],
        'subscription.cancelled' => ['in_app' => true, 'push' => false, 'email' => true, 'whatsapp' => false, 'sms' => false],

        // Phase 12 — coupons/membership/loyalty.
        'membership.activated' => ['in_app' => true, 'push' => true, 'email' => true, 'whatsapp' => false, 'sms' => false],
        'membership.expired' => ['in_app' => true, 'push' => true, 'email' => true, 'whatsapp' => false, 'sms' => false],
        // Low-noise: a completed booking already notifies the customer (see
        // booking.completed above); this is in-app only so as not to double
        // up on push/WhatsApp for the same event.
        'loyalty.points_earned' => ['in_app' => true, 'push' => false, 'email' => false, 'whatsapp' => false, 'sms' => false],
    ],

    /*
    |--------------------------------------------------------------------------
    | Booking reminders
    |--------------------------------------------------------------------------
    |
    | `offsets` maps a reminder-type key to how many minutes before the
    | appointment it should fire. `window_minutes` is how wide a tolerance
    | the scheduled job accepts around that offset (must be >= the job's run
    | frequency below, or some appointments would fall between two runs and
    | never get a reminder).
    |
    */
    'reminders' => [
        'offsets' => [
            '24h' => 1440,
            '2h' => 120,
        ],
        'window_minutes' => 15,
        // How often `notifications:process-reminders` runs — see
        // routes/console.php. Must stay <= window_minutes above.
        'run_frequency_minutes' => 10,
    ],

    /*
    |--------------------------------------------------------------------------
    | Retry policy
    |--------------------------------------------------------------------------
    |
    | Applies to SendNotificationDeliveryJob. `tries`/`backoff` are standard
    | Laravel queue retry knobs; `permanent_failure_patterns` are
    | provider-error substrings that should never be retried (bad phone
    | number, rejected template, etc.) — see RETRY_STRATEGY in
    | NOTIFICATION_ARCHITECTURE.md.
    |
    */
    'retry' => [
        'tries' => 5,
        'backoff_seconds' => [30, 120, 600, 1800],
    ],

    /*
    |--------------------------------------------------------------------------
    | Push (Firebase Cloud Messaging — HTTP v1 API)
    |--------------------------------------------------------------------------
    */
    'fcm' => [
        'project_id' => env('FCM_PROJECT_ID'),
        'client_email' => env('FCM_CLIENT_EMAIL'),
        'private_key' => env('FCM_PRIVATE_KEY'),
    ],

    /*
    |--------------------------------------------------------------------------
    | WhatsApp (official Meta WhatsApp Cloud API)
    |--------------------------------------------------------------------------
    |
    | `templates` maps our internal event keys to the WhatsApp template name
    | approved in the Meta Business Manager for that message — never hard-code
    | a provider template id/name inside business logic (see
    | MetaWhatsAppProvider).
    |
    */
    'whatsapp' => [
        'provider' => env('WHATSAPP_PROVIDER', 'meta'),
        'access_token' => env('WHATSAPP_ACCESS_TOKEN'),
        'phone_number_id' => env('WHATSAPP_PHONE_NUMBER_ID'),
        'business_account_id' => env('WHATSAPP_BUSINESS_ACCOUNT_ID'),
        'api_base_url' => env('WHATSAPP_API_BASE_URL', 'https://graph.facebook.com/v20.0'),
        'templates' => [
            'booking.created' => 'booking_confirmation',
            'booking.confirmed' => 'booking_confirmation',
            'booking.rescheduled' => 'booking_rescheduled',
            'booking.cancelled' => 'booking_cancelled',
            'booking.reminder' => 'booking_reminder',
            'payment.succeeded' => 'payment_success',
            'subscription.expired' => 'subscription_expiring',
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | SMS
    |--------------------------------------------------------------------------
    |
    | No production SMS provider has been selected yet (see Phase 11 report).
    | `SmsProviderInterface` is bound to `LogSmsProvider` until one is chosen;
    | swap the binding in AppServiceProvider once real credentials exist.
    |
    */
    'sms' => [
        'provider' => env('SMS_PROVIDER'),
        'api_key' => env('SMS_API_KEY'),
        'from' => env('SMS_FROM'),
    ],
];
