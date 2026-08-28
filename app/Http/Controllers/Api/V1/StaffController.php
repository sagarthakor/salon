<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BusinessStatus;
use App\Http\Requests\Staff\StaffRequest;
use App\Http\Resources\StaffResource;
use App\Models\Staff;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;

class StaffController extends TenantManagementController
{
    /**
     * Resolves the authenticated user's OWN staff profile within the current
     * tenant — never a client-supplied staff id (see OWNER_APP_ARCHITECTURE.md
     * / STAFF_APP_ARCHITECTURE.md on why "me" endpoints exist: the Flutter
     * staff app has no other way to discover its own staff id safely). Mirrors
     * `CustomerProfileController::show`'s self-resolution-by-`user_id` pattern.
     */
    public function me(Request $request): JsonResponse
    {
        $this->viewableTenant();
        $staff = Staff::query()->with('branches')->where('user_id', $request->user()->id)->first();
        if ($staff === null) {
            return ApiResponse::error('No staff profile is linked to your account.', [], 404);
        }

        return ApiResponse::success(new StaffResource($staff), 'Staff profile retrieved.');
    }

    public function index(Request $request): JsonResponse
    {
        $this->managedTenant();
        $query = Staff::query()->with('branches');
        if ($request->filled('status')) {
            $query->where('status', $request->string('status'));
        }
        if ($request->filled('branch_id')) {
            $branchId = $request->string('branch_id');
            $query->whereHas('branches', fn ($q) => $q->where('branches.id', $branchId));
        }
        $sorts = ['name', 'joining_date', 'newest'];
        $sort = $request->input('sort', 'name');
        if (! in_array($sort, $sorts, true)) {
            return ApiResponse::error('Invalid sort field.', ['sort' => ['The selected sort field is invalid.']], 422);
        }
        $sort === 'newest' ? $query->latest() : $query->orderBy($sort)->orderBy('id');

        return ApiResponse::success(StaffResource::collection($query->paginate(min($request->integer('per_page', 20), 100))), 'Staff retrieved.');
    }

    public function store(StaffRequest $request): JsonResponse
    {
        $this->managedTenant();
        $data = $request->validated();
        $branchIds = $data['branch_ids'] ?? [];
        unset($data['branch_ids']);
        $data['status'] ??= BusinessStatus::ACTIVE;
        $data['photo'] = $request->hasFile('photo') ? $request->file('photo')->store('staff', 'public') : null;
        $staff = DB::transaction(function () use ($data, $branchIds): Staff {
            $staff = Staff::query()->create($data);
            $this->syncBranches($staff, $branchIds);

            return $staff;
        });

        return ApiResponse::success(new StaffResource($staff->load('branches')), 'Staff member created.', 201);
    }

    public function show(string $staff): JsonResponse
    {
        $model = $this->staff($staff);
        Gate::authorize('view', $model);

        return ApiResponse::success(new StaffResource($model->load('branches')), 'Staff member retrieved.');
    }

    public function update(StaffRequest $request, string $staff): JsonResponse
    {
        $this->managedTenant();
        $model = $this->staff($staff);
        $data = $request->validated();
        $branchIds = $data['branch_ids'] ?? null;
        unset($data['branch_ids']);
        $data['status'] ??= $model->status;
        if ($request->hasFile('photo')) {
            $data['photo'] = $request->file('photo')->store('staff', 'public');
        } else {
            unset($data['photo']);
        }
        DB::transaction(function () use ($model, $data, $branchIds): void {
            $model->update($data);
            if ($branchIds !== null) {
                $this->syncBranches($model, $branchIds);
            }
        });

        return ApiResponse::success(new StaffResource($model->fresh()->load('branches')), 'Staff member updated.');
    }

    public function destroy(string $staff): JsonResponse
    {
        $this->managedTenant();
        $this->staff($staff)->delete();

        return ApiResponse::success(null, 'Staff member deleted.');
    }

    private function staff(string $id): Staff
    {
        return Staff::query()->findOrFail($id);
    }

    /**
     * @param  array<int, string>  $branchIds
     */
    private function syncBranches(Staff $staff, array $branchIds): void
    {
        $staff->branches()->sync(collect($branchIds)->mapWithKeys(fn (string $branchId) => [$branchId => ['tenant_id' => $staff->tenant_id]])->all());
    }
}
