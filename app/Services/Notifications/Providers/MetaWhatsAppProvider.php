<?php

namespace App\Services\Notifications\Providers;

use Illuminate\Support\Facades\Http;

/**
 * Official Meta WhatsApp Cloud API — never an unofficial client, never
 * WhatsApp Web automation/scraping (see NOTIFICATION_ARCHITECTURE.md,
 * "WhatsApp architecture"). Sends only pre-approved templates; arbitrary
 * free-text session messages are out of scope for this phase since template
 * approval is required for business-initiated messages outside a customer's
 * 24-hour service window.
 */
class MetaWhatsAppProvider implements WhatsAppProviderInterface
{
    public function __construct(
        private readonly ?string $accessToken,
        private readonly ?string $phoneNumberId,
        private readonly string $apiBaseUrl,
    ) {}

    public function name(): string
    {
        return 'meta_whatsapp';
    }

    public function isConfigured(): bool
    {
        return filled($this->accessToken) && filled($this->phoneNumberId);
    }

    public function sendTemplate(string $to, string $templateName, array $params = []): ProviderSendResult
    {
        if (! $this->isConfigured()) {
            return ProviderSendResult::permanentFailure('WhatsApp is not configured.');
        }

        $response = Http::withToken($this->accessToken)
            ->post("{$this->apiBaseUrl}/{$this->phoneNumberId}/messages", [
                'messaging_product' => 'whatsapp',
                'to' => $to,
                'type' => 'template',
                'template' => [
                    'name' => $templateName,
                    'language' => ['code' => 'en'],
                    'components' => $params === [] ? [] : [[
                        'type' => 'body',
                        'parameters' => array_map(static fn (string $p): array => ['type' => 'text', 'text' => $p], $params),
                    ]],
                ],
            ]);

        if ($response->successful()) {
            return ProviderSendResult::success($response->json('messages.0.id'));
        }

        $errorCode = $response->json('error.code');
        // Meta error 132001 = template does not exist/not approved; 131030 =
        // recipient number not allowed. Both are permanent — retrying with
        // the same inputs will never succeed.
        $permanent = in_array($errorCode, [132001, 131030, 131047, 131026], true);
        $message = (string) $response->json('error.message', 'WhatsApp request failed.');

        return $permanent ? ProviderSendResult::permanentFailure($message) : ProviderSendResult::retryableFailure($message);
    }
}
