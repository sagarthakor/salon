<?php

namespace App\Services\Notifications\Channels;

use App\Mail\NotificationMail;
use App\Models\Notification;
use App\Models\NotificationDelivery;
use Illuminate\Support\Facades\Mail;
use Throwable;

/**
 * Uses Laravel's own mail configuration (config/mail.php) — no second mail
 * system. `$delivery->recipient` is the resolved email address, set by
 * NotificationDispatcher at creation time.
 */
class EmailNotificationChannel implements NotificationChannelInterface
{
    public function send(NotificationDelivery $delivery, Notification $notification): void
    {
        if (blank($delivery->recipient)) {
            $delivery->markSkipped('Recipient has no email address on file.');

            return;
        }

        try {
            Mail::to($delivery->recipient)->send(new NotificationMail($notification->title, $notification->body));
            $delivery->markSent();
        } catch (Throwable $e) {
            $delivery->markFailed($e->getMessage());
        }
    }
}
