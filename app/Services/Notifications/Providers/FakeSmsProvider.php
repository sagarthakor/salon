<?php

namespace App\Services\Notifications\Providers;

use Illuminate\Support\Str;

class FakeSmsProvider implements SmsProviderInterface
{
    public bool $configured = true;

    public ?ProviderSendResult $nextResult = null;

    /** @var list<array{to: string, message: string}> */
    public array $sent = [];

    public function name(): string
    {
        return 'fake_sms';
    }

    public function isConfigured(): bool
    {
        return $this->configured;
    }

    public function send(string $to, string $message): ProviderSendResult
    {
        $this->sent[] = ['to' => $to, 'message' => $message];

        return $this->nextResult ?? ProviderSendResult::success('fake_'.Str::random(10));
    }
}
