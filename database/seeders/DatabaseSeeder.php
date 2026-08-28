<?php

namespace Database\Seeders;

use App\Enums\StaffGender;
use App\Enums\SubscriptionStatus;
use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Plan;
use App\Models\Staff;
use App\Models\Subscription;
use App\Models\Tenant;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    /**
     * Seed the application's database.
     */
    public function run(): void
    {
        $this->call(MasterCatalogSeeder::class);

        User::query()->firstOrCreate(['email' => 'admin@example.test'], ['name' => 'Local Super Admin', 'password' => 'ChangeMe123!', 'role' => UserRole::SUPER_ADMIN]);
        $owner = User::query()->firstOrCreate(['email' => 'owner@example.test'], ['name' => 'Demo Salon Owner', 'password' => 'ChangeMe123!', 'role' => UserRole::SALON_OWNER]);
        $tenant = Tenant::query()->firstOrCreate(['slug' => 'demo-salon'], ['name' => 'Demo Salon', 'status' => 'active']);
        $tenant->users()->syncWithoutDetaching([$owner->id => ['role' => TenantMembershipRole::SALON_OWNER->value]]);

        // Phase 9 demo staff login — a real `staff`-role platform user, given the
        // same tenant membership a live-created staff account would have, and
        // linked to an existing (or newly created) staff_profiles row so
        // `GET /staff/me` resolves it exactly like production would.
        $staffUser = User::query()->firstOrCreate(['email' => 'staff@example.test'], ['name' => 'Demo Staff Member', 'password' => 'ChangeMe123!', 'role' => UserRole::STAFF]);
        $tenant->users()->syncWithoutDetaching([$staffUser->id => ['role' => TenantMembershipRole::STAFF->value]]);

        // Model events (including the `BelongsToTenant` `creating` hook that
        // would normally auto-fill `tenant_id`) are suppressed for this whole
        // method by `WithoutModelEvents` above, so `tenant_id` is set
        // explicitly on every create below rather than relying on it.
        app(TenantContext::class)->set($tenant);
        try {
            $staffProfile = Staff::query()->where('user_id', $staffUser->id)->first();
            if ($staffProfile === null) {
                $staffProfile = Staff::query()->whereNull('user_id')->first();
                if ($staffProfile !== null) {
                    $staffProfile->update(['user_id' => $staffUser->id]);
                } else {
                    $staffProfile = Staff::query()->create([
                        'tenant_id' => $tenant->id,
                        'user_id' => $staffUser->id,
                        'name' => 'Demo Staff Member',
                        'gender' => StaffGender::MALE,
                        'status' => 'active',
                    ]);
                }
            }
            if ($staffProfile->workingHours()->count() === 0) {
                foreach (range(1, 6) as $dayOfWeek) {
                    $staffProfile->workingHours()->create([
                        'tenant_id' => $tenant->id,
                        'day_of_week' => $dayOfWeek,
                        'is_working' => true,
                        'start_time' => '09:00',
                        'end_time' => '19:00',
                    ]);
                }
                $staffProfile->workingHours()->create([
                    'tenant_id' => $tenant->id,
                    'day_of_week' => 0,
                    'is_working' => false,
                    'start_time' => null,
                    'end_time' => null,
                ]);
            }

            // Phase 10 — the demo tenant predates the billing migration, so
            // `Tenant::booted()`'s auto-trial hook never fired for it (and
            // wouldn't have anyway, since WithoutModelEvents suppresses it
            // here same as the staff-profile creation above). Backfilled as
            // an already-ACTIVE subscription (not just a trial) so the demo
            // owner login shows a realistic paid-plan state.
            if (Subscription::query()->where('tenant_id', $tenant->id)->doesntExist()) {
                $plan = Plan::query()->where('code', 'SALON_BASIC')->first();
                if ($plan !== null) {
                    $now = now();
                    Subscription::query()->create([
                        'tenant_id' => $tenant->id,
                        'plan_id' => $plan->id,
                        'status' => SubscriptionStatus::ACTIVE,
                        'starts_at' => $now,
                        'current_period_start' => $now,
                        'current_period_end' => $now->copy()->addMonth(),
                        'gateway' => 'razorpay',
                    ]);
                }
            }
        } finally {
            app(TenantContext::class)->clear();
        }
    }
}
