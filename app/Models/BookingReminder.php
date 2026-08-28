<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Idempotency record for one (booking, reminder_type) pair — its unique
 * index is what guarantees a reminder is never sent twice even if the
 * scheduler runs concurrently or is retried. See
 * ProcessBookingReminders/NOTIFICATION_ARCHITECTURE.md, "Reminder idempotency".
 *
 * Deliberately plain (no BelongsToTenant): the reminder scan runs
 * platform-wide from a console context with no TenantContext set — the same
 * withoutGlobalScope('tenant') pattern SubscriptionService::processLifecycle
 * uses — so `tenant_id` is set explicitly from the booking instead.
 */
class BookingReminder extends Model
{
    protected $fillable = ['tenant_id', 'booking_id', 'reminder_type', 'scheduled_at', 'sent_at'];

    protected function casts(): array
    {
        return [
            'scheduled_at' => 'datetime',
            'sent_at' => 'datetime',
        ];
    }

    public function booking(): BelongsTo
    {
        return $this->belongsTo(Booking::class);
    }
}
