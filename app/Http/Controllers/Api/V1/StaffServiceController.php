<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Requests\Staff\StaffServiceRequest;
use App\Http\Resources\ServiceResource;
use App\Models\Staff;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Gate;

class StaffServiceController extends TenantManagementController
{
    public function index(string $staff): JsonResponse
    {
        $model = $this->staff($staff);
        Gate::authorize('view', $model);

        return ApiResponse::success(ServiceResource::collection($model->services()->with('category')->get()), 'Staff services retrieved.');
    }

    public function update(StaffServiceRequest $request, string $staff): JsonResponse
    {
        $this->managedTenant();
        $model = $this->staff($staff);
        $serviceIds = $request->validated('service_ids');
        $model->services()->sync(collect($serviceIds)->mapWithKeys(fn (string $serviceId) => [$serviceId => ['tenant_id' => $model->tenant_id]])->all());

        return ApiResponse::success(ServiceResource::collection($model->services()->with('category')->get()), 'Staff services updated.');
    }

    private function staff(string $id): Staff
    {
        return Staff::query()->findOrFail($id);
    }
}
