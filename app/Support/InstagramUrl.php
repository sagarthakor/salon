<?php

namespace App\Support;

/**
 * Validates and normalizes an Instagram URL — either a post/reel/video an
 * owner attaches to a service (`isValid()`, e.g. `/p/{id}`), or a salon's
 * official profile link (`isValidProfile()`, e.g. `/{username}`). Never
 * downloads, scrapes, or resolves either kind of URL in any way — this is
 * pure string handling, both here and everywhere the result is used (see
 * ServiceController / SalonController). Never returns a URL whose scheme
 * isn't `https` — a `javascript:`/`data:`/etc. scheme fails validation
 * outright rather than reaching normalization.
 */
class InstagramUrl
{
    private const ALLOWED_HOSTS = ['instagram.com', 'www.instagram.com'];

    /**
     * Reserved first-path-segments Instagram itself uses for non-profile
     * pages — never a valid "username" for a profile URL.
     */
    private const RESERVED_PROFILE_PATHS = ['p', 'reel', 'reels', 'tv', 'explore', 'accounts', 'stories', 'direct', 'about', 'developer'];

    /**
     * Best-effort harmless-variation cleanup applied before validation: adds
     * a missing scheme (defaulting to https, never inventing a destination),
     * upgrades a plain `http://` to `https://`, and lowercases the host.
     * Never changes the path/query, i.e. never changes which post it points
     * to. If the input isn't parseable as a URL at all, it's returned
     * unchanged so the validation rule can reject it with a normal message.
     */
    public static function normalize(string $url): string
    {
        $url = trim($url);
        if ($url === '') {
            return $url;
        }

        $candidate = preg_match('#^[a-zA-Z][a-zA-Z0-9+.\-]*://#', $url) === 1 ? $url : "https://{$url}";
        $parts = parse_url($candidate);
        if ($parts === false || ! isset($parts['scheme'], $parts['host'])) {
            return $url;
        }

        $scheme = strtolower($parts['scheme']) === 'http' ? 'https' : strtolower($parts['scheme']);
        $host = strtolower($parts['host']);
        $path = $parts['path'] ?? '';
        $query = isset($parts['query']) ? '?'.$parts['query'] : '';

        return "{$scheme}://{$host}{$path}{$query}";
    }

    /**
     * Requires `https`, an instagram.com host, and a `/p/`, `/reel/`, or
     * `/tv/` post path — the three share-link shapes Instagram itself
     * produces. Anything else (a different domain, a dangerous scheme, a
     * malformed URL) is rejected.
     */
    public static function isValid(string $url): bool
    {
        $path = self::httpsInstagramPath($url);

        return $path !== null && preg_match('#^/(p|reel|tv)/[A-Za-z0-9_-]+/?$#', $path) === 1;
    }

    /**
     * The post/reel shortcode (the case-sensitive id in `/p|reel|reels|tv/{code}`),
     * or null if the URL is not an instagram.com post link. Tolerant of an
     * optional `www`, trailing slash, query string, and a leading
     * `/{username}` segment, so every equivalent form of one Reel yields the
     * same code. Pure string handling — never fetches the URL.
     */
    public static function shortcode(string $url): ?string
    {
        $parts = parse_url(trim($url));
        if ($parts === false || ! isset($parts['scheme'], $parts['host']) || strtolower($parts['scheme']) !== 'https') {
            return null;
        }
        if (! in_array(strtolower($parts['host']), self::ALLOWED_HOSTS, true)) {
            return null;
        }

        return preg_match('#^(?:/[A-Za-z0-9._]{1,30})?/(?:p|reel|reels|tv)/([A-Za-z0-9_-]+)/?$#', $parts['path'] ?? '', $matches) === 1 ? $matches[1] : null;
    }

    /**
     * One canonical spelling per post (`https://www.instagram.com/{type}/{code}/`,
     * query string dropped), or null if [isValid] would reject it.
     */
    public static function canonical(string $url): ?string
    {
        if (! self::isValid($url)) {
            return null;
        }
        $path = self::httpsInstagramPath($url) ?? '';
        preg_match('#^/(p|reel|tv)/([A-Za-z0-9_-]+)/?$#', $path, $matches);

        return "https://www.instagram.com/{$matches[1]}/{$matches[2]}/";
    }

    /**
     * Requires `https`, an instagram.com host, and a single path segment
     * that is a plausible Instagram username (letters/digits/`.`/`_`,
     * 1–30 chars — Instagram's own limit) and not one of the reserved,
     * non-profile paths Instagram itself uses. Anything else (a different
     * domain, a dangerous scheme, a post/reel link, a malformed URL) is
     * rejected — a profile link is never confused with a content link.
     */
    public static function isValidProfile(string $url): bool
    {
        $path = self::httpsInstagramPath($url);
        if ($path === null || preg_match('#^/([A-Za-z0-9._]{1,30})/?$#', $path, $matches) !== 1) {
            return false;
        }

        return ! in_array(strtolower($matches[1]), self::RESERVED_PROFILE_PATHS, true);
    }

    /**
     * Shared scheme/host check for both link kinds. Returns the URL's path
     * (possibly empty) once `https` + an instagram.com host are confirmed,
     * or `null` for anything that fails either check.
     */
    private static function httpsInstagramPath(string $url): ?string
    {
        $parts = parse_url($url);
        if ($parts === false || ! isset($parts['scheme'], $parts['host'])) {
            return null;
        }
        if ($parts['scheme'] !== 'https') {
            return null;
        }
        if (! in_array(strtolower($parts['host']), self::ALLOWED_HOSTS, true)) {
            return null;
        }

        return $parts['path'] ?? '';
    }
}
