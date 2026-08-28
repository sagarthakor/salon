<?php

namespace App\Services\Notifications\Channels;

use App\Enums\NotificationEventType;
use App\Models\Notification;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;

/**
 * In-app is not a queued external call — it *is* the notifications table
 * row, written synchronously the moment NotificationDispatcher runs, so a
 * user's in-app inbox is never stale behind a queue worker. See
 * NOTIFICATION_ARCHITECTURE.md.
 */
class InAppNotificationChannel
{
    public function store(?Tenant $tenant, User $recipient, NotificationEventType $event, string $title, string $body, array $data, ?Model $notifiable): Notification
    {
        return Notification::query()->create([
            'tenant_id' => $tenant?->id,
            'user_id' => $recipient->id,
            'notifiable_type' => $notifiable?->getMorphClass(),
            'notifiable_id' => $notifiable?->getKey(),
            'type' => $event,
            'title' => $title,
            'body' => $body,
            'data' => $data,
        ]);
    }
}
