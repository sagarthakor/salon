<?php

namespace App\Services\Notifications\Channels;

use App\Models\Notification;
use App\Models\NotificationDelivery;
use App\Services\Notifications\Providers\SmsProviderInterface;

class SmsNotificationChannel implements NotificationChannelInterface
{
    public function __construct(private readonly SmsProviderInterface $provider) {}

    public function send(NotificationDelivery $delivery, Notification $notification): void
    {
        if (! $this->provider->isConfigured()) {
            $delivery->markSkipped('SMS provider is not configured.');

            return;
        }
        if (blank($delivery->recipient)) {
            $delivery->markSkipped('Recipient has no phone number on file.');

            return;
        }

        $message = "{$notification->title} — {$notification->body}";
        $result = $this->provider->send($delivery->recipient, $message);
        match (true) {
            $result->success => $delivery->markSent($result->providerMessageId),
            ! $result->retryable => $delivery->markSkipped((string) $result->errorMessage),
            default => $delivery->markFailed((string) $result->errorMessage),
        };
    }
}
