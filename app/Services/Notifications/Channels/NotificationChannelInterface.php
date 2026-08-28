<?php

namespace App\Services\Notifications\Channels;

use App\Models\Notification;
use App\Models\NotificationDelivery;

/**
 * The contract every *external* delivery channel implements — push, email,
 * WhatsApp, SMS. In-app is deliberately not one of these: it is the
 * synchronous database write the dispatcher performs itself (see
 * InAppNotificationChannel), never a queued external call. Business logic
 * (controllers/services) never depends on a concrete channel or provider —
 * only SendNotificationDeliveryJob resolves one of these by
 * `NotificationChannel` value. See NOTIFICATION_ARCHITECTURE.md.
 */
interface NotificationChannelInterface
{
    /**
     * Sends [$delivery] and updates its status (SENT/FAILED/SKIPPED) itself
     * — the job that calls this never inspects the provider result
     * directly, so every channel is free to have its own "what counts as
     * skippable/permanent" rules.
     */
    public function send(NotificationDelivery $delivery, Notification $notification): void;
}
