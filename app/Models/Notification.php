<?php

namespace App\Models;

use App\Enums\NotificationEventType;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\MorphTo;

/**
 * An in-app notification for a single user. Deliberately NOT tenant-scoped
 * via BelongsToTenant: a customer's notification inbox spans every tenant
 * they hold a customer profile with (see CustomerBookingController for the
 * same withoutGlobalScope('tenant') pattern), so every query and
 * authorization check here filters by `user_id` instead — see
 * NotificationController.
 */
class Notification extends Model
{
    use HasUlids;

    protected $fillable = ['tenant_id', 'user_id', 'notifiable_type', 'notifiable_id', 'type', 'title', 'body', 'data', 'read_at'];

    protected function casts(): array
    {
        return [
            'type' => NotificationEventType::class,
            'data' => 'array',
            'read_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    public function notifiable(): MorphTo
    {
        return $this->morphTo();
    }

    public function deliveries(): HasMany
    {
        return $this->hasMany(NotificationDelivery::class);
    }

    public function isRead(): bool
    {
        return $this->read_at !== null;
    }
}
