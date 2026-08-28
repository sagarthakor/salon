<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BusinessStatus;
use App\Http\Requests\Salon\BranchRequest;
use App\Http\Resources\BranchResource;
use App\Models\Branch;
use App\Services\Catalog\CatalogProvisioningService;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Str;

class BranchController extends TenantManagementController
{
    public function index(): JsonResponse
    {
        $this->managedTenant();

        return ApiResponse::success(BranchResource::collection(Branch::query()->orderBy('name')->get()), 'Branches retrieved.');
    }

    public function store(BranchRequest $request, CatalogProvisioningService $provisioning): JsonResponse
    {
        $this->managedTenant();
        $data = $request->validated();
        // A brand-new self-registered owner may not have a Salon profile
        // yet — see requireSalon() on the base controller.
        $data['salon_id'] = $this->requireSalon('adding a branch')->id;
        $data['slug'] ??= Str::slug($data['name']);
        $data['status'] ??= BusinessStatus::ACTIVE;

        $branch = Branch::query()->create($data);
        // A no-op for every branch after a tenant's first — see
        // CatalogProvisioningService's own idempotency guard.
        $provisioning->provisionForBranch($branch);

        return ApiResponse::success(new BranchResource($branch), 'Branch created.', 201);
    }

    public function show(string $branch): JsonResponse
    {
        $this->managedTenant();

        return ApiResponse::success(new BranchResource($this->branch($branch)), 'Branch retrieved.');
    }

    public function update(BranchRequest $request, string $branch): JsonResponse
    {
        $this->managedTenant();
        $model = $this->branch($branch);
        $data = $request->validated();
        $data['slug'] ??= Str::slug($data['name']);
        $data['status'] ??= $model->status;
        $model->update($data);

        return ApiResponse::success(new BranchResource($model->fresh()), 'Branch updated.');
    }

    public function destroy(string $branch): JsonResponse
    {
        $this->managedTenant();
        $this->branch($branch)->delete();

        return ApiResponse::success(null, 'Branch deleted.');
    }

    private function branch(string $id): Branch
    {
        return Branch::query()->findOrFail($id);
    }
}
