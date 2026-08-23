<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BusinessStatus;
use App\Http\Requests\Salon\SalonRequest;
use App\Http\Requests\Salon\SalonSettingsRequest;
use App\Http\Resources\SalonResource;
use App\Http\Resources\SalonSettingsResource;
use App\Models\Salon;
use App\Models\SalonSetting;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class SalonController extends TenantManagementController
{
    public function show(): JsonResponse
    {
        $this->managedTenant();

        return ApiResponse::success(new SalonResource(Salon::query()->firstOrFail()), 'Salon retrieved.');
    }

    public function store(SalonRequest $request): JsonResponse
    {
        $tenant = $this->managedTenant();
        if ($tenant->salon()->exists()) {
            return ApiResponse::error('A salon profile already exists for this tenant.', [], 409);
        }
        $data = $request->validated();
        $data['slug'] ??= Str::slug($data['name']);
        $data['status'] ??= BusinessStatus::ACTIVE;

        return ApiResponse::success(new SalonResource(Salon::query()->create($data)), 'Salon created.', 201);
    }

    public function update(SalonRequest $request): JsonResponse
    {
        $this->managedTenant();
        $salon = Salon::query()->firstOrFail();
        $data = $request->validated();
        $data['slug'] ??= Str::slug($data['name']);
        $data['status'] ??= $salon->status;
        $salon->update($data);

        return ApiResponse::success(new SalonResource($salon->fresh()), 'Salon updated.');
    }

    public function settings(): JsonResponse
    {
        $this->managedTenant();
        $salon = Salon::query()->firstOrFail();

        return ApiResponse::success(new SalonSettingsResource($salon->settings()->get()), 'Salon settings retrieved.');
    }

    public function updateSettings(SalonSettingsRequest $request): JsonResponse
    {
        $this->managedTenant();
        $salon = Salon::query()->firstOrFail();
        DB::transaction(function () use ($request, $salon): void {
            foreach ($request->validated('settings') as $key => $value) {
                SalonSetting::query()->updateOrCreate(['salon_id' => $salon->id, 'key' => $key], ['value' => $value]);
            }
        });

        return ApiResponse::success(new SalonSettingsResource($salon->settings()->get()), 'Salon settings updated.');
    }
}
