<?php

namespace App\Services\Notifications\Providers;

use Illuminate\Support\Str;

class FakeWhatsAppProvider implements WhatsAppProviderInterface
{
    public bool $configured = true;

    public ?ProviderSendResult $nextResult = null;

    /** @var list<array{to: string, template: string, params: array}> */
    public array $sent = [];

    public function name(): string
    {
        return 'fake_whatsapp';
    }

    public function isConfigured(): bool
    {
        return $this->configured;
    }

    public function sendTemplate(string $to, string $templateName, array $params = []): ProviderSendResult
    {
        $this->sent[] = ['to' => $to, 'template' => $templateName, 'params' => $params];

        return $this->nextResult ?? ProviderSendResult::success('fake_'.Str::random(10));
    }
}
