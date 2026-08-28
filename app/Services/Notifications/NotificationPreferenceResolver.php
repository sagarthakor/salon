<?php

namespace App\Services\Notifications;

use App\Enums\NotificationChannel;
use App\Enums\NotificationEventType;
use App\Models\NotificationPreference;
use App\Models\Tenant;
use App\Models\User;

/**
 * Whether a user *wants* a channel for a given event — precedence is
 * personal override > tenant-wide default > config('notifications.default_channels').
 * Deliberately independent of whether the channel is actually *available*
 * (device token exists, email configured, ...) — see
 * NotificationDispatcher, which combines this with availability before ever
 * creating a NotificationDelivery. Nothing here is hard-coded per event; all
 * defaults live in config/notifications.php (see Phase 11 spec, section 7).
 */
class NotificationPreferenceResolver
{
    public function wants(?Tenant $tenant, User $user, NotificationEventType $event, NotificationChannel $channel): bool
    {
        $userPreference = NotificationPreference::query()
            ->whereNull('tenant_id')
            ->where('user_id', $user->id)
            ->where('event_type', $event->value)
            ->where('channel', $channel->value)
            ->first();
        if ($userPreference !== null) {
            return $userPreference->enabled;
        }

        if ($tenant !== null) {
            $tenantPreference = NotificationPreference::query()
                ->where('tenant_id', $tenant->id)
                ->whereNull('user_id')
                ->where('event_type', $event->value)
                ->where('channel', $channel->value)
                ->first();
            if ($tenantPreference !== null) {
                return $tenantPreference->enabled;
            }
        }

        // Not config("notifications.default_channels.{$event->value}.{$channel->value}")
        // — NotificationEventType values (e.g. 'booking.confirmed') contain a
        // literal dot, which Laravel's config() dot-notation would otherwise
        // misparse as extra nesting levels instead of part of the key.
        $defaults = config('notifications.default_channels', []);

        return (bool) ($defaults[$event->value][$channel->value] ?? false);
    }
}
