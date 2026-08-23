<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Requests\Salon\WorkingHoursRequest;
use App\Http\Resources\BranchWorkingHourResource;
use App\Models\Branch;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

class BranchWorkingHourController extends TenantManagementController
{
    public function index(string $branch): JsonResponse
    {
        $this->managedTenant();

        return ApiResponse::success(BranchWorkingHourResource::collection($this->branch($branch)->workingHours()->orderBy('day_of_week')->get()), 'Working hours retrieved.');
    }

    public function update(WorkingHoursRequest $request, string $branch): JsonResponse
    {
        $this->managedTenant();
        $branch = $this->branch($branch);
        DB::transaction(function () use ($branch, $request): void {
            $branch->workingHours()->delete();
            $branch->workingHours()->createMany($request->validated('hours'));
        });

        return ApiResponse::success(BranchWorkingHourResource::collection($branch->workingHours()->orderBy('day_of_week')->get()), 'Working hours updated.');
    }

    private function branch(string $id): Branch
    {
        return Branch::query()->findOrFail($id);
    }
}
