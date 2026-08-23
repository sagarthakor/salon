<?php

namespace App\Http\Middleware;

use App\Enums\TenantStatus;
use App\Enums\UserRole;
use App\Models\Tenant;
use App\Support\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class ResolveTenantContext
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['success' => false, 'message' => 'Unauthenticated.', 'errors' => (object) []], 401);
        } $slug = $request->header('X-Tenant-Slug');
        $memberships = $user->role === UserRole::SUPER_ADMIN
            ? Tenant::query()->where('status', TenantStatus::ACTIVE->value)
            : $user->tenants()->where('status', TenantStatus::ACTIVE->value);
        $tenant = $slug ? $memberships->where('slug', $slug)->first() : $memberships->first();
        if ($tenant === null) {
            return response()->json(['success' => false, 'message' => 'A valid tenant membership is required.', 'errors' => (object) []], 403);
        } $context = app(TenantContext::class);
        $context->set($tenant);
        try {
            return $next($request);
        } finally {
            $context->clear();
        }
    }
}
