<?php

namespace Tests\Feature;

use App\Enums\SubscriptionStatus;
use App\Enums\TenantMembershipRole;
use App\Enums\TenantStatus;
use App\Enums\UserRole;
use App\Models\Plan;
use App\Models\Subscription;
use App\Models\Tenant;
use App\Models\User;
use App\Services\Auth\OwnerRegistrationService;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use RuntimeException;
use Tests\TestCase;

class OwnerRegistrationApiTest extends TestCase
{
    use RefreshDatabase;

    private function payload(array $overrides = []): array
    {
        return array_merge([
            'name' => 'Asha Owner',
            'email' => 'asha-owner@example.test',
            'password' => 'SecurePassword1!',
            'password_confirmation' => 'SecurePassword1!',
            'salon_name' => 'Asha Hair Studio',
        ], $overrides);
    }

    private function makeTenant(string $slug): Tenant
    {
        return Tenant::query()->create(['name' => $slug, 'slug' => $slug, 'status' => TenantStatus::ACTIVE]);
    }

    public function test_owner_registration_succeeds_and_returns_user_token_and_tenant_slug(): void
    {
        $response = $this->postJson('/api/v1/auth/register-owner', $this->payload());

        $response->assertCreated()->assertJsonPath('success', true)
            ->assertJsonPath('data.user.name', 'Asha Owner')
            ->assertJsonPath('data.user.email', 'asha-owner@example.test')
            ->assertJsonPath('data.user.role', 'salon_owner')
            ->assertJsonPath('data.tenant_slug', 'asha-hair-studio')
            ->assertJsonStructure(['data' => ['token']])
            ->assertJsonMissingPath('data.user.password');
    }

    public function test_the_new_user_has_the_salon_owner_platform_role(): void
    {
        $this->postJson('/api/v1/auth/register-owner', $this->payload())->assertCreated();

        $this->assertDatabaseHas('users', ['email' => 'asha-owner@example.test', 'role' => UserRole::SALON_OWNER->value]);
    }

    public function test_a_tenant_is_created_for_the_new_salon(): void
    {
        $this->postJson('/api/v1/auth/register-owner', $this->payload())->assertCreated();

        $this->assertDatabaseHas('tenants', ['slug' => 'asha-hair-studio', 'name' => 'Asha Hair Studio', 'status' => 'active']);
    }

    public function test_owner_membership_is_created_with_the_salon_owner_role(): void
    {
        $this->postJson('/api/v1/auth/register-owner', $this->payload())->assertCreated();

        $user = User::where('email', 'asha-owner@example.test')->first();
        $tenant = Tenant::where('slug', 'asha-hair-studio')->first();

        $this->assertDatabaseHas('tenant_user', [
            'user_id' => $user->id,
            'tenant_id' => $tenant->id,
            'role' => TenantMembershipRole::SALON_OWNER->value,
        ]);
        $this->assertSame(1, $user->tenants()->count());
    }

    public function test_returned_tenant_slug_matches_the_created_tenant(): void
    {
        $data = $this->postJson('/api/v1/auth/register-owner', $this->payload())->assertCreated()->json('data');

        $tenant = Tenant::where('name', 'Asha Hair Studio')->first();
        $this->assertSame($tenant->slug, $data['tenant_slug']);
    }

    public function test_an_authentication_token_is_returned_and_works(): void
    {
        $data = $this->postJson('/api/v1/auth/register-owner', $this->payload())->assertCreated()->json('data');

        $this->withToken($data['token'])->getJson('/api/v1/auth/me')
            ->assertOk()->assertJsonPath('data.email', 'asha-owner@example.test');
    }

    /**
     * `Subscription` uses `BelongsToTenant`, so reading it back here (with
     * no request-scoped TenantContext active, unlike the real HTTP flow)
     * must bypass the global scope explicitly — the same
     * `withoutGlobalScope('tenant')` pattern already used throughout this
     * project's own cross-tenant test assertions.
     */
    private function subscriptionFor(Tenant $tenant): ?Subscription
    {
        return Subscription::withoutGlobalScope('tenant')->where('tenant_id', $tenant->id)->first();
    }

    public function test_a_trial_subscription_is_automatically_created_via_the_existing_tenant_booted_hook(): void
    {
        $this->postJson('/api/v1/auth/register-owner', $this->payload())->assertCreated();

        $tenant = Tenant::where('slug', 'asha-hair-studio')->first();
        $subscription = $this->subscriptionFor($tenant);
        $this->assertNotNull($subscription);
        $this->assertSame(SubscriptionStatus::TRIALING, $subscription->status);
    }

    public function test_the_trial_uses_the_existing_default_active_plan_never_a_hardcoded_one(): void
    {
        $this->postJson('/api/v1/auth/register-owner', $this->payload())->assertCreated();

        $tenant = Tenant::where('slug', 'asha-hair-studio')->first();
        $expectedPlan = Plan::query()->where('is_active', true)->oldest()->first();

        $this->assertSame($expectedPlan->id, $this->subscriptionFor($tenant)->plan_id);
    }

    public function test_the_trial_duration_matches_the_plans_own_configured_trial_days_not_a_hardcoded_number(): void
    {
        $this->postJson('/api/v1/auth/register-owner', $this->payload())->assertCreated();

        $tenant = Tenant::where('slug', 'asha-hair-studio')->first();
        $subscription = $this->subscriptionFor($tenant);
        $plan = Plan::find($subscription->plan_id);

        $this->assertEqualsWithDelta(
            $subscription->trial_starts_at->addDays($plan->trial_days)->timestamp,
            $subscription->trial_ends_at->timestamp,
            2,
        );
    }

