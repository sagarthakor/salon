<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BusinessStatus;
use App\Http\Requests\Service\ServiceRequest;
use App\Http\Resources\ServiceResource;
use App\Models\Service;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class ServiceController extends TenantManagementController
{
    public function index(Request $request): JsonResponse
    {
        $this->managedTenant();
        $query = Service::query()->with('category');
        foreach (['branch_id' => 'branch_id', 'category_id' => 'category_id', 'gender' => 'gender', 'status' => 'status'] as $input => $column) {
            if ($request->filled($input)) {
                $query->where($column, $request->string($input));
            }
        } $sorts = ['sort_order', 'name', 'price', 'duration_minutes', 'newest'];
        $sort = $request->input('sort', 'sort_order');
        if (! in_array($sort, $sorts, true)) {
            return ApiResponse::error('Invalid sort field.', ['sort' => ['The selected sort field is invalid.']], 422);
        } $sort === 'newest' ? $query->latest() : $query->orderBy($sort)->orderBy('id');

        return ApiResponse::success(ServiceResource::collection($query->paginate(min($request->integer('per_page', 20), 100))), 'Services retrieved.');
    }

    public function store(ServiceRequest $request): JsonResponse
    {
        $this->managedTenant();
        $data = $request->validated();
        $data['slug'] ??= Str::slug($data['name']);
        $data['status'] ??= BusinessStatus::ACTIVE;
        $data['image'] = $request->hasFile('image') ? $request->file('image')->store('services', 'public') : null;

        return ApiResponse::success(new ServiceResource(Service::query()->create($data)->load('category')), 'Service created.', 201);
    }

    public function show(string $service): JsonResponse
    {
        $this->managedTenant();

        return ApiResponse::success(new ServiceResource($this->service($service)->load('category')), 'Service retrieved.');
    }

    public function update(ServiceRequest $request, string $service): JsonResponse
    {
        $this->managedTenant();
        $model = $this->service($service);
        $data = $request->validated();
        $data['slug'] ??= Str::slug($data['name']);
        $data['status'] ??= $model->status;
        if ($request->hasFile('image')) {
            $data['image'] = $request->file('image')->store('services', 'public');
        } else {
            unset($data['image']);
        } $model->update($data);

        return ApiResponse::success(new ServiceResource($model->fresh()->load('category')), 'Service updated.');
    }

    public function destroy(string $service): JsonResponse
    {
        $this->managedTenant();
        $this->service($service)->delete();

        return ApiResponse::success(null, 'Service deleted.');
    }

    private function service(string $id): Service
    {
        return Service::query()->findOrFail($id);
    }
}
