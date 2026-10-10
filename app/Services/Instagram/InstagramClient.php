<?php

namespace App\Services\Instagram;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;

/**
 * Thin wrapper over the official Instagram API with Instagram Login
 * (graph.instagram.com / api.instagram.com). Never scrapes, never fetches
 * media files. Deliberately does not use `->throw()` so a failure's URL
 * (which carries the access token as a query parameter) can never end up in
 * an exception message or log.
 */
class InstagramClient
{
    /** Documented Graph/Instagram rate-limit codes (80002 = Instagram business-use-case limit). */
    private const RATE_LIMIT_CODES = [4, 17, 32, 613, 80002];

    /** Token invalid/expired/revoked: 190 and 102 (session), plus the OAuth subcodes below. */
    private const AUTH_CODES = [190, 102];

    /** 458 app not authorized, 459 checkpoint, 460 password changed, 463 expired, 467 invalid. */
    private const AUTH_SUBCODES = [458, 459, 460, 463, 467];

    public function isConfigured(): bool
    {
        return filled(config('services.instagram.app_id'))
            && filled(config('services.instagram.app_secret'))
            && filled(config('services.instagram.redirect_uri'));
    }

    public function authorizationUrl(string $state): string
    {
        $this->assertConfigured();

        return config('services.instagram.authorize_url').'?'.http_build_query([
            'client_id' => config('services.instagram.app_id'),
            'redirect_uri' => config('services.instagram.redirect_uri'),
            'response_type' => 'code',
            'scope' => implode(',', config('services.instagram.scopes')),
            'state' => $state,
        ]);
    }

    /** @return array{access_token: string, user_id: string} */
    public function exchangeCode(string $code): array
    {
        $this->assertConfigured();
        $response = $this->send(fn () => Http::asForm()->timeout(15)->post(config('services.instagram.oauth_url').'/oauth/access_token', [
            'client_id' => config('services.instagram.app_id'),
            'client_secret' => config('services.instagram.app_secret'),
            'grant_type' => 'authorization_code',
            'redirect_uri' => config('services.instagram.redirect_uri'),
            'code' => $code,
        ]));
        $data = $this->decode($response, tokenExchange: true);
        // Short-lived responses are either flat or wrapped in `data[0]`.
        $data = $data['data'][0] ?? $data;
        if (! isset($data['access_token'], $data['user_id'])) {
            throw new InstagramApiException(InstagramApiException::AUTH, 'Instagram did not return an access token.');
        }

        return ['access_token' => (string) $data['access_token'], 'user_id' => (string) $data['user_id']];
    }

    /** @return array{access_token: string, expires_in: int} */
    public function exchangeForLongLivedToken(string $shortLivedToken): array
    {
        $this->assertConfigured();
        $response = $this->send(fn () => Http::timeout(15)->get(config('services.instagram.graph_url').'/access_token', [
            'grant_type' => 'ig_exchange_token',
            'client_secret' => config('services.instagram.app_secret'),
            'access_token' => $shortLivedToken,
        ]));

        return $this->tokenPayload($this->decode($response, tokenExchange: true));
    }

    /** @return array{access_token: string, expires_in: int} */
    public function refreshLongLivedToken(string $token): array
    {
        $this->assertConfigured();
        $response = $this->send(fn () => Http::timeout(15)->get(config('services.instagram.graph_url').'/refresh_access_token', [
            'grant_type' => 'ig_refresh_token',
            'access_token' => $token,
        ]));

        return $this->tokenPayload($this->decode($response));
    }

    /** @return array<string, mixed> */
    public function profile(string $token): array
    {
        $response = $this->send(fn () => Http::timeout(15)->get(config('services.instagram.graph_url').'/me', [
            'fields' => 'user_id,username,account_type',
            'access_token' => $token,
        ]));

        return $this->decode($response);
    }

    /**
     * One page of the account's media metadata. Deliberately does not request
     * `media_url`: the gallery never downloads or re-hosts Instagram media.
     *
     * @return array<string, mixed>
     */
    public function mediaPage(string $token, ?string $after = null): array
    {
        $query = [
            // Only fields the IG Media reference does not restrict to Facebook Login
            // (`media_product_type` is, so it is deliberately not requested).
            'fields' => 'id,caption,media_type,permalink,thumbnail_url,timestamp',
            'limit' => 50,
            'access_token' => $token,
        ];
        if ($after !== null) {
            $query['after'] = $after;
        }
        $response = $this->send(fn () => Http::timeout(20)->get(config('services.instagram.graph_url').'/me/media', $query));

        return $this->decode($response);
    }

    private function assertConfigured(): void
    {
        if (! $this->isConfigured()) {
            throw new InstagramApiException(InstagramApiException::NOT_CONFIGURED, 'Instagram connection is not configured on this server.');
        }
    }

    private function send(callable $request): Response
    {
        try {
            return $request();
        } catch (ConnectionException) {
            throw new InstagramApiException(InstagramApiException::UNAVAILABLE, 'Could not reach Instagram. Please try again shortly.');
        }
    }

    /**
     * Maps a response to either its decoded body or a typed exception. Only a
     * genuine token problem is AUTH (which callers treat as "connection
     * expired"); a bad field/parameter, missing permission, or outage never
     * is, so a transient or code-level error can't force an owner to
     * reconnect. During the code/token exchange itself any client error means
     * the authorization attempt failed, so those are AUTH.
     *
     * @return array<string, mixed>
     */
    private function decode(Response $response, bool $tokenExchange = false): array
    {
        $body = $response->json();
        $body = is_array($body) ? $body : [];

        if ($response->successful() && ! isset($body['error'])) {
            return $body;
        }

        // Errors are nested under `error` on the Graph host, flat on api.instagram.com.
        $error = is_array($body['error'] ?? null) ? $body['error'] : $body;
        $code = (int) ($error['code'] ?? 0);
        $subcode = (int) ($error['error_subcode'] ?? 0);

        if ($response->status() === 429 || in_array($code, self::RATE_LIMIT_CODES, true)) {
            throw new InstagramApiException(InstagramApiException::RATE_LIMITED, 'Instagram is rate limiting requests. Please try again later.');
        }
        if ($response->status() === 401 || in_array($code, self::AUTH_CODES, true) || in_array($subcode, self::AUTH_SUBCODES, true)
            || ($tokenExchange && $response->clientError())) {
            throw new InstagramApiException(InstagramApiException::AUTH, 'Instagram authorization failed or has expired. Please reconnect your account.');
        }
        if ($code === 10 || ($code >= 200 && $code <= 299)) {
            throw new InstagramApiException(InstagramApiException::PERMISSION, 'Instagram has not granted the access this needs. Please reconnect and approve access.');
        }
        if ($code === 100) {
            throw new InstagramApiException(InstagramApiException::INVALID_REQUEST, 'Instagram rejected the request. Please try again later.');
        }

        throw new InstagramApiException(InstagramApiException::UNAVAILABLE, 'Instagram returned an unexpected error. Please try again later.');
    }

    /**
     * @param  array<string, mixed>  $data
     * @return array{access_token: string, expires_in: int}
     */
    private function tokenPayload(array $data): array
    {
        if (! isset($data['access_token'])) {
            throw new InstagramApiException(InstagramApiException::AUTH, 'Instagram did not return an access token.');
        }

        return ['access_token' => (string) $data['access_token'], 'expires_in' => (int) ($data['expires_in'] ?? 5183944)];
    }
}
