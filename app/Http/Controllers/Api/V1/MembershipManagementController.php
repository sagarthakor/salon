<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\CustomerMembershipStatus;
use App\Http\Requests\Pricing\MembershipGrantRequest;
use App\Http\Resources\CustomerMembershipResource;
use App\Models\Customer;
use App\Models\CustomerMembership;
use App\Models\MembershipPlan;
use App\Services\Membership\MembershipService;
use App\Support\ApiResponse;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Owner/super-admin only — viewing and granting a customer's membership.
 * See "Owner membership screen" in LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md.
 */
class MembershipManagementController extends TenantManagementController
{
    public function __construct(private readonly MembershipService $memberships) {}

    public function index(Request $request): JsonResponse
    {
        $this->managedTenant();
        $query = CustomerMembership::query()->with(['customer', 'membershipPlan']);
        if ($request->filled('status')) {
            $query->where('status', $request->string('status'));
        }
        if ($request->boolean('expiring_soon')) {
            $query->where('status', CustomerMembershipStatus::ACTIVE)
                ->whereBetween('expires_at', [CarbonImmutable::now(), CarbonImmutable::now()->addDays(7)]);
        }
        $query->latest('starts_at');

        return ApiResponse::success(CustomerMembershipResource::collection($query->paginate(min($request->integer('per_page', 20), 100))), 'Customer memberships retrieved.');
    }

    public function show(string $customerMembership): JsonResponse
    {
        $this->managedTenant();

        return ApiResponse::success(new CustomerMembershipResource($this->membership($customerMembership)->load(['customer', 'membershipPlan'])), 'Customer membership retrieved.');
    }

    /**
     * Owner-granted membership — no payment, fully auditable
     * (`source = owner_grant`). See "Membership purchase without payment".
     */
    public function grant(MembershipGrantRequest $request): JsonResponse
    {
        $tenant = $this->managedTenant();
        $customer = Customer::query()->findOrFail($request->validated('customer_id'));
        $plan = MembershipPlan::query()->findOrFail($request->validated('membership_plan_id'));
        $membership = $this->memberships->grant($tenant, $customer, $plan, $request->user());

        return ApiResponse::success(new CustomerMembershipResource($membership->load(['customer', 'membershipPlan'])), 'Membership granted.', 201);
    }

    public function cancel(string $customerMembership): JsonResponse
    {
        $this->managedTenant();
        $membership = $this->memberships->cancel($this->membership($customerMembership));

        return ApiResponse::success(new CustomerMembershipResource($membership->load(['customer', 'membershipPlan'])), 'Membership cancelled.');
    }

    private function membership(string $id): CustomerMembership
    {
        return CustomerMembership::query()->findOrFail($id);
    }
}
