<?php

namespace App\Services\Billing\Gateways;

final readonly class GatewayRefund
{
    public function __construct(
        public string $id,
        public string $status,
    ) {}
}
