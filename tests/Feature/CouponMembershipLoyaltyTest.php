<?php

namespace Tests\Feature;

use App\Enums\BusinessStatus;
use App\Enums\CustomerMembershipStatus;
use App\Enums\GenderType;
use App\Enums\LoyaltyTransactionType;
use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Booking;
use App\Models\Branch;
use App\Models\BranchWorkingHour;
use App\Models\Coupon;
use App\Models\CouponUsage;
use App\Models\Customer;
use App\Models\CustomerMembership;
use App\Models\LoyaltyAccount;
use App\Models\LoyaltyTransaction;
use App\Models\MembershipPlan;
use App\Models\Salon;
use App\Models\SalonSetting;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\Staff;
use App\Models\StaffWorkingHour;
use App\Models\Tenant;
use App\Models\User;
use App\Services\Billing\Gateways\FakePaymentGateway;
use App\Services\Billing\Gateways\PaymentGatewayInterface;
use App\Services\Loyalty\LoyaltyService;
use App\Services\Membership\MembershipService;
use App\Services\Pricing\CouponService;
use App\Support\TenantContext;
use Carbon\Carbon;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CouponMembershipLoyaltyTest extends TestCase
{
    use RefreshDatabase;

    // --- Coupon CRUD + authorization ---

    public function test_owner_can_manage_coupons_but_staff_and_customer_cannot(): void
    {
        $f = $this->fixture('a');
        $owner = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        $coupon = $owner->postJson('/api/v1/coupons', $this->couponPayload())->assertCreated()
            ->assertJsonPath('data.code', 'WELCOME10')->json('data');

        $owner->patchJson("/api/v1/coupons/{$coupon['id']}", $this->couponPayload(['name' => 'Renamed']))
            ->assertOk()->assertJsonPath('data.name', 'Renamed');
        $owner->postJson("/api/v1/coupons/{$coupon['id']}/deactivate")->assertOk()->assertJsonPath('data.is_active', false);
        $owner->postJson("/api/v1/coupons/{$coupon['id']}/activate")->assertOk()->assertJsonPath('data.is_active', true);

        $staffUser = User::factory()->create(['role' => UserRole::STAFF]);
        $this->actingAs($staffUser, 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug)
            ->postJson('/api/v1/coupons', $this->couponPayload(['code' => 'STAFFCODE']))->assertForbidden();

        $customerUser = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $this->actingAs($customerUser, 'sanctum')
            ->postJson('/api/v1/coupons', $this->couponPayload(['code' => 'CUSTCODE']))->assertForbidden();
    }

    public function test_coupon_code_is_normalized_and_unique_per_tenant_case_insensitively(): void
    {
        $f = $this->fixture('a');
        $owner = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        $owner->postJson('/api/v1/coupons', $this->couponPayload(['code' => 'welcome10']))->assertCreated()
            ->assertJsonPath('data.code', 'WELCOME10');
        $owner->postJson('/api/v1/coupons', $this->couponPayload(['code' => 'Welcome10']))
            ->assertUnprocessable()->assertJsonValidationErrors('code');
    }

    // --- Coupon validation rules ---

    public function test_percentage_coupon_is_capped_by_maximum_discount_and_minimum_amount_is_enforced(): void
    {
        $f = $this->fixture('a');
        $this->createCoupon($f['tenant'], [
            'code' => 'BIG50', 'discount_type' => 'percentage', 'discount_value' => 50,
            'maximum_discount_amount' => 100, 'minimum_booking_amount' => 250,
        ]);

        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $booking = $api->postJson('/api/v1/bookings', $this->bookingPayload($f, couponCode: 'BIG50'))
            ->assertCreated()->json('data');
        // 50% of 300 = 150, capped at 100.
        $this->assertSame('100.00', $booking['coupon_discount']);
        $this->assertSame('200.00', $booking['total']);
    }

    public function test_coupon_below_minimum_booking_amount_is_rejected(): void
    {
        $f = $this->fixture('a');
        $this->createCoupon($f['tenant'], ['code' => 'NEEDS1000', 'discount_type' => 'fixed_amount', 'discount_value' => 50, 'minimum_booking_amount' => 1000]);

        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $api->postJson('/api/v1/bookings', $this->bookingPayload($f, couponCode: 'NEEDS1000'))->assertStatus(409);
    }

    public function test_expired_inactive_and_unknown_coupon_codes_are_all_rejected(): void
    {
        $f = $this->fixture('a');
        $this->createCoupon($f['tenant'], ['code' => 'EXPIRED', 'expires_at' => Carbon::yesterday()]);
        $this->createCoupon($f['tenant'], ['code' => 'INACTIVE', 'is_active' => false]);

        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $api->postJson('/api/v1/bookings', $this->bookingPayload($f, couponCode: 'EXPIRED'))->assertStatus(409);
        $api->postJson('/api/v1/bookings', $this->bookingPayload($f, couponCode: 'INACTIVE'))->assertStatus(409);
        $api->postJson('/api/v1/bookings', $this->bookingPayload($f, couponCode: 'DOES-NOT-EXIST'))->assertStatus(409);
    }

    public function test_coupon_restricted_to_a_service_does_not_apply_to_a_different_service(): void
    {
        $f = $this->fixture('a');
        $coupon = $this->createCoupon($f['tenant'], ['code' => 'HAIRONLY', 'discount_type' => 'fixed_amount', 'discount_value' => 50]);
        app(TenantContext::class)->set($f['tenant']);
        $coupon->services()->sync([$f['haircut']->id => ['tenant_id' => $f['tenant']->id]]);
        app(TenantContext::class)->clear();

        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        // Facial-only booking: the coupon does not qualify at all.
        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $this->bookingDate(), 'start_time' => '09:00',
            'items' => [['service_id' => $f['facial']->id, 'staff_id' => $f['staff']->id]],
            'coupon_code' => 'HAIRONLY',
        ])->assertStatus(409);

        // Haircut booking: qualifies.
        $booking = $api->postJson('/api/v1/bookings', $this->bookingPayload($f, couponCode: 'HAIRONLY'))->assertCreated()->json('data');
        $this->assertSame('50.00', $booking['coupon_discount']);
    }

    public function test_usage_limit_and_per_customer_limit_are_enforced(): void
    {
        $f = $this->fixture('a');
        $this->createCoupon($f['tenant'], ['code' => 'ONEUSE', 'discount_type' => 'fixed_amount', 'discount_value' => 10, 'usage_limit' => 1]);

        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $api->postJson('/api/v1/bookings', $this->bookingPayload($f, couponCode: 'ONEUSE', startTime: '09:00'))->assertCreated();
        // A second booking (even for a different customer) exhausts the limit.
        $api->postJson('/api/v1/bookings', $this->bookingPayload($f, couponCode: 'ONEUSE', startTime: '11:00'))->assertStatus(409);

        $this->createCoupon($f['tenant'], ['code' => 'PERCUST', 'discount_type' => 'fixed_amount', 'discount_value' => 10, 'usage_limit_per_customer' => 1]);
        $api->postJson('/api/v1/bookings', $this->bookingPayload($f, couponCode: 'PERCUST', startTime: '13:00'))->assertCreated();
        $api->postJson('/api/v1/bookings', $this->bookingPayload($f, couponCode: 'PERCUST', startTime: '15:00'))->assertStatus(409);
    }

    public function test_first_booking_only_coupon_is_rejected_once_the_customer_has_a_prior_booking(): void
    {
        $f = $this->fixture('a');
        $this->createCoupon($f['tenant'], ['code' => 'FIRSTONLY', 'discount_type' => 'fixed_amount', 'discount_value' => 10, 'first_booking_only' => true]);

        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        // First-ever booking for this customer: coupon applies.
        $api->postJson('/api/v1/bookings', $this->bookingPayload($f, couponCode: 'FIRSTONLY', startTime: '09:00'))->assertCreated();
        // Second booking: no longer their first booking.
        $api->postJson('/api/v1/bookings', $this->bookingPayload($f, startTime: '11:00'))->assertCreated();
        $api->postJson('/api/v1/bookings', $this->bookingPayload($f, couponCode: 'FIRSTONLY', startTime: '13:00'))->assertStatus(409);
    }

    public function test_an_invalid_coupon_at_creation_time_leaves_no_orphaned_booking_or_usage_record(): void
    {
        $f = $this->fixture('a');
        $this->createCoupon($f['tenant'], ['code' => 'GONE', 'is_active' => false]);
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        $before = Booking::withoutGlobalScope('tenant')->count();
        $api->postJson('/api/v1/bookings', $this->bookingPayload($f, couponCode: 'GONE'))->assertStatus(409);
        $after = Booking::withoutGlobalScope('tenant')->count();

        $this->assertSame($before, $after);
        $this->assertSame(0, CouponUsage::withoutGlobalScope('tenant')->count());
    }

    public function test_coupon_usage_limit_is_race_safe_the_second_reservation_attempt_against_an_exhausted_coupon_fails(): void
    {
        // PHPUnit cannot exercise genuine parallel HTTP requests (same
        // documented limitation as BOOKING_ENGINE.md's concurrency test) —
        // this instead proves the *mechanism* two real concurrent requests
        // would hit: reserve() re-validates and increments under a row lock,
        // so a second reservation against an already-exhausted coupon is
        // rejected exactly like a genuine loser of the race would be.
        $f = $this->fixture('a');
        $coupon = $this->createCoupon($f['tenant'], ['code' => 'RACE', 'discount_type' => 'fixed_amount', 'discount_value' => 10, 'usage_limit' => 1]);

        app(TenantContext::class)->set($f['tenant']);
        $couponService = app(CouponService::class);
        $services = collect([(object) ['id' => $f['haircut']->id, 'price' => 300.0, 'category_id' => $f['haircut']->category_id]]);
        $booking = Booking::query()->create(['branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'booking_date' => now()->addDay()->toDateString(), 'start_time' => '09:00', 'end_time' => '09:30', 'status' => 'pending', 'subtotal' => 300, 'total' => 300]);

        $first = $couponService->reserve($f['tenant'], $coupon->id, $f['customer'], $services, 300, $booking);
        $second = $couponService->reserve($f['tenant'], $coupon->id, $f['customer'], $services, 300, $booking);
        app(TenantContext::class)->clear();

        $this->assertTrue($first->valid);
        $this->assertFalse($second->valid);
        $this->assertSame(1, $coupon->fresh()->usage_count);
    }

    // --- Membership ---

    public function test_owner_can_manage_membership_plans_and_grant_a_membership(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        $plan = $api->postJson('/api/v1/membership-plans', $this->planPayload())->assertCreated()->json('data');

        $granted = $api->postJson('/api/v1/memberships/grant', ['customer_id' => $f['customer']->id, 'membership_plan_id' => $plan['id']])
            ->assertCreated()->json('data');
        $this->assertSame('active', $granted['status']);
        $this->assertSame('owner_grant', $granted['source']);
        $this->assertSame('0.00', $granted['purchased_amount']);

        $this->assertDatabaseHas('customer_memberships', ['id' => $granted['id'], 'status' => 'active']);
    }

    public function test_membership_benefit_applies_automatically_and_a_coupon_takes_priority_over_it(): void
    {
        $f = $this->fixture('a');
        $plan = MembershipPlan::withoutGlobalScope('tenant')->find(
            $this->createPlan($f['tenant'], ['discount_type' => 'percentage', 'discount_value' => 20])->id
        );
        app(TenantContext::class)->set($f['tenant']);
        app(MembershipService::class)->grant($f['tenant'], $f['customer'], $plan, $f['owner']);
        app(TenantContext::class)->clear();

        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        // No coupon: membership benefit applies automatically (20% of 300 = 60).
        $booking = $api->postJson('/api/v1/bookings', $this->bookingPayload($f, startTime: '09:00'))->assertCreated()->json('data');
        $this->assertSame('60.00', $booking['membership_discount']);
        $this->assertSame('0.00', $booking['coupon_discount']);
        $this->assertSame('240.00', $booking['total']);

        // A valid coupon takes priority — membership benefit is NOT also applied.
        $this->createCoupon($f['tenant'], ['code' => 'STACK', 'discount_type' => 'fixed_amount', 'discount_value' => 30]);
        $booking2 = $api->postJson('/api/v1/bookings', $this->bookingPayload($f, couponCode: 'STACK', startTime: '11:00'))->assertCreated()->json('data');
        $this->assertSame('30.00', $booking2['coupon_discount']);
        $this->assertSame('0.00', $booking2['membership_discount']);
        $this->assertSame('270.00', $booking2['total']);
    }

    public function test_an_expired_membership_grants_no_benefit_even_before_the_scheduler_runs(): void
    {
        $f = $this->fixture('a');
        $plan = $this->createPlan($f['tenant'], ['discount_type' => 'percentage', 'discount_value' => 20]);
        app(TenantContext::class)->set($f['tenant']);
        CustomerMembership::query()->create([
            'tenant_id' => $f['tenant']->id, 'customer_id' => $f['customer']->id, 'membership_plan_id' => $plan->id,
            'status' => CustomerMembershipStatus::ACTIVE, 'starts_at' => now()->subDays(40), 'expires_at' => now()->subDay(),
            'purchased_amount' => 999, 'currency' => 'INR', 'source' => 'owner_grant',
        ]);
        app(TenantContext::class)->clear();

        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $booking = $api->postJson('/api/v1/bookings', $this->bookingPayload($f))->assertCreated()->json('data');
        $this->assertSame('0.00', $booking['membership_discount']);
    }

    public function test_membership_purchase_via_checkout_and_verify_activates_it_and_a_renewal_supersedes_the_old_one(): void
    {
        $f = $this->fixture('a');
        $plan = $this->createPlan($f['tenant'], ['discount_type' => 'fixed_amount', 'discount_value' => 20]);
        $gateway = new FakePaymentGateway;
        $this->app->bind(PaymentGatewayInterface::class, fn () => $gateway);

        $customerApi = $this->actingAs($f['customerUser'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $checkout = $customerApi->postJson('/api/v1/customer/membership/checkout', ['membership_plan_id' => $plan->id])->assertCreated()->json('data');
        $gateway->validSignatures['sig-1'] = true;
        $customerApi->postJson('/api/v1/customer/membership/checkout/verify', [
            'payment_id' => $checkout['payment_id'], 'gateway_payment_id' => 'pay_1', 'gateway_signature' => 'sig-1',
        ])->assertOk()->assertJsonPath('data.status', 'active');

        $current = $customerApi->getJson('/api/v1/customer/membership')->assertOk()->json('data');
        $firstMembershipId = $current['id'];
        $this->assertSame('active', $current['status']);

        // Renewal: purchasing again supersedes the first membership.
        $checkout2 = $customerApi->postJson('/api/v1/customer/membership/checkout', ['membership_plan_id' => $plan->id])->assertCreated()->json('data');
        $gateway->validSignatures['sig-2'] = true;
        $customerApi->postJson('/api/v1/customer/membership/checkout/verify', [
            'payment_id' => $checkout2['payment_id'], 'gateway_payment_id' => 'pay_2', 'gateway_signature' => 'sig-2',
        ])->assertOk();

        $this->assertDatabaseHas('customer_memberships', ['id' => $firstMembershipId, 'status' => 'cancelled']);
        $renewed = $customerApi->getJson('/api/v1/customer/membership')->assertOk()->json('data');
        $this->assertNotSame($firstMembershipId, $renewed['id']);
        $this->assertSame('active', $renewed['status']);
    }

    public function test_the_shared_razorpay_webhook_also_activates_a_membership_purchase_and_deduplicates_delivery(): void
    {
        $f = $this->fixture('a');
        $plan = $this->createPlan($f['tenant'], ['discount_type' => 'fixed_amount', 'discount_value' => 20]);
        $gateway = new FakePaymentGateway;
        $this->app->bind(PaymentGatewayInterface::class, fn () => $gateway);

        $customerApi = $this->actingAs($f['customerUser'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $checkout = $customerApi->postJson('/api/v1/customer/membership/checkout', ['membership_plan_id' => $plan->id])->assertCreated()->json('data');

        $signature = 'webhook-valid';
        $gateway->validSignatures[$signature] = true;
        $payload = [
            'event' => 'payment.captured',
            'payload' => ['payment' => ['entity' => ['id' => 'pay_webhook_1', 'order_id' => $checkout['gateway_order_id']]]],
        ];
        $headers = ['X-Razorpay-Signature' => $signature, 'X-Razorpay-Event-Id' => 'evt_membership_1'];

        $this->postJson('/api/v1/webhooks/razorpay', $payload, $headers)->assertOk();
        $this->assertDatabaseHas('membership_payments', ['id' => $checkout['payment_id'], 'status' => 'paid']);
        $this->assertSame('active', $customerApi->getJson('/api/v1/customer/membership')->assertOk()->json('data.status'));

        // Duplicate delivery — must not double-activate/create a second membership.
        $this->postJson('/api/v1/webhooks/razorpay', $payload, $headers)->assertOk();
        $this->assertSame(1, CustomerMembership::withoutGlobalScope('tenant')->where('customer_id', $f['customer']->id)->count());
    }

    public function test_membership_expiry_scheduler_marks_it_expired_and_it_stops_granting_benefit(): void
    {
        $f = $this->fixture('a');
        $plan = $this->createPlan($f['tenant'], ['discount_type' => 'percentage', 'discount_value' => 20]);
        app(TenantContext::class)->set($f['tenant']);
        $membership = CustomerMembership::query()->create([
            'tenant_id' => $f['tenant']->id, 'customer_id' => $f['customer']->id, 'membership_plan_id' => $plan->id,
            'status' => CustomerMembershipStatus::ACTIVE, 'starts_at' => now()->subDays(10), 'expires_at' => now()->subDay(),
            'purchased_amount' => 999, 'currency' => 'INR', 'source' => 'owner_grant',
        ]);
        app(TenantContext::class)->clear();

        app(MembershipService::class)->expireDueMemberships();

        $this->assertSame('expired', $membership->fresh()->status->value);
    }

    // --- Loyalty ---

    public function test_loyalty_points_are_earned_only_on_completion_never_on_creation_or_cancellation(): void
    {
        $f = $this->fixture('a');
        $this->enableLoyalty($f['tenant'], ['loyalty_earn_rate_amount' => 100, 'loyalty_redemption_value' => 1, 'loyalty_max_redemption_percent' => 50]);

        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $booking = $api->postJson('/api/v1/bookings', $this->bookingPayload($f, startTime: '09:00'))->assertCreated()->json('data');
        $this->assertSame(0, LoyaltyTransaction::withoutGlobalScope('tenant')->where('type', LoyaltyTransactionType::EARN->value)->count());

        $cancelled = $api->postJson('/api/v1/bookings', $this->bookingPayload($f, startTime: '11:00'))->assertCreated()->json('data');
        $api->postJson("/api/v1/bookings/{$cancelled['id']}/cancel", ['reason' => 'test'])->assertOk();
        $this->assertSame(0, LoyaltyTransaction::withoutGlobalScope('tenant')->where('type', LoyaltyTransactionType::EARN->value)->count());

        $api->postJson("/api/v1/bookings/{$booking['id']}/confirm")->assertOk();
        $api->patchJson("/api/v1/bookings/{$booking['id']}", ['status' => 'checked_in'])->assertOk();
        $api->patchJson("/api/v1/bookings/{$booking['id']}", ['status' => 'in_service'])->assertOk();
        $api->patchJson("/api/v1/bookings/{$booking['id']}", ['status' => 'completed'])->assertOk();

        // 300 spent at 100/point = 3 points.
        $this->assertSame(1, LoyaltyTransaction::withoutGlobalScope('tenant')->where('type', LoyaltyTransactionType::EARN->value)->count());
        $account = LoyaltyAccount::withoutGlobalScope('tenant')->where('customer_id', $f['customer']->id)->first();
        $this->assertSame(3, $account->balance);
    }

    public function test_loyalty_earning_is_idempotent_for_the_same_booking(): void
    {
        $f = $this->fixture('a');
        $this->enableLoyalty($f['tenant'], ['loyalty_earn_rate_amount' => 100]);
        app(TenantContext::class)->set($f['tenant']);
        $booking = Booking::query()->create(['branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'booking_date' => now()->addDay()->toDateString(), 'start_time' => '09:00', 'end_time' => '09:30', 'status' => 'completed', 'subtotal' => 300, 'total' => 300]);

        $service = app(LoyaltyService::class);
        $first = $service->earnForBooking($booking->fresh(['branch.salon', 'customer']));
        $second = $service->earnForBooking($booking->fresh(['branch.salon', 'customer']));
        app(TenantContext::class)->clear();

        $this->assertNotNull($first);
        $this->assertNull($second);
        $this->assertSame(1, LoyaltyTransaction::withoutGlobalScope('tenant')->where('booking_id', $booking->id)->where('type', 'earn')->count());
    }

    public function test_loyalty_redemption_never_exceeds_balance_or_the_configured_max_percent_and_never_goes_negative(): void
    {
        $f = $this->fixture('a');
        $this->enableLoyalty($f['tenant'], ['loyalty_redemption_value' => 1, 'loyalty_max_redemption_percent' => 20]);
        app(TenantContext::class)->set($f['tenant']);
        $account = app(LoyaltyService::class)->accountFor($f['tenant'], $f['customer']);
        $account->update(['balance' => 500]);
        app(TenantContext::class)->clear();

        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        // Requests 500 points against a 300 subtotal capped at 20% => max 60 points allowed.
        $booking = $api->postJson('/api/v1/bookings', $this->bookingPayload($f, loyaltyPoints: 500))->assertCreated()->json('data');
        $this->assertSame(60, $booking['loyalty_points_redeemed']);
        $this->assertSame('60.00', $booking['loyalty_discount']);
        $this->assertSame('240.00', $booking['total']);

        $account = $account->fresh();
        $this->assertSame(440, $account->balance);
        $this->assertGreaterThanOrEqual(0, $account->balance);
    }

    public function test_owner_can_search_a_customers_loyalty_balance_and_make_an_auditable_adjustment(): void
    {
        $f = $this->fixture('a');
        app(TenantContext::class)->set($f['tenant']);
        app(LoyaltyService::class)->accountFor($f['tenant'], $f['customer'])->update(['balance' => 100]);
        app(TenantContext::class)->clear();

        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $api->getJson("/api/v1/loyalty/customers/{$f['customer']->id}")->assertOk()->assertJsonPath('data.balance', 100);

        $adjustment = $api->postJson("/api/v1/loyalty/customers/{$f['customer']->id}/adjust", ['points' => -30, 'reason' => 'Goodwill correction'])
            ->assertCreated()->json('data');
        $this->assertSame(-30, $adjustment['points']);
        $this->assertSame(70, $adjustment['balance_after']);

        $api->postJson("/api/v1/loyalty/customers/{$f['customer']->id}/adjust", ['points' => -1000, 'reason' => 'too much'])
            ->assertUnprocessable();

        $transactions = $api->getJson("/api/v1/loyalty/customers/{$f['customer']->id}/transactions")->assertOk()->json('data');
        $this->assertSame('adjustment', $transactions[0]['type']);
    }

    public function test_staff_and_customer_cannot_manage_membership_plans_or_adjust_loyalty(): void
    {
        $f = $this->fixture('a');
        $staffUser = User::factory()->create(['role' => UserRole::STAFF]);
        $staffApi = $this->actingAs($staffUser, 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        $staffApi->postJson('/api/v1/membership-plans', $this->planPayload())->assertForbidden();
        $staffApi->postJson("/api/v1/loyalty/customers/{$f['customer']->id}/adjust", ['points' => 10, 'reason' => 'x'])->assertForbidden();
    }

    // --- Tenant isolation ---

    public function test_tenant_a_cannot_access_tenant_bs_coupons_memberships_or_loyalty_by_direct_id(): void
    {
        $a = $this->fixture('a');
        $b = $this->fixture('b');
        $couponB = $this->createCoupon($b['tenant'], ['code' => 'BONLY']);
        $planB = $this->createPlan($b['tenant']);
        app(TenantContext::class)->set($b['tenant']);
        $membershipB = app(MembershipService::class)->grant($b['tenant'], $b['customer'], $planB, $b['owner']);
        app(TenantContext::class)->clear();

        $apiA = $this->actingAs($a['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $a['tenant']->slug);
        $apiA->getJson("/api/v1/coupons/{$couponB->id}")->assertNotFound();
        $apiA->getJson("/api/v1/membership-plans/{$planB->id}")->assertNotFound();
        $apiA->getJson("/api/v1/memberships/{$membershipB->id}")->assertNotFound();
        $apiA->getJson("/api/v1/loyalty/customers/{$b['customer']->id}")->assertNotFound();
    }

    // --- Data integrity ---

    /**
     * Regression test for Phase 14: `customer_memberships.customer_id`,
     * `loyalty_accounts.customer_id`, and `loyalty_transactions.customer_id`
     * (plus `loyalty_transactions.loyalty_account_id`) were created with
     * `cascadeOnDelete()`, inconsistent with every sibling financial/
     * historical table in the same migration (`coupon_usages.customer_id`,
     * `membership_payments.customer_id` both use `restrictOnDelete()`). The
     * app itself only ever soft-deletes a Customer, so this never fired
     * through any API path — but a future hard-delete (an admin cleanup
     * script, a GDPR-erasure feature) would have silently destroyed a
     * customer's entire loyalty ledger and membership history. Fixed to
     * `restrictOnDelete()` — see SECURITY_HARDENING.md.
     */
    public function test_hard_deleting_a_customer_with_loyalty_or_membership_history_is_blocked_not_cascaded(): void
    {
        $f = $this->fixture('a');
        $this->enableLoyalty($f['tenant'], ['loyalty_earn_rate_amount' => 100, 'loyalty_redemption_value' => 1, 'loyalty_max_redemption_percent' => 50]);
        $plan = MembershipPlan::withoutGlobalScope('tenant')->find($this->createPlan($f['tenant'])->id);
        app(TenantContext::class)->set($f['tenant']);
        app(MembershipService::class)->grant($f['tenant'], $f['customer'], $plan, $f['owner']);
        app(TenantContext::class)->clear();

        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $booking = $api->postJson('/api/v1/bookings', $this->bookingPayload($f))->assertCreated()->json('data');
        $api->postJson("/api/v1/bookings/{$booking['id']}/confirm")->assertOk();
        $api->patchJson("/api/v1/bookings/{$booking['id']}", ['status' => 'checked_in'])->assertOk();
        $api->patchJson("/api/v1/bookings/{$booking['id']}", ['status' => 'in_service'])->assertOk();
        $api->patchJson("/api/v1/bookings/{$booking['id']}", ['status' => 'completed'])->assertOk();

        $this->assertDatabaseHas('customer_memberships', ['customer_id' => $f['customer']->id]);
        $this->assertDatabaseHas('loyalty_accounts', ['customer_id' => $f['customer']->id]);
        $this->assertDatabaseHas('loyalty_transactions', ['customer_id' => $f['customer']->id]);

        $this->expectException(QueryException::class);
        $f['customer']->forceDelete();
    }

    // --- helpers ---

    private function couponPayload(array $overrides = []): array
    {
        return array_merge([
            'code' => 'WELCOME10', 'name' => 'Welcome discount', 'discount_type' => 'percentage', 'discount_value' => 10,
        ], $overrides);
    }

    private function planPayload(array $overrides = []): array
    {
        return array_merge([
            'name' => 'Gold', 'code' => 'GOLD', 'price' => 999, 'duration_days' => 30,
            'discount_type' => 'percentage', 'discount_value' => 15,
        ], $overrides);
    }

    private function createCoupon(Tenant $tenant, array $overrides = []): Coupon
    {
        $context = app(TenantContext::class);
        $context->set($tenant);
        $coupon = Coupon::query()->create(array_merge([
            'code' => Coupon::normalizeCode($overrides['code'] ?? 'TESTCODE'),
            'name' => 'Test coupon', 'discount_type' => 'percentage', 'discount_value' => 10, 'is_active' => true,
        ], $overrides));
        $context->clear();

        return $coupon;
    }

    private function createPlan(Tenant $tenant, array $overrides = []): MembershipPlan
    {
        $context = app(TenantContext::class);
        $context->set($tenant);
        $plan = MembershipPlan::query()->create(array_merge([
            'name' => 'Gold', 'code' => 'GOLD-'.uniqid(), 'price' => 999, 'currency' => 'INR', 'duration_days' => 30,
            'discount_type' => 'percentage', 'discount_value' => 15, 'is_active' => true,
        ], $overrides));
        $context->clear();

        return $plan;
    }

    private function enableLoyalty(Tenant $tenant, array $overrides = []): void
    {
        $context = app(TenantContext::class);
        $context->set($tenant);
        $salon = Salon::query()->first();
        $settings = array_merge([
            'loyalty_enabled' => true, 'loyalty_earn_rate_amount' => 100, 'loyalty_redemption_value' => 1,
            'loyalty_max_redemption_percent' => 50, 'loyalty_min_booking_amount_for_earning' => 0,
        ], $overrides);
        foreach ($settings as $key => $value) {
            SalonSetting::query()->updateOrCreate(['salon_id' => $salon->id, 'key' => $key], ['value' => $value]);
        }
        $context->clear();
    }

    private function bookingPayload(array $f, ?string $couponCode = null, ?int $loyaltyPoints = null, string $startTime = '09:00'): array
    {
        return [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $this->bookingDate(), 'start_time' => $startTime,
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['staff']->id]],
            'coupon_code' => $couponCode,
            'loyalty_points_to_redeem' => $loyaltyPoints,
        ];
    }

    private function bookingDate(): string
    {
        return Carbon::today()->addDay()->toDateString();
    }

    /**
     * @return array{tenant: Tenant, owner: User, branch: Branch, haircut: Service, facial: Service, staff: Staff, customer: Customer, customerUser: User}
     */
    private function fixture(string $slug): array
    {
        $tenant = Tenant::query()->create(['name' => $slug, 'slug' => $slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);
        app(TenantContext::class)->set($tenant);

        $salon = Salon::query()->create(['name' => $slug, 'slug' => $slug, 'gender_type' => GenderType::UNISEX, 'status' => BusinessStatus::ACTIVE, 'timezone' => 'UTC']);
        $branch = Branch::query()->create(['salon_id' => $salon->id, 'name' => 'Main', 'slug' => 'main-'.$slug, 'status' => BusinessStatus::ACTIVE, 'timezone' => 'UTC']);
        foreach (range(0, 6) as $day) {
            BranchWorkingHour::query()->create(['branch_id' => $branch->id, 'day_of_week' => $day, 'is_open' => true, 'opening_time' => '09:00', 'closing_time' => '20:00']);
        }

        $category = ServiceCategory::query()->create(['branch_id' => $branch->id, 'name' => 'Hair', 'slug' => 'hair-'.$slug, 'status' => BusinessStatus::ACTIVE]);
        $haircut = Service::query()->create(['branch_id' => $branch->id, 'category_id' => $category->id, 'name' => 'Haircut', 'slug' => 'haircut-'.$slug, 'gender' => GenderType::UNISEX, 'price' => '300.00', 'duration_minutes' => 30, 'status' => BusinessStatus::ACTIVE]);
        $facial = Service::query()->create(['branch_id' => $branch->id, 'category_id' => $category->id, 'name' => 'Facial', 'slug' => 'facial-'.$slug, 'gender' => GenderType::UNISEX, 'price' => '500.00', 'duration_minutes' => 45, 'status' => BusinessStatus::ACTIVE]);

        $staff = Staff::query()->create(['name' => 'Amit', 'gender' => 'male', 'status' => BusinessStatus::ACTIVE]);
        $staff->branches()->sync([$branch->id => ['tenant_id' => $tenant->id]]);
        $staff->services()->sync([$haircut->id => ['tenant_id' => $tenant->id], $facial->id => ['tenant_id' => $tenant->id]]);
        foreach (range(0, 6) as $day) {
            StaffWorkingHour::query()->create(['staff_id' => $staff->id, 'day_of_week' => $day, 'is_working' => true, 'start_time' => '09:00', 'end_time' => '20:00']);
        }

        $customerUser = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $customer = Customer::query()->create(['user_id' => $customerUser->id, 'name' => 'Rahul', 'phone' => '90000000'.($slug === 'a' ? '01' : '02'), 'normalized_phone' => '90000000'.($slug === 'a' ? '01' : '02'), 'status' => BusinessStatus::ACTIVE]);

        app(TenantContext::class)->clear();

        return compact('tenant', 'owner', 'branch', 'haircut', 'facial', 'staff', 'customer', 'customerUser');
    }
}
