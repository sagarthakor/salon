<?php

namespace App\Models;

use App\Enums\NotificationChannel;
use App\Enums\NotificationDeliveryStatus;
use App\Enums\NotificationEventType;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One delivery attempt record per (notification, external channel) — the
 * audit trail SendNotificationDeliveryJob updates as it processes the queue.
 * See NOTIFICATION_ARCHITECTURE.md, "Delivery tracking".
 */
class NotificationDelivery extends Model
{
    protected $fillable = [
        'tenant_id', 'notification_id', 'event_type', 'channel', 'recipient',
        'provider', 'provider_message_id', 'status', 'attempt_count',
        'last_attempt_at', 'sent_at', 'failed_at', 'failure_reason', 'metadata',
    ];

    protected function casts(): array
    {
        return [
            'event_type' => NotificationEventType::class,
            'channel' => NotificationChannel::class,
            'status' => NotificationDeliveryStatus::class,
            'attempt_count' => 'integer',
            'last_attempt_at' => 'datetime',
            'sent_at' => 'datetime',
            'failed_at' => 'datetime',
            'metadata' => 'array',
        ];
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    public function notification(): BelongsTo
    {
        return $this->belongsTo(Notification::class);
    }

    public function markSent(?string $providerMessageId = null): void
    {
        $this->update([
            'status' => NotificationDeliveryStatus::SENT,
            'provider_message_id' => $providerMessageId,
            'sent_at' => now(),
            'last_attempt_at' => now(),
        ]);
    }

    public function markFailed(string $reason): void
    {
        $this->update([
            'status' => NotificationDeliveryStatus::FAILED,
            'failure_reason' => $reason,
            'failed_at' => now(),
            'last_attempt_at' => now(),
        ]);
    }

    public function markSkipped(string $reason): void
    {
        $this->update([
            'status' => NotificationDeliveryStatus::SKIPPED,
            'failure_reason' => $reason,
        ]);
    }
}
