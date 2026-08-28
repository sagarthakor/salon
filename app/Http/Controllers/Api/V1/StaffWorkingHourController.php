<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Requests\Staff\StaffWorkingHoursRequest;
use App\Http\Resources\StaffWorkingHourResource;
use App\Models\Staff;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;

class StaffWorkingHourController extends TenantManagementController
{
    public function index(string $staff): JsonResponse
    {
        $model = $this->staff($staff);
        Gate::authorize('view', $model);

        return ApiResponse::success(StaffWorkingHourResource::collection($model->workingHours()->orderBy('day_of_week')->get()), 'Working hours retrieved.');
    }

    public function update(StaffWorkingHoursRequest $request, string $staff): JsonResponse
    {
        $this->managedTenant();
        $model = $this->staff($staff);
        DB::transaction(function () use ($model, $request): void {
            $model->workingHours()->delete();
            $model->workingHours()->createMany($request->validated('hours'));
        });

        return ApiResponse::success(StaffWorkingHourResource::collection($model->workingHours()->orderBy('day_of_week')->get()), 'Working hours updated.');
    }

    private function staff(string $id): Staff
    {
        return Staff::query()->findOrFail($id);
    }
}
