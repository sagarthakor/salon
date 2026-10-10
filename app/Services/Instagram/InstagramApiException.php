<?php

namespace App\Services\Instagram;

use RuntimeException;

/**
 * A failed Instagram API call. Messages are safe to show an owner and never
 * contain a URL, token, or raw provider payload.
 */
class InstagramApiException extends RuntimeException
{
    public const NOT_CONFIGURED = 'not_configured';

    public const AUTH = 'auth';

    public const RATE_LIMITED = 'rate_limited';

    public const PERMISSION = 'permission';

    public const INVALID_REQUEST = 'invalid_request';

    public const UNAVAILABLE = 'unavailable';

    public function __construct(public readonly string $kind, string $message)
    {
        parent::__construct($message);
    }

    /**
     * Stable, client-facing identifier (part of the API contract — do not rename).
     * `reconnect_required` means the token is bad and the connection is flagged
     * expired; `permission_denied` means access is missing but the token is fine.
     */
    public function publicKind(): string
    {
        return match ($this->kind) {
            self::NOT_CONFIGURED => 'not_configured',
            self::AUTH => 'reconnect_required',
            self::PERMISSION => 'permission_denied',
            self::RATE_LIMITED => 'rate_limited',
            self::INVALID_REQUEST => 'invalid_request',
            default => 'unavailable',
        };
    }

    public function httpStatus(): int
    {
        return match ($this->kind) {
            self::NOT_CONFIGURED => 503,
            self::AUTH, self::PERMISSION => 409,
            self::RATE_LIMITED => 429,
            default => 502,
        };
    }
}
