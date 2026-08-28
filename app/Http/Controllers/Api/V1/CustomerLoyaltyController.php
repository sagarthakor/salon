<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\LoyaltyAccountResource;
use App\Http\Resources\LoyaltyTransactionResource;
use App\Models\Customer;
use App\Services\Loyalty\LoyaltyService;
use App\Support\ApiResponse;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * A customer viewing their own loyalty balance/history — same
 * X-Tenant-Slug resolution as CustomerProfileController/
 * CustomerMembershipController.
 */
class CustomerLoyaltyController extends Controller
{
    public function __construct(private readonly LoyaltyService $loyalty) {}

    public function account(Request $request): JsonResponse
    {
        $customer = $this->resolveCustomer($request);
        $context = app(TenantContext::class);
        $context->set($customer->tenant);
        try {
            $account = $this->loyalty->accountFor($customer->tenant, $customer);
        } finally {
            $context->clear();
        }

        return ApiResponse::success(new LoyaltyAccountResource($account), 'Loyalty account retrieved.');
    }

    public function transactions(Request $request): JsonResponse
    {
        $customer = $this->resolveCustomer($request);
        $context = app(TenantContext::class);
        $context->set($customer->tenant);
        try {
            $account = $this->loyalty->accountFor($customer->tenant, $customer);
            $query = $account->transactions()->latest();
            $result = LoyaltyTransactionResource::collection($query->paginate(min($request->integer('per_page', 20), 100)));
        } finally {
            $context->clear();
        }

        return ApiResponse::success($result, 'Loyalty transactions retrieved.');
    }

    private function resolveCustomer(Request $request): Customer
    {
        $userId = $request->user()->id;
        $slug = $request->header('X-Tenant-Slug');
        $query = Customer::withoutGlobalScope('tenant')->where('user_id', $userId);
        if ($slug) {
            $profile = $query->whereHas('tenant', fn ($q) => $q->where('slug', $slug))->first();
            abort_if($profile === null, 404, 'No customer profile found for this tenant.');

            return $profile;
        }
        $profiles = $query->get();
        abort_if($profiles->isEmpty(), 404, 'No customer profile found.');
        abort_if($profiles->count() > 1, 422, 'Multiple customer profiles found. Specify X-Tenant-Slug to select one.');

        return $profiles->first();
    }
}
