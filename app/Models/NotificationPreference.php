<?php

namespace App\Models;

use App\Enums\NotificationChannel;
use App\Enums\NotificationEventType;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A row with `user_id === null` is a tenant-wide default the owner set for
 * everyone; a row with `user_id` set is one user's personal override. See
 * NotificationPreferenceResolver for how the two combine with the
 * config('notifications.default_channels') fallback.
 */
class NotificationPreference extends Model
{
    protected $fillable = ['tenant_id', 'user_id', 'event_type', 'channel', 'enabled'];

    protected function casts(): array
    {
        return [
            'event_type' => NotificationEventType::class,
            'channel' => NotificationChannel::class,
            'enabled' => 'boolean',
        ];
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
