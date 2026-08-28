<?php

namespace App\Http\Middleware;

use App\Enums\SubscriptionStatus;
use App\Models\Subscription;
use App\Support\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Gates normal business-feature routes (branches, services, staff,
 * customers, bookings, dashboard) on the current tenant's subscription
 * standing. Deliberately NOT applied to `/subscription*` — billing,
 * renewal, and cancellation must always be reachable regardless of status,
 * so an expired owner is never locked out of fixing it. Runs after
 * `tenant.context` (needs `TenantContext` already resolved).
 *
 * Allowed statuses: TRIALING, ACTIVE, PAST_DUE, GRACE_PERIOD — see
 * `SubscriptionStatus::accessAllowed()` and SAAS_BILLING_ARCHITECTURE.md.
 * Blocked: CANCELLED, EXPIRED, or no subscription row at all.
 */
class EnsureActiveSubscription
{
    public function handle(Request $request, Closure $next): Response
    {
        $tenant = app(TenantContext::class)->get();
        $subscription = $tenant !== null ? Subscription::query()->first() : null;

        if ($subscription === null || ! in_array($subscription->status, SubscriptionStatus::accessAllowed(), true)) {
            return response()->json([
                'success' => false,
                'message' => "Your salon's subscription is not active. Please renew to continue.",
                'errors' => (object) [],
            ], 402);
        }

        return $next($request);
    }
}
