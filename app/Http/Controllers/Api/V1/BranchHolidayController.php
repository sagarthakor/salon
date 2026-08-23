<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Requests\Salon\BranchHolidayRequest;
use App\Http\Resources\BranchHolidayResource;
use App\Models\Branch;
use App\Models\BranchHoliday;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;

class BranchHolidayController extends TenantManagementController
{
    public function index(string $branch): JsonResponse
    {
        $this->managedTenant();

        return ApiResponse::success(BranchHolidayResource::collection($this->branch($branch)->holidays()->orderBy('holiday_date')->get()), 'Branch holidays retrieved.');
    }

    public function store(BranchHolidayRequest $request, string $branch): JsonResponse
    {
        $this->managedTenant();
        $branch = $this->branch($branch);
        $data = $request->validated();
        $data['is_closed'] ??= true;

        return ApiResponse::success(new BranchHolidayResource($branch->holidays()->create($data)), 'Branch holiday created.', 201);
    }

    public function update(BranchHolidayRequest $request, string $branch, string $holiday): JsonResponse
    {
        $this->managedTenant();
        $model = $this->holiday($this->branch($branch), $holiday);
        $model->update($request->validated());

        return ApiResponse::success(new BranchHolidayResource($model->fresh()), 'Branch holiday updated.');
    }

    public function destroy(string $branch, string $holiday): JsonResponse
    {
        $this->managedTenant();
        $this->holiday($this->branch($branch), $holiday)->delete();

        return ApiResponse::success(null, 'Branch holiday deleted.');
    }

    private function branch(string $id): Branch
    {
        return Branch::query()->findOrFail($id);
    }

    private function holiday(Branch $branch, string $id): BranchHoliday
    {
        return $branch->holidays()->findOrFail($id);
    }
}
