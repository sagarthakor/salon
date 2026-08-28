<?php

namespace App\Services\Notifications\Providers;

/**
 * The only contract SmsNotificationChannel depends on. No production SMS
 * vendor has been selected yet — see NOTIFICATION_ARCHITECTURE.md, "SMS
 * architecture" — so this currently binds to LogSmsProvider, which never
 * sends a real message. Swap the AppServiceProvider binding once a vendor is
 * chosen; nothing else in the codebase needs to change.
 */
interface SmsProviderInterface
{
    public function name(): string;

    public function isConfigured(): bool;

    public function send(string $to, string $message): ProviderSendResult;
}
