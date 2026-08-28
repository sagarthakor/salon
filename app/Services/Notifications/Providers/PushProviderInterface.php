<?php

namespace App\Services\Notifications\Providers;

/**
 * The only contract PushNotificationChannel depends on — never a vendor SDK
 * directly. Bound in AppServiceProvider to FcmHttpV1Provider; tests bind
 * FakePushProvider instead. See NOTIFICATION_ARCHITECTURE.md, "Push
 * architecture".
 */
interface PushProviderInterface
{
    public function name(): string;

    public function isConfigured(): bool;

    /**
     * @param  array<string, scalar>  $data  typed deep-link payload (see NotificationMessageBuilder) — never
     *                                       arbitrary/untrusted routing strings from outside the backend
     */
    public function send(string $deviceToken, string $title, string $body, array $data = []): ProviderSendResult;
}
