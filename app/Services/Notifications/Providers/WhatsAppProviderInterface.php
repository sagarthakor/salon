<?php

namespace App\Services\Notifications\Providers;

/**
 * The only contract WhatsAppNotificationChannel depends on. Bound to
 * MetaWhatsAppProvider (official Meta WhatsApp Cloud API — never an
 * unofficial/automation-based client). See NOTIFICATION_ARCHITECTURE.md,
 * "WhatsApp architecture".
 */
interface WhatsAppProviderInterface
{
    public function name(): string;

    public function isConfigured(): bool;

    /**
     * @param  string  $templateName  a pre-approved Meta template name — see config('notifications.whatsapp.templates'),
     *                                never a provider template id hard-coded into business logic
     * @param  list<string>  $params  positional template variables, in order
     */
    public function sendTemplate(string $to, string $templateName, array $params = []): ProviderSendResult;
}
