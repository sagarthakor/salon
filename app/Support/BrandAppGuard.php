<?php

namespace App\Support;

use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\Request;

/**
 * Opt-in, additive enforcement for branded single-salon Flutter apps (see
 * config/brand_apps.php). A branded app sends `X-App-Brand: <slug>` on every
 * request; this asserts that whatever tenant a controller just resolved
 * (from a branch/salon/booking id supplied by the client) matches the one
 * tenant that brand is locked to, and 403s otherwise.
 *
 * A request with no `X-App-Brand` header — every existing caller today,
 * including the unbranded multi-tenant customer app — is untouched: this is
 * a no-op unless a caller opts in. It never replaces the existing
 * tenant-resolution/global-scope logic, only adds a check on top of it.
 */
class BrandAppGuard
{
    public function assertTenant(Request $request, ?string $resolvedTenantId): void
    {
        $brand = $request->header('X-App-Brand');
        if ($brand === null || $brand === '') {
            return;
        }

        $allowedTenantId = config("brand_apps.{$brand}");
        if ($allowedTenantId === null) {
            throw new HttpResponseException(ApiResponse::error('Unknown app brand.', [], 403));
        }

        if ($resolvedTenantId !== $allowedTenantId) {
            throw new HttpResponseException(ApiResponse::error('This app is not available for the requested salon.', [], 403));
        }
    }
}
