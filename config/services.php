<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Resend, Postmark, AWS, and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    // Phase 10 SaaS billing — see SAAS_BILLING_ARCHITECTURE.md for why
    // Razorpay was selected. `mode` is `test` or `live`; only `test`
    // (sandbox) credentials should ever be used outside production.
    'razorpay' => [
        'key' => env('PAYMENT_KEY'),
        'secret' => env('PAYMENT_SECRET'),
        'webhook_secret' => env('PAYMENT_WEBHOOK_SECRET'),
        'mode' => env('PAYMENT_GATEWAY_MODE', 'test'),
    ],

    // Instagram API with Instagram Login (Professional accounts). Standard
    // Access is enough for accounts the app owner manages; see
    // SALON_MEDIA_ARCHITECTURE.md for the Meta dashboard setup.
    'instagram' => [
        'app_id' => env('INSTAGRAM_APP_ID'),
        'app_secret' => env('INSTAGRAM_APP_SECRET'),
        'redirect_uri' => env('INSTAGRAM_REDIRECT_URI'),
        'graph_url' => 'https://graph.instagram.com',
        'oauth_url' => 'https://api.instagram.com',
        'authorize_url' => 'https://www.instagram.com/oauth/authorize',
        'scopes' => ['instagram_business_basic'],
    ],

];
