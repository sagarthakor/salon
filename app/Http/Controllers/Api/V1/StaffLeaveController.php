<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\LeaveStatus;
use App\Http\Requests\Staff\StaffLeaveRequest;
use App\Http\Resources\StaffLeaveResource;
use App\Models\Staff;
use App\Models\StaffLeave;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Gate;

class StaffLeaveController extends TenantManagementController
{
    public function index(string $staff): JsonResponse
    {
        $model = $this->staff($staff);
        Gate::authorize('view', $model);

        return ApiResponse::success(StaffLeaveResource::collection($model->leaves()->orderBy('start_date')->get()), 'Staff leave retrieved.');
    }

    public function store(StaffLeaveRequest $request, string $staff): JsonResponse
    {
        $this->managedTenant();
        $model = $this->staff($staff);
        $data = $request->validated();
        $data['status'] ??= LeaveStatus::APPROVED;

        return ApiResponse::success(new StaffLeaveResource($model->leaves()->create($data)), 'Staff leave created.', 201);
    }

    public function update(StaffLeaveRequest $request, string $staff, string $leave): JsonResponse
    {
        $this->managedTenant();
        $model = $this->leave($this->staff($staff), $leave);
        $data = $request->validated();
        $data['status'] ??= $model->status;
        $model->update($data);

        return ApiResponse::success(new StaffLeaveResource($model->fresh()), 'Staff leave updated.');
    }

    public function destroy(string $staff, string $leave): JsonResponse
    {
        $this->managedTenant();
        $this->leave($this->staff($staff), $leave)->delete();

        return ApiResponse::success(null, 'Staff leave deleted.');
    }

    private function staff(string $id): Staff
    {
        return Staff::query()->findOrFail($id);
    }

    private function leave(Staff $staff, string $id): StaffLeave
    {
        return $staff->leaves()->findOrFail($id);
    }
}
