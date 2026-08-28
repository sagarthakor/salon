<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Booking\AvailabilityRequest;
use App\Models\Branch;
use App\Models\Service;
use App\Models\Staff;
use App\Services\Booking\AvailabilityService;
use App\Support\ApiResponse;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;

class AvailabilityController extends Controller
{
    public function __construct(private readonly AvailabilityService $availability) {}

    public function index(AvailabilityRequest $request, string $branch): JsonResponse
    {
        $branchModel = Branch::withoutGlobalScope('tenant')->findOrFail($branch);
        $context = app(TenantContext::class);
        $context->set($branchModel->tenant);
        try {
            $services = Service::query()->whereIn('id', $request->input('service_ids'))->get();
            $staff = $request->filled('staff_id') ? Staff::query()->find($request->input('staff_id')) : null;
            $date = CarbonImmutable::createFromFormat('Y-m-d', $request->string('date')->toString(), $branchModel->timezone ?: 'UTC')->startOfDay();
            $result = $this->availability->forBranch($branchModel, $date, $services, $staff);

            $staffIds = collect($result['slots'])->pluck('staff_ids')->flatten()->unique()->values();
            $result['staff'] = Staff::query()->whereIn('id', $staffIds)->orderBy('name')->get(['id', 'name'])
                ->map(fn (Staff $s) => ['id' => $s->id, 'name' => $s->name])->values();
        } finally {
            $context->clear();
        }

        return ApiResponse::success($result, 'Availability retrieved.');
    }
}
