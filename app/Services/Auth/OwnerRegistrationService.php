<?php

namespace App\Services\Auth;

use App\Enums\TenantMembershipRole;
use App\Enums\TenantStatus;
use App\Enums\UserRole;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * Self-service salon-owner registration: creates the owner's `User`, a new
 * `Tenant`, and the owner's `tenant_user` membership in one transaction —
 * the one HTTP-reachable path that creates a `Tenant` at all (see
 * "Tenant onboarding" in PROJECT_ARCHITECTURE.md; every other tenant is
 * created by a seeder or test fixture). `Tenant::booted()`'s `created` hook
 * starts the trial subscription automatically — this class never touches
 * `SubscriptionService` directly, by design, so trial logic has exactly one
 * source of truth regardless of how a tenant comes to exist.
 */
class OwnerRegistrationService
{
    /**
     * @param  array{name: string, email: string, password: string, salon_name: string, slug: ?string}  $data
     * @return array{user: User, tenant: Tenant, token: string}
     */
    public function register(array $data): array
    {
        return DB::transaction(function () use ($data): array {
            $slug = $this->resolveSlug($data['slug'] ?? null, $data['salon_name']);

            // Role is never taken from $data — the caller (RegisterOwnerRequest)
            // never validates a `role` field in the first place, and this is
            // hardcoded regardless, exactly mirroring how AuthController::register()
            // hardcodes UserRole::CUSTOMER.
            $user = User::query()->create([
                'name' => $data['name'],
                'email' => $data['email'],
                'password' => $data['password'],
                'role' => UserRole::SALON_OWNER,
            ]);

            $tenant = $this->createTenantWithUniqueSlug($data['salon_name'], $slug);

            // Never `sync()`/`attach()` a role other than SALON_OWNER here —
            // this is the one and only membership this flow ever creates.
            $tenant->users()->attach($user->id, ['role' => TenantMembershipRole::SALON_OWNER->value]);

            $token = $user->createToken('mobile')->plainTextToken;

            return ['user' => $user->load('tenants'), 'tenant' => $tenant, 'token' => $token];
        });
    }

    /**
     * A cheap pre-check (avoids the common case of a genuinely duplicate
     * slug reaching the database at all) followed by the real guard: the
     * `tenants.slug` unique index itself. A race lost between the pre-check
     * and the insert — two requests picking the same never-seen-before slug
     * in the same instant — is still caught here, never silently allowed
     * through and never left as a bare 500: Laravel's
     * UniqueConstraintViolationException (driver-agnostic; verified against
     * both MySQL and SQLite) is caught and turned into the same
     * ValidationException shape every other 422 in this app already uses.
     */
    private function createTenantWithUniqueSlug(string $name, string $slug): Tenant
    {
        try {
            return Tenant::query()->create([
                'name' => $name,
                'slug' => $slug,
                'status' => TenantStatus::ACTIVE,
            ]);
        } catch (UniqueConstraintViolationException $e) {
            if (in_array('slug', $e->columns, true)) {
                throw ValidationException::withMessages(['slug' => ['This salon slug is already taken.']]);
            }

            throw $e;
        }
    }

    private function resolveSlug(?string $requested, string $salonName): string
    {
        $base = $requested !== null ? Str::slug($requested) : Str::slug($salonName);
        if ($base === '') {
            $base = 'salon';
        }

        $slug = $base;
        $suffix = 1;
        while (Tenant::query()->where('slug', $slug)->exists()) {
            $suffix++;
            $slug = "{$base}-{$suffix}";
        }

        return $slug;
    }
}