    public function test_duplicate_email_is_rejected(): void
    {
        User::factory()->create(['email' => 'taken@example.test']);

        $this->postJson('/api/v1/auth/register-owner', $this->payload(['email' => 'taken@example.test']))
            ->assertStatus(422)->assertJsonValidationErrors('email');
        $this->assertSame(0, Tenant::count());
    }

    public function test_an_explicitly_supplied_duplicate_slug_is_rejected_with_a_clean_validation_error(): void
    {
        $this->makeTenant('taken-slug');

        $this->postJson('/api/v1/auth/register-owner', $this->payload(['slug' => 'taken-slug']))
            ->assertStatus(422)->assertJsonValidationErrors('slug');
    }

    public function test_an_omitted_slug_colliding_with_an_existing_one_is_auto_resolved_with_a_numeric_suffix(): void
    {
        $this->makeTenant('asha-hair-studio');

        $data = $this->postJson('/api/v1/auth/register-owner', $this->payload())->assertCreated()->json('data');

        $this->assertSame('asha-hair-studio-2', $data['tenant_slug']);
    }

    public function test_slug_uniqueness_is_enforced_by_a_real_database_constraint_not_just_a_pre_check(): void
    {
        $this->makeTenant('race-slug');

        $this->expectException(UniqueConstraintViolationException::class);
        $this->makeTenant('race-slug');
    }

    public function test_missing_required_fields_are_rejected(): void
    {
        $this->postJson('/api/v1/auth/register-owner', [])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['name', 'email', 'password', 'salon_name']);
    }

    public function test_password_confirmation_mismatch_is_rejected(): void
    {
        $this->postJson('/api/v1/auth/register-owner', $this->payload(['password_confirmation' => 'SomethingElse1!']))
            ->assertStatus(422)->assertJsonValidationErrors('password');
    }

    public function test_client_supplied_role_is_ignored_and_server_always_assigns_salon_owner(): void
    {
        $response = $this->postJson('/api/v1/auth/register-owner', $this->payload(['role' => 'super_admin']));

        $response->assertCreated()->assertJsonPath('data.user.role', 'salon_owner');
        $this->assertDatabaseHas('users', ['email' => 'asha-owner@example.test', 'role' => UserRole::SALON_OWNER->value]);
    }

    public function test_client_supplied_tenant_id_is_ignored_and_a_fresh_tenant_is_always_created(): void
    {
        $existing = $this->makeTenant('existing-salon');

        $response = $this->postJson('/api/v1/auth/register-owner', $this->payload(['tenant_id' => $existing->id]));

        $response->assertCreated();
        $newSlug = $response->json('data.tenant_slug');
        $this->assertNotSame($existing->slug, $newSlug);
        $this->assertDatabaseCount('tenants', 2);
    }

    /**
     * Forces a failure between the two writes the transaction must cover
     * (User, then Tenant) via a `Tenant::creating` listener — deterministic
     * and portable across SQLite/MySQL, unlike trying to force a genuine
     * unique-constraint race synchronously in a single-threaded test. Proves
     * the whole registration really is one atomic unit, not two sequential
     * operations that could leave an owner-less orphan user behind.
     */
    public function test_a_failure_after_the_user_is_created_rolls_back_the_entire_registration(): void
    {
        Tenant::creating(function (): void {
            throw new RuntimeException('Simulated failure between user and tenant creation.');
        });

        try {
            app(OwnerRegistrationService::class)->register([
                'name' => 'Rollback Owner',
                'email' => 'rollback-owner@example.test',
                'password' => 'SecurePassword1!',
                'salon_name' => 'Rollback Salon',
                'slug' => null,
            ]);
            $this->fail('Expected the simulated exception to propagate.');
        } catch (RuntimeException $e) {
            $this->assertSame('Simulated failure between user and tenant creation.', $e->getMessage());
        }

        $this->assertDatabaseMissing('users', ['email' => 'rollback-owner@example.test']);
        $this->assertSame(0, Tenant::count());
    }

    public function test_the_newly_registered_owner_can_only_access_their_own_new_tenant(): void
    {
        $otherTenant = $this->makeTenant('other-salon');

        $data = $this->postJson('/api/v1/auth/register-owner', $this->payload())->assertCreated()->json('data');
        $api = $this->withToken($data['token']);

        // Own tenant resolves fine (no salon profile created yet, so 404 —
        // not a 403 — which is exactly what proves tenant context resolved).
        $api->getJson('/api/v1/salon')->assertStatus(404);

        // Someone else's tenant, even explicitly requested by slug, is denied.
        $api->withHeader('X-Tenant-Slug', $otherTenant->slug)->getJson('/api/v1/salon')->assertForbidden();
    }

    public function test_existing_customer_registration_is_completely_unaffected(): void
    {
        $response = $this->postJson('/api/v1/auth/register', [
            'name' => 'Still A Customer', 'email' => 'still-customer@example.test',
            'password' => 'SecurePassword1!', 'password_confirmation' => 'SecurePassword1!',
            'role' => 'salon_owner', 'salon_name' => 'Should Be Ignored',
        ]);

        $response->assertCreated()->assertJsonPath('data.user.role', 'customer');
        $this->assertSame(0, Tenant::count());
        $this->assertDatabaseHas('users', ['email' => 'still-customer@example.test', 'role' => UserRole::CUSTOMER->value]);
    }
}
