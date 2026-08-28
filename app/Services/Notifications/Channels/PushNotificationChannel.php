<?php

namespace App\Services\Notifications\Channels;

use App\Models\Notification;
use App\Models\NotificationDelivery;
use App\Models\UserDeviceToken;
use App\Services\Notifications\Providers\PushProviderInterface;

class PushNotificationChannel implements NotificationChannelInterface
{
    public function __construct(private readonly PushProviderInterface $provider) {}

    public function send(NotificationDelivery $delivery, Notification $notification): void
    {
        if (! $this->provider->isConfigured()) {
            $delivery->markSkipped('Push provider is not configured.');

            return;
        }

        $tokens = UserDeviceToken::query()->where('user_id', $notification->user_id)->where('is_active', true)->get();
        if ($tokens->isEmpty()) {
            $delivery->markSkipped('No active device token for this user.');

            return;
        }

        $data = array_merge((array) $notification->data, [
            'notification_id' => $notification->id,
            'type' => $notification->type->value,
        ]);

        $anySent = false;
        $anyRetryable = false;
        $lastError = null;
        foreach ($tokens as $token) {
            $result = $this->provider->send($token->token, $notification->title, $notification->body, $data);
            if ($result->success) {
                $anySent = true;

                continue;
            }
            $lastError = $result->errorMessage;
            if ($result->retryable) {
                $anyRetryable = true;
            } else {
                // Provider says this token is dead (unregistered/invalid) —
                // deactivate it so future sends don't waste an attempt on it.
                $token->update(['is_active' => false]);
            }
        }

        if ($anySent) {
            $delivery->markSent();

            return;
        }

        $lastError ??= 'Push delivery failed for every registered device.';
        // Only retry if at least one failure was transient — if every token
        // was permanently rejected, retrying would just repeat the same
        // outcome forever.
        $anyRetryable ? $delivery->markFailed($lastError) : $delivery->markSkipped($lastError);
    }
}
