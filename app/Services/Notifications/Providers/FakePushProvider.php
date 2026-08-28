<?php

namespace App\Services\Notifications\Providers;

use Illuminate\Support\Str;

/**
 * Test-only stand-in for FcmHttpV1Provider — no network access. Configure
 * [$configured]/[$nextResult] to drive success, retryable-failure, and
 * permanent-failure paths deterministically. See FakePaymentGateway for the
 * same pattern used in Phase 10's billing tests.
 */
class FakePushProvider implements PushProviderInterface
{
    public bool $configured = true;

    public ?ProviderSendResult $nextResult = null;

    /** @var list<array{token: string, title: string, body: string, data: array}> */
    public array $sent = [];

    public function name(): string
    {
        return 'fake_push';
    }

    public function isConfigured(): bool
    {
        return $this->configured;
    }

    public function send(string $deviceToken, string $title, string $body, array $data = []): ProviderSendResult
    {
        $this->sent[] = ['token' => $deviceToken, 'title' => $title, 'body' => $body, 'data' => $data];

        return $this->nextResult ?? ProviderSendResult::success('fake_'.Str::random(10));
    }
}
