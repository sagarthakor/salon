<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BusinessStatus;
use App\Http\Requests\Service\ServiceRequest;
use App\Http\Resources\ServiceResource;
use App\Models\Service;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
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
        $data['image'] = $request->hasFile('image') ? $this->storeImage($request->file('image')) : null;

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

        // A new upload always wins over `remove_image` — no ambiguity about
        // "replace with X" vs "remove" when both are somehow sent together.
        // Either way, the previous file (if any) is deleted, never left
        // orphaned in storage.
        if ($request->hasFile('image')) {
            $this->deleteImage($model->image);
            $data['image'] = $this->storeImage($request->file('image'));
        } elseif ($request->boolean('remove_image')) {
            $this->deleteImage($model->image);
            $data['image'] = null;
        } else {
            unset($data['image']);
        } $model->update($data);

        return ApiResponse::success(new ServiceResource($model->fresh()->load('category')), 'Service updated.');
    }

    public function destroy(string $service): JsonResponse
    {
        $this->managedTenant();
        // A regular delete() is a soft delete — the image is deliberately
        // kept (see Service::booted()'s forceDeleting hook for when it's
        // actually removed).
        $this->service($service)->delete();

        return ApiResponse::success(null, 'Service deleted.');
    }

    private function service(string $id): Service
    {
        return Service::query()->findOrFail($id);
    }

    private function storeImage(UploadedFile $file): string
    {
        return $file->store('services', 'public');
    }

    private function deleteImage(?string $path): void
    {
        if ($path !== null) {
            Storage::disk('public')->delete($path);
        }
    }
}
