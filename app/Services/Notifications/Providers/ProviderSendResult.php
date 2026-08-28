<?php

namespace App\Services\Notifications\Providers;

/**
 * The uniform result every provider (push/WhatsApp/SMS) returns, so
 * SendNotificationDeliveryJob never has to know which provider it just
 * called. [$retryable] drives the retry policy — a provider sets it to
 * false for permanent errors (invalid phone number, rejected template, an
 * unregistered/expired push token) so those never get retried forever; see
 * NOTIFICATION_ARCHITECTURE.md, "Retry strategy".
 */
final class ProviderSendResult
{
    public function __construct(
        public readonly bool $success,
        public readonly ?string $providerMessageId = null,
        public readonly ?string $errorMessage = null,
        public readonly bool $retryable = true,
    ) {}

    public static function success(?string $providerMessageId = null): self
    {
        return new self(success: true, providerMessageId: $providerMessageId);
    }

    public static function permanentFailure(string $errorMessage): self
    {
        return new self(success: false, errorMessage: $errorMessage, retryable: false);
    }

    public static function retryableFailure(string $errorMessage): self
    {
        return new self(success: false, errorMessage: $errorMessage, retryable: true);
    }
}
