<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Billing\PlanRequest;
use App\Http\Resources\PlanResource;
use App\Models\Plan;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Gate;

/**
 * `index()` (active plans only) is reachable by any tenant member — it's
 * what the owner app's plan-selection screen calls. Every other action is
 * platform administration (`manage-platform` gate, super_admin only — the
 * existing gate from `AppServiceProvider`) and lives under `/platform/plans`
 * rather than the tenant-scoped `/subscription/*` group, since it isn't
 * tenant-scoped at all. No Platform Admin Flutter app was built this phase
 * (out of scope) — these are backend-only management APIs.
 */
class PlanController extends Controller
{
    public function index(): JsonResponse
    {
        $plans = Plan::query()->where('is_active', true)->orderBy('amount')->get();

        return ApiResponse::success(PlanResource::collection($plans), 'Plans retrieved.');
    }

    public function indexAll(): JsonResponse
    {
        Gate::authorize('manage-platform');
        $plans = Plan::query()->orderBy('created_at')->get();

        return ApiResponse::success(PlanResource::collection($plans), 'Plans retrieved.');
    }

    public function store(PlanRequest $request): JsonResponse
    {
        Gate::authorize('manage-platform');
        $data = $request->validated();
        $data['is_active'] ??= true;
        $plan = Plan::query()->create($data);

        return ApiResponse::success(new PlanResource($plan), 'Plan created.', 201);
    }

    public function update(PlanRequest $request, string $plan): JsonResponse
    {
        Gate::authorize('manage-platform');
        $model = Plan::query()->findOrFail($plan);
        $data = $request->validated();
        $data['is_active'] ??= $model->is_active;
        $model->update($data);

        return ApiResponse::success(new PlanResource($model->fresh()), 'Plan updated.');
    }

    public function activate(string $plan): JsonResponse
    {
        Gate::authorize('manage-platform');
        $model = Plan::query()->findOrFail($plan);
        $model->update(['is_active' => true]);

        return ApiResponse::success(new PlanResource($model), 'Plan activated.');
    }

    public function deactivate(string $plan): JsonResponse
    {
        Gate::authorize('manage-platform');
        $model = Plan::query()->findOrFail($plan);
        $model->update(['is_active' => false]);

        return ApiResponse::success(new PlanResource($model), 'Plan deactivated.');
    }
}
