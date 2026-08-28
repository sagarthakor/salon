<?php

namespace App\Services\Notifications\Channels;

use App\Models\Notification;
use App\Models\NotificationDelivery;
use App\Services\Notifications\Providers\WhatsAppProviderInterface;

class WhatsAppNotificationChannel implements NotificationChannelInterface
{
    public function __construct(private readonly WhatsAppProviderInterface $provider) {}

    public function send(NotificationDelivery $delivery, Notification $notification): void
    {
        if (! $this->provider->isConfigured()) {
            $delivery->markSkipped('WhatsApp provider is not configured.');

            return;
        }
        if (blank($delivery->recipient)) {
            $delivery->markSkipped('Recipient has no phone number on file.');

            return;
        }

        // Not a dotted config() lookup — event type values (e.g.
        // 'booking.created') contain a literal dot; see
        // NotificationPreferenceResolver for the same pitfall.
        $template = config('notifications.whatsapp.templates')[$notification->type->value] ?? null;
        if (blank($template)) {
            $delivery->markSkipped("No approved WhatsApp template configured for '{$notification->type->value}'.");

            return;
        }

        $result = $this->provider->sendTemplate($delivery->recipient, $template, [$notification->title, $notification->body]);
        match (true) {
            $result->success => $delivery->markSent($result->providerMessageId),
            // Permanent provider errors (rejected template, disallowed
            // recipient, ...) are never retried — see retry policy.
            ! $result->retryable => $delivery->markSkipped((string) $result->errorMessage),
            default => $delivery->markFailed((string) $result->errorMessage),
        };
    }
}
