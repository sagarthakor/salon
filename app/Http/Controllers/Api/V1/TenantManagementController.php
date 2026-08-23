<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Tenant;
use App\Support\TenantContext;
use Illuminate\Support\Facades\Gate;

abstract class TenantManagementController extends Controller
{
    protected function managedTenant(): Tenant
    {
        $tenant = app(TenantContext::class)->require();
        Gate::authorize('manage', $tenant);

        return $tenant;
    }
}
