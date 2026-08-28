<?php

namespace App\Services\Notifications\Providers;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;
use Throwable;

/**
 * Firebase Cloud Messaging via the HTTP v1 API, authenticated with a
 * service-account JWT assertion — signed by hand with openssl (RS256) so no
 * new Composer dependency (e.g. a Firebase Admin SDK / firebase/php-jwt) is
 * required. See NOTIFICATION_ARCHITECTURE.md, "Push architecture", for why:
 * this repo has no internet-independent way to vendor a new package inside
 * this phase, and the JWT assertion flow is only ~30 lines of stdlib code.
 *
 * `isConfigured()` gates every call site: with no FCM_PROJECT_ID/
 * FCM_CLIENT_EMAIL/FCM_PRIVATE_KEY set, this provider is inert and
 * PushNotificationChannel marks the delivery SKIPPED rather than attempting
 * a call that can never succeed — see section 26/49 of the Phase 11 spec:
 * do not claim real push delivery without real credentials.
 */
class FcmHttpV1Provider implements PushProviderInterface
{
    private const TOKEN_URL = 'https://oauth2.googleapis.com/token';

    private const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

    public function __construct(
        private readonly ?string $projectId,
        private readonly ?string $clientEmail,
        private readonly ?string $privateKey,
    ) {}

    public function name(): string
    {
        return 'fcm';
    }

    public function isConfigured(): bool
    {
        return filled($this->projectId) && filled($this->clientEmail) && filled($this->privateKey);
    }

    public function send(string $deviceToken, string $title, string $body, array $data = []): ProviderSendResult
    {
        if (! $this->isConfigured()) {
            return ProviderSendResult::permanentFailure('FCM is not configured.');
        }

        try {
            $accessToken = $this->accessToken();
        } catch (Throwable $e) {
            Log::warning('FCM: failed to obtain an access token.', ['error' => $e->getMessage()]);

            return ProviderSendResult::retryableFailure('Could not authenticate with FCM.');
        }

        $response = Http::withToken($accessToken)
            ->post("https://fcm.googleapis.com/v1/projects/{$this->projectId}/messages:send", [
                'message' => [
                    'token' => $deviceToken,
                    'notification' => ['title' => $title, 'body' => $body],
                    'data' => array_map(static fn ($v): string => (string) $v, $data),
                ],
            ]);

        if ($response->successful()) {
            return ProviderSendResult::success($response->json('name'));
        }

        $errorStatus = (string) $response->json('error.status', '');
        // UNREGISTERED/INVALID_ARGUMENT mean the token is dead or malformed —
        // retrying will never succeed, so the channel should deactivate it
        // instead (see PushNotificationChannel).
        $permanent = in_array($errorStatus, ['UNREGISTERED', 'INVALID_ARGUMENT', 'NOT_FOUND'], true);
        $message = (string) $response->json('error.message', 'FCM request failed.');

        return $permanent ? ProviderSendResult::permanentFailure($message) : ProviderSendResult::retryableFailure($message);
    }

    private function accessToken(): string
    {
        return Cache::remember('fcm:access_token:'.md5((string) $this->clientEmail), 50 * 60, function (): string {
            $now = time();
            $header = $this->base64UrlEncode(json_encode(['alg' => 'RS256', 'typ' => 'JWT'], JSON_THROW_ON_ERROR));
            $claims = $this->base64UrlEncode(json_encode([
                'iss' => $this->clientEmail,
                'scope' => self::SCOPE,
                'aud' => self::TOKEN_URL,
                'iat' => $now,
                'exp' => $now + 3600,
            ], JSON_THROW_ON_ERROR));

            $signingInput = "{$header}.{$claims}";
            $signature = '';
            $privateKey = openssl_pkey_get_private((string) $this->privateKey);
            if ($privateKey === false || ! openssl_sign($signingInput, $signature, $privateKey, OPENSSL_ALGO_SHA256)) {
                throw new RuntimeException('Unable to sign the FCM service-account JWT.');
            }

            $jwt = $signingInput.'.'.$this->base64UrlEncode($signature);

            $response = Http::asForm()->post(self::TOKEN_URL, [
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion' => $jwt,
            ]);

            if (! $response->successful() || ! is_string($response->json('access_token'))) {
                throw new RuntimeException('FCM token endpoint did not return an access token.');
            }

            return $response->json('access_token');
        });
    }

    private function base64UrlEncode(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }
}
