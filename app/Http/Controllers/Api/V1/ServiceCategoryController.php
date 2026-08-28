<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BusinessStatus;
use App\Http\Requests\Service\ServiceCategoryRequest;
use App\Http\Resources\ServiceCategoryResource;
use App\Models\ServiceCategory;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class ServiceCategoryController extends TenantManagementController
{
    public function index(Request $request): JsonResponse
    {
        $this->managedTenant();
        $query = ServiceCategory::query();
        foreach (['branch_id' => 'branch_id', 'audience' => 'audience', 'status' => 'status'] as $input => $column) {
            if ($request->filled($input)) {
                $query->where($column, $request->string($input));
            }
        }

        return ApiResponse::success(ServiceCategoryResource::collection($query->orderBy('sort_order')->orderBy('name')->paginate(min($request->integer('per_page', 20), 100))), 'Service categories retrieved.');
    }

    public function store(ServiceCategoryRequest $request): JsonResponse
    {
        $this->managedTenant();
        $data = $request->validated();
        $data['slug'] ??= Str::slug($data['name']);
        $data['status'] ??= BusinessStatus::ACTIVE;
        $data['image'] = $request->hasFile('image') ? $request->file('image')->store('service-categories', 'public') : null;

        return ApiResponse::success(new ServiceCategoryResource(ServiceCategory::query()->create($data)), 'Service category created.', 201);
    }

    public function show(string $service_category): JsonResponse
    {
        $this->managedTenant();

        return ApiResponse::success(new ServiceCategoryResource($this->category($service_category)), 'Service category retrieved.');
    }

    public function update(ServiceCategoryRequest $request, string $service_category): JsonResponse
    {
        $this->managedTenant();
        $model = $this->category($service_category);
        $data = $request->validated();
        $data['slug'] ??= Str::slug($data['name']);
        $data['status'] ??= $model->status;
        if ($request->hasFile('image')) {
            $data['image'] = $request->file('image')->store('service-categories', 'public');
        } else {
            unset($data['image']);
        } $model->update($data);

        return ApiResponse::success(new ServiceCategoryResource($model->fresh()), 'Service category updated.');
    }

    public function destroy(string $service_category): JsonResponse
    {
        $this->managedTenant();
        $this->category($service_category)->delete();

        return ApiResponse::success(null, 'Service category deleted.');
    }

    private function category(string $id): ServiceCategory
    {
        return ServiceCategory::query()->findOrFail($id);
    }
}
