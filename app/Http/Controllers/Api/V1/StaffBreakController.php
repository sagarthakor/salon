<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Requests\Staff\StaffBreakRequest;
use App\Http\Resources\StaffBreakResource;
use App\Models\Staff;
use App\Models\StaffBreak;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Gate;

class StaffBreakController extends TenantManagementController
{
    public function index(string $staff): JsonResponse
    {
        $model = $this->staff($staff);
        Gate::authorize('view', $model);

        return ApiResponse::success(StaffBreakResource::collection($model->breaks()->orderBy('day_of_week')->orderBy('start_time')->get()), 'Staff breaks retrieved.');
    }

    public function store(StaffBreakRequest $request, string $staff): JsonResponse
    {
        $this->managedTenant();
        $model = $this->staff($staff);

        return ApiResponse::success(new StaffBreakResource($model->breaks()->create($request->validated())), 'Staff break created.', 201);
    }

    public function update(StaffBreakRequest $request, string $staff, string $break): JsonResponse
    {
        $this->managedTenant();
        $model = $this->break($this->staff($staff), $break);
        $model->update($request->validated());

        return ApiResponse::success(new StaffBreakResource($model->fresh()), 'Staff break updated.');
    }

    public function destroy(string $staff, string $break): JsonResponse
    {
        $this->managedTenant();
        $this->break($this->staff($staff), $break)->delete();

        return ApiResponse::success(null, 'Staff break deleted.');
    }

    private function staff(string $id): Staff
    {
        return Staff::query()->findOrFail($id);
    }

    private function break(Staff $staff, string $id): StaffBreak
    {
        return $staff->breaks()->findOrFail($id);
    }
}
