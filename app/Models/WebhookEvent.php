<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Platform-global idempotency ledger for inbound payment-gateway webhooks —
 * unique on (gateway, gateway_event_id). A webhook arrives with no
 * authenticated tenant session, so this is deliberately not tenant-scoped;
 * see `PaymentWebhookController`.
 */
class WebhookEvent extends Model
{
    protected $fillable = ['gateway', 'gateway_event_id', 'event_type', 'payload', 'processed_at'];

    protected function casts(): array
    {
        return ['payload' => 'array', 'processed_at' => 'datetime'];
    }
}
