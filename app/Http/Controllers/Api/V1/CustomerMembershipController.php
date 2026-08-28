<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\PaymentStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Pricing\MembershipCheckoutRequest;
use App\Http\Requests\Pricing\MembershipVerifyRequest;
use App\Http\Resources\CustomerMembershipResource;
use App\Http\Resources\MembershipPlanResource;
use App\Models\Branch;
use App\Models\Customer;
use App\Models\MembershipPayment;
use App\Models\MembershipPlan;
use App\Services\Membership\MembershipService;
use App\Support\ApiResponse;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Customer-facing membership purchase/status — mirrors
 * `CustomerBookingController`'s X-Tenant-Slug resolution (a customer may
 * hold profiles, and therefore memberships, across several tenants) rather
 * than the `tenant.context` middleware the owner-side controllers use.
 */
class CustomerMembershipController extends Controller
{
    public function __construct(private readonly MembershipService $memberships) {}

    /** Public browse — mirrors `GET /branches/{branch}/services`. */
    public function plans(string $branch): JsonResponse
    {
        $branchModel = Branch::withoutGlobalScope('tenant')->findOrFail($branch);
        $plans = MembershipPlan::withoutGlobalScope('tenant')
            ->where('tenant_id', $branchModel->tenant_id)->where('is_active', true)->get();

        return ApiResponse::success(MembershipPlanResource::collection($plans), 'Membership plans retrieved.');
    }

    public function current(Request $request): JsonResponse
    {
        $customer = $this->resolveCustomer($request);
        $context = app(TenantContext::class);
        $context->set($customer->tenant);
        try {
            $membership = $this->memberships->activeMembershipFor($customer->tenant, $customer);
        } finally {
            $context->clear();
        }

        return ApiResponse::success($membership !== null ? new CustomerMembershipResource($membership->load('membershipPlan')) : null, 'Current membership retrieved.');
    }

    public function checkout(MembershipCheckoutRequest $request): JsonResponse
    {
        $customer = $this->resolveCustomer($request);
        $context = app(TenantContext::class);
        $context->set($customer->tenant);
        try {
            $plan = MembershipPlan::query()->where('is_active', true)->findOrFail($request->validated('membership_plan_id'));
            $payment = $this->memberships->initiateCheckout($customer->tenant, $customer, $plan, $request->header('Idempotency-Key'));
        } finally {
            $context->clear();
        }

        return ApiResponse::success([
            'payment_id' => $payment->id,
            'idempotency_key' => $payment->idempotency_key,
            'gateway' => $payment->gateway,
            'gateway_key' => config('services.razorpay.key'),
            'gateway_order_id' => $payment->gateway_order_id,
            'amount' => $payment->amount,
            'currency' => $payment->currency,
            'plan' => ['id' => $plan->id, 'name' => $plan->name, 'code' => $plan->code],
        ], 'Membership checkout order created.', 201);
    }

    public function verifyCheckout(MembershipVerifyRequest $request): JsonResponse
    {
        $customer = $this->resolveCustomer($request);
        $context = app(TenantContext::class);
        $context->set($customer->tenant);
        try {
            $payment = MembershipPayment::query()->where('customer_id', $customer->id)->findOrFail($request->validated('payment_id'));
            $payment = $this->memberships->verifyAndFinalize($payment, $request->validated('gateway_payment_id'), $request->validated('gateway_signature'));
            if ($payment->status !== PaymentStatus::PAID) {
                return ApiResponse::error('Membership payment could not be verified.', [], 402);
            }
            $membership = $payment->customerMembership()->with('membershipPlan')->first();
        } finally {
            $context->clear();
        }

        return ApiResponse::success(new CustomerMembershipResource($membership), 'Payment verified. Membership is now active.');
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
