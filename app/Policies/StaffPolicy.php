<?php

namespace App\Policies;

use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Staff;
use App\Models\User;

class StaffPolicy
{
    public function view(User $user, Staff $staff): bool
    {
        if ($user->role === UserRole::SUPER_ADMIN) {
            return true;
        }
        if ($user->tenants()->whereKey($staff->tenant_id)->wherePivot('role', TenantMembershipRole::SALON_OWNER->value)->exists()) {
            return true;
        }

        return $staff->user_id !== null && $staff->user_id === $user->id;
    }
}
