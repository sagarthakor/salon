<?php

namespace App\Services\Instagram;

use App\Models\InstagramConnection;
use App\Models\Tenant;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;

/**
 * Owner-initiated OAuth connection to the tenant's own Instagram
 * Professional account. Tokens live only in `instagram_connections`
 * (encrypted); nothing here ever returns one to a caller.
 */
class InstagramConnectionService
{
    private const STATE_TTL_MINUTES = 10;

    /** Meta refuses to refresh a token younger than 24 hours. */
    private const MIN_REFRESH_AGE_HOURS = 24;

    public function __construct(private readonly InstagramClient $client) {}

    /** Single-use, tenant+user-bound `state` so the public callback can't be forged or replayed. */
    public function beginAuthorization(Tenant $tenant, User $user): string
    {
        $state = Str::random(48);
        Cache::put($this->stateKey($state), ['tenant_id' => $tenant->id, 'user_id' => $user->id], now()->addMinutes(self::STATE_TTL_MINUTES));

        return $this->client->authorizationUrl($state);
    }

    /**
     * Completes the callback. Returns the connection, or throws
     * InstagramApiException (invalid/expired state, Meta errors).
     */
    public function completeAuthorization(string $state, string $code): InstagramConnection
    {
        $payload = Cache::pull($this->stateKey($state));
        if (! is_array($payload)) {
            throw new InstagramApiException(InstagramApiException::AUTH, 'This authorization link is invalid or has expired. Please start again from the app.');
        }
        $tenant = Tenant::query()->find($payload['tenant_id']);
        if ($tenant === null) {
            throw new InstagramApiException(InstagramApiException::AUTH, 'This authorization link is invalid or has expired. Please start again from the app.');
        }

        // Instagram appends `#_` to the redirect; never part of the code.
        $code = rtrim($code, '#_');
        $short = $this->client->exchangeCode($code);
        $long = $this->client->exchangeForLongLivedToken($short['access_token']);
        $profile = $this->client->profile($long['access_token']);

        $context = app(TenantContext::class);
        $context->set($tenant);
        try {
            return InstagramConnection::query()->updateOrCreate([], [
                'connected_by' => $payload['user_id'],
                'instagram_user_id' => (string) ($profile['user_id'] ?? $profile['id'] ?? $short['user_id']),
                'username' => $profile['username'] ?? null,
                'account_type' => $profile['account_type'] ?? null,
                'access_token' => $long['access_token'],
                'token_expires_at' => now()->addSeconds($long['expires_in']),
                'token_refreshed_at' => now(),
                'status' => InstagramConnection::STATUS_ACTIVE,
                'last_error' => null,
            ]);
        } finally {
            $context->clear();
        }
    }

    /** Refreshes one token; flags the connection as expired if Meta rejects it. */
    public function refresh(InstagramConnection $connection): bool
    {
        if ($connection->token_refreshed_at !== null && $connection->token_refreshed_at->gt(now()->subHours(self::MIN_REFRESH_AGE_HOURS))) {
            return false;
        }
        try {
            $token = $this->client->refreshLongLivedToken($connection->access_token);
        } catch (InstagramApiException $exception) {
            if ($exception->kind === InstagramApiException::AUTH) {
                $this->markExpired($connection, $exception->getMessage());
            }

            return false;
        }
        $connection->forceFill([
            'access_token' => $token['access_token'],
            'token_expires_at' => now()->addSeconds($token['expires_in']),
            'token_refreshed_at' => now(),
            'status' => InstagramConnection::STATUS_ACTIVE,
            'last_error' => null,
        ])->save();

        return true;
    }

    public function markExpired(InstagramConnection $connection, string $reason): void
    {
        $connection->forceFill(['status' => InstagramConnection::STATUS_EXPIRED, 'last_error' => mb_substr($reason, 0, 250)])->save();
    }

    /**
     * Disconnect = delete our stored token. Meta exposes no token-revoke
     * endpoint for this login type; the owner can also remove the app under
     * Instagram → Settings → Apps and websites. Already-synced gallery rows
     * are kept (only the owner's explicit delete removes them).
     */
    public function disconnect(InstagramConnection $connection): void
    {
        $connection->delete();
    }

    private function stateKey(string $state): string
    {
        return 'instagram_oauth_state:'.hash('sha256', $state);
    }
}
