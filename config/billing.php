<?php

return [

    /*
    |--------------------------------------------------------------------------
    | SaaS billing configuration
    |--------------------------------------------------------------------------
    |
    | Business rules that must never be hard-coded inline (see
    | SAAS_BILLING_ARCHITECTURE.md). Plan pricing itself lives in the
    | database (the `plans` table) — nothing price-related belongs here.
    |
    */

    // Which PaymentGatewayInterface binding is active. Currently only
    // 'razorpay' is implemented; the interface exists specifically so a
    // second gateway could be added without touching SubscriptionService/
    // BillingService.
    'default_gateway' => env('PAYMENT_GATEWAY', 'razorpay'),

    // How many days a subscription stays reachable (billing/renewal only —
    // business features are still blocked, see EnsureActiveSubscription)
    // after entering PAST_DUE/GRACE_PERIOD before it's marked EXPIRED.
    // Default: 3 days — configurable, not assumed elsewhere in the code.
    'grace_period_days' => (int) env('SUBSCRIPTION_GRACE_PERIOD_DAYS', 3),

    // Invoice number format: "{prefix}-{year}-{6-digit sequence}".
    'invoice_number_prefix' => env('BILLING_INVOICE_PREFIX', 'INV'),

];
