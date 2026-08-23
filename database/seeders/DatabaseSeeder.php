<?php

namespace Database\Seeders;

use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Tenant;
use App\Models\User;
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
        User::query()->firstOrCreate(['email' => 'admin@example.test'], ['name' => 'Local Super Admin', 'password' => 'ChangeMe123!', 'role' => UserRole::SUPER_ADMIN]);
        $owner = User::query()->firstOrCreate(['email' => 'owner@example.test'], ['name' => 'Demo Salon Owner', 'password' => 'ChangeMe123!', 'role' => UserRole::SALON_OWNER]);
        $tenant = Tenant::query()->firstOrCreate(['slug' => 'demo-salon'], ['name' => 'Demo Salon', 'status' => 'active']);
        $tenant->users()->syncWithoutDetaching([$owner->id => ['role' => TenantMembershipRole::SALON_OWNER->value]]);
    }
}
