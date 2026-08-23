<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\Tenant;
use App\Models\User;

class TenantPolicy
{
    public function view(User $user, Tenant $tenant): bool
    {
        return $user->role === UserRole::SUPER_ADMIN || $user->tenants()->whereKey($tenant->getKey())->exists();
    }

    public function manage(User $user, Tenant $tenant): bool
    {
        return $user->role === UserRole::SUPER_ADMIN || $user->tenants()->whereKey($tenant->getKey())->wherePivot('role', 'salon_owner')->exists();
    }
}
