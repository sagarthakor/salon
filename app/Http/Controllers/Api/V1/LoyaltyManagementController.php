<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Requests\Pricing\LoyaltyAdjustmentRequest;
use App\Http\Resources\LoyaltyAccountResource;
use App\Http\Resources\LoyaltyTransactionResource;
use App\Models\Customer;
use App\Models\LoyaltyAccount;
use App\Services\Loyalty\LoyaltyService;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use RuntimeException;

/**
 * Owner/super-admin only. Loyalty *settings* are not here — they are part
 * of the existing `/salon/settings` endpoint (see `LoyaltySettings`); this
 * controller is only customer-specific balance search/adjustment. See
 * "Owner loyalty screen" in LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md.
 */
class LoyaltyManagementController extends TenantManagementController
{
    public function __construct(private readonly LoyaltyService $loyalty) {}

    public function index(Request $request): JsonResponse
    {
        $this->managedTenant();
        $query = LoyaltyAccount::query()->with('customer')->where('balance', '>', 0);
        if ($request->filled('search')) {
            $search = $request->string('search');
            $query->whereHas('customer', fn ($q) => $q->where('name', 'like', "%{$search}%")->orWhere('phone', 'like', "%{$search}%"));
        }
        $query->orderByDesc('balance');

        return ApiResponse::success(LoyaltyAccountResource::collection($query->paginate(min($request->integer('per_page', 20), 100))), 'Loyalty accounts retrieved.');
    }

    public function show(string $customer): JsonResponse
    {
        $tenant = $this->managedTenant();
        $customerModel = Customer::query()->findOrFail($customer);
        $account = $this->loyalty->accountFor($tenant, $customerModel);

        return ApiResponse::success(new LoyaltyAccountResource($account), 'Loyalty account retrieved.');
    }

    public function transactions(Request $request, string $customer): JsonResponse
    {
        $tenant = $this->managedTenant();
        $customerModel = Customer::query()->findOrFail($customer);
        $account = $this->loyalty->accountFor($tenant, $customerModel);
        $query = $account->transactions()->latest();

        return ApiResponse::success(LoyaltyTransactionResource::collection($query->paginate(min($request->integer('per_page', 20), 100))), 'Loyalty transactions retrieved.');
    }

    public function adjust(LoyaltyAdjustmentRequest $request, string $customer): JsonResponse
    {
        $tenant = $this->managedTenant();
        $customerModel = Customer::query()->findOrFail($customer);
        try {
            $transaction = $this->loyalty->adjust($tenant, $customerModel, $request->validated('points'), $request->validated('reason'), $request->user());
        } catch (RuntimeException $e) {
            return ApiResponse::error($e->getMessage(), [], 422);
        }

        return ApiResponse::success(new LoyaltyTransactionResource($transaction), 'Loyalty balance adjusted.', 201);
    }
}
