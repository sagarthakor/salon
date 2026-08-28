<?php

namespace App\Services\Billing\Gateways;

/**
 * A created gateway order/checkout session — everything the Flutter app
 * needs to open the gateway's payment UI, and nothing more (never a secret).
 */
final readonly class GatewayOrder
{
    public function __construct(
        public string $id,
        public float $amount,
        public string $currency,
        public string $receipt,
    ) {}
}
