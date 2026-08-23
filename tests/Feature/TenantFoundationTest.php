<?php

namespace Tests\Feature;

use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Http\Middleware\ResolveTenantContext;
use App\Models\Concerns\BelongsToTenant;
use App\Models\Tenant;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class TenantFoundationTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Schema::create('tenant_scope_test_records', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->constrained('tenants');
            $table->string('name');
        });
        Route::middleware(['auth:sanctum', ResolveTenantContext::class])->get('/api/v1/_tenant-context-test', fn () => response()->json(['tenant_id' => app(TenantContext::class)->id()]));
    }

    public function test_users_can_belong_to_tenants_with_a_tenant_role(): void
    {
        $tenant = Tenant::query()->create(['name' => 'Salon A', 'slug' => 'salon-a']);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);

        $this->assertTrue($owner->tenants()->whereKey($tenant->id)->exists());
        $this->assertTrue($owner->can('manage', $tenant));
    }

    public function test_authenticated_user_cannot_select_another_tenants_context(): void
    {
        $tenantA = Tenant::query()->create(['name' => 'Salon A', 'slug' => 'salon-a']);
        $tenantB = Tenant::query()->create(['name' => 'Salon B', 'slug' => 'salon-b']);
        $ownerA = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenantA->users()->attach($ownerA, ['role' => TenantMembershipRole::SALON_OWNER->value]);

        $this->actingAs($ownerA, 'sanctum')->getJson('/api/v1/_tenant-context-test')->assertOk()->assertJsonPath('tenant_id', $tenantA->id);
        $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantB->slug)->getJson('/api/v1/_tenant-context-test')->assertForbidden()->assertJsonPath('success', false);
        $this->assertNull(app(TenantContext::class)->get());
    }

    public function test_tenant_owned_models_are_automatically_scoped_to_the_current_context(): void
    {
        $tenantA = Tenant::query()->create(['name' => 'Salon A', 'slug' => 'salon-a']);
        $tenantB = Tenant::query()->create(['name' => 'Salon B', 'slug' => 'salon-b']);
        app(TenantContext::class)->set($tenantA);
        TenantScopeTestRecord::query()->create(['name' => 'A only']);
        app(TenantContext::class)->set($tenantB);
        TenantScopeTestRecord::query()->create(['name' => 'B only']);
        app(TenantContext::class)->set($tenantA);

        $this->assertSame(['A only'], TenantScopeTestRecord::query()->pluck('name')->all());
        $this->assertSame($tenantA->id, TenantScopeTestRecord::query()->firstOrFail()->tenant_id);

        app(TenantContext::class)->clear();
        $this->assertSame([], TenantScopeTestRecord::query()->pluck('name')->all());
    }
}

class TenantScopeTestRecord extends Model
{
    use BelongsToTenant;

    protected $table = 'tenant_scope_test_records';

    public $timestamps = false;

    protected $guarded = [];
}
