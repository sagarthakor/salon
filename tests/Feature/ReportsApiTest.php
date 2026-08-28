<?php

namespace Tests\Feature;

use App\Enums\BusinessStatus;
use App\Enums\CustomerMembershipStatus;
use App\Enums\GenderType;
use App\Enums\LoyaltyTransactionType;
use App\Enums\PaymentStatus;
use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Booking;
use App\Models\BookingItem;
use App\Models\Branch;
use App\Models\BranchWorkingHour;
use App\Models\Coupon;
use App\Models\CouponUsage;
use App\Models\Customer;
use App\Models\CustomerMembership;
use App\Models\LoyaltyAccount;
use App\Models\LoyaltyTransaction;
use App\Models\MembershipPayment;
use App\Models\MembershipPlan;
use App\Models\Salon;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\Staff;
use App\Models\StaffWorkingHour;
use App\Models\Tenant;
use App\Models\User;
use App\Support\TenantContext;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class ReportsApiTest extends TestCase
{
    use RefreshDatabase;

    // --- Authorization / tenant isolation ---

    public function test_owner_can_access_reports_but_staff_and_customer_cannot(): void
    {
        $f = $this->fixture('a');
        $owner = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $owner->getJson('/api/v1/reports/dashboard')->assertOk();
        $owner->getJson('/api/v1/reports/revenue')->assertOk();
        $owner->getJson('/api/v1/reports/bookings')->assertOk();

        $staffUser = User::factory()->create(['role' => UserRole::STAFF]);
        $f['tenant']->users()->attach($staffUser, ['role' => TenantMembershipRole::STAFF->value]);
        $staffApi = $this->actingAs($staffUser, 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $staffApi->getJson('/api/v1/reports/dashboard')->assertForbidden();
        $staffApi->getJson('/api/v1/reports/staff')->assertForbidden();

        $customerUser = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $this->actingAs($customerUser, 'sanctum')->getJson('/api/v1/reports/revenue')->assertForbidden();
    }

    public function test_tenant_a_cannot_see_tenant_bs_report_data_or_use_its_ids_as_filters(): void
    {
        $a = $this->fixture('a');
        $b = $this->fixture('b');
        $this->createBooking($b, ['status' => 'completed', 'subtotal' => 900, 'total' => 900]);

        $apiA = $this->actingAs($a['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $a['tenant']->slug);
        $apiA->getJson('/api/v1/reports/revenue?range=this_month')->assertOk()
            ->assertJsonPath('data.summary.net_revenue', '0.00');

        // Tenant B's branch id used as a filter on tenant A's request must be rejected, not silently ignored.
        $apiA->getJson('/api/v1/reports/revenue?branch_id='.$b['branch']->id)->assertUnprocessable()
            ->assertJsonValidationErrors('branch_id');
        $apiA->getJson('/api/v1/reports/staff?staff_id='.$b['staff']->id)->assertUnprocessable()
            ->assertJsonValidationErrors('staff_id');
    }

    // --- Date range resolution ---

    public function test_date_range_presets_and_custom_range_are_resolved_and_invalid_ranges_rejected(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        $today = Carbon::now('UTC')->toDateString();
        $this->createBooking($f, ['status' => 'completed', 'booking_date' => $today, 'subtotal' => 500, 'total' => 500]);
        $this->createBooking($f, ['status' => 'completed', 'booking_date' => Carbon::yesterday('UTC')->toDateString(), 'subtotal' => 300, 'total' => 300]);

        $api->getJson('/api/v1/reports/revenue?range=today')->assertOk()->assertJsonPath('data.summary.net_revenue', '500.00');
        $api->getJson('/api/v1/reports/revenue?range=yesterday')->assertOk()->assertJsonPath('data.summary.net_revenue', '300.00');

        $api->getJson("/api/v1/reports/revenue?range=custom&from={$today}&to={$today}")->assertOk()
            ->assertJsonPath('data.summary.net_revenue', '500.00');
        $api->getJson('/api/v1/reports/revenue?range=custom&from=2026-02-01&to=2026-01-01')->assertUnprocessable();
        $api->getJson('/api/v1/reports/revenue?range=custom')->assertUnprocessable();
        $api->getJson('/api/v1/reports/revenue?range=not_a_range')->assertUnprocessable();
    }

    /**
     * The server instant below is 2026-08-27 20:00:00 UTC, which is already
     * 2026-08-28 01:30 in Asia/Kolkata (UTC+5:30) — the UTC calendar date and
     * the salon's local calendar date disagree. A "today" report must follow
     * the salon's timezone, not the server's, per instruction #4's exact
     * example (a 00:30 local-time booking must land on the correct local
     * business date). This also covers DashboardController::summary(),
     * which shares the same bug/fix (see its docblock).
     */
    public function test_today_range_resolves_against_salon_timezone_not_server_utc(): void
    {
        Carbon::setTestNow(Carbon::create(2026, 8, 27, 20, 0, 0, 'UTC'));

        try {
            $f = $this->fixture('a', 'Asia/Kolkata');
            $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

            // Booking_date is the branch-local wall-clock business date for a
            // booking at ~01:00 local time on the salon's "today" (2026-08-28
            // in Asia/Kolkata), not the server's UTC "today" (2026-08-27).
            $this->createBooking($f, ['status' => 'completed', 'booking_date' => '2026-08-28', 'subtotal' => 400, 'total' => 400]);

            $api->getJson('/api/v1/reports/revenue?range=today')->assertOk()
                ->assertJsonPath('data.summary.net_revenue', '400.00');

            $api->getJson('/api/v1/dashboard/summary')->assertOk()
                ->assertJsonPath('data.date', '2026-08-28')
                ->assertJsonPath('data.revenue_today', '400.00');
        } finally {
            Carbon::setTestNow();
        }
    }

    // --- Revenue report ---

    public function test_revenue_report_aggregates_completed_bookings_only_and_excludes_cancelled(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $today = Carbon::now('UTC')->toDateString();

        $this->createBooking($f, ['status' => 'completed', 'booking_date' => $today, 'subtotal' => 1000, 'discount' => 100, 'total' => 900]);
        $this->createBooking($f, ['status' => 'completed', 'booking_date' => $today, 'subtotal' => 500, 'discount' => 0, 'total' => 500]);
        $this->createBooking($f, ['status' => 'cancelled', 'booking_date' => $today, 'subtotal' => 2000, 'discount' => 0, 'total' => 2000]);

        $response = $api->getJson('/api/v1/reports/revenue?range=today')->assertOk();
        $response->assertJsonPath('data.summary.completed_bookings', 2)
            ->assertJsonPath('data.summary.gross_booking_value', '1500.00')
            ->assertJsonPath('data.summary.discount', '100.00')
            ->assertJsonPath('data.summary.net_revenue', '1400.00')
            ->assertJsonPath('data.summary.average_booking_value', '700.00');
    }

    public function test_revenue_by_staff_attributes_by_booking_item_without_double_counting(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $today = Carbon::now('UTC')->toDateString();

        $staff2 = $this->createStaff($f, 'Priya');

        // One booking with two items assigned to two different staff — total subtotal 800, discount 80.
        app(TenantContext::class)->set($f['tenant']);
        $booking = Booking::query()->create([
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'booking_date' => $today,
            'start_time' => '10:00:00', 'end_time' => '11:00:00', 'status' => 'completed',
            'subtotal' => 800, 'discount' => 80, 'tax' => 0, 'total' => 720,
        ]);
        BookingItem::query()->create([
            'booking_id' => $booking->id, 'service_id' => $f['haircut']->id, 'staff_id' => $f['staff']->id,
            'service_name' => 'Haircut', 'service_price' => 300, 'service_duration_minutes' => 30, 'quantity' => 1,
            'start_time' => '10:00:00', 'end_time' => '10:30:00', 'subtotal' => 300,
        ]);
        BookingItem::query()->create([
            'booking_id' => $booking->id, 'service_id' => $f['haircut']->id, 'staff_id' => $staff2->id,
            'service_name' => 'Facial', 'service_price' => 500, 'service_duration_minutes' => 30, 'quantity' => 1,
            'start_time' => '10:30:00', 'end_time' => '11:00:00', 'subtotal' => 500,
        ]);
        app(TenantContext::class)->clear();

        $data = $api->getJson('/api/v1/reports/revenue?range=today')->assertOk()->json('data');
        $byStaff = collect($data['breakdown']['by_staff'])->keyBy('staff_id');

        // 300/800 * 80 = 30 discount for staff 1; 500/800*80 = 50 for staff 2. Net: 270 + 450 = 720 = booking total.
        $this->assertSame('270.00', $byStaff[$f['staff']->id]['net_revenue']);
        $this->assertSame('450.00', $byStaff[$staff2->id]['net_revenue']);
        $totalNet = (float) $byStaff[$f['staff']->id]['net_revenue'] + (float) $byStaff[$staff2->id]['net_revenue'];
        $this->assertEqualsWithDelta(720.0, $totalNet, 0.001);
    }

    public function test_revenue_by_service_uses_historical_price_snapshot_not_current_price(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $today = Carbon::now('UTC')->toDateString();

        $this->createBooking($f, ['status' => 'completed', 'booking_date' => $today, 'subtotal' => 300, 'total' => 300, 'service_price' => 300]);

        app(TenantContext::class)->set($f['tenant']);
        $f['haircut']->update(['price' => 999]);
        app(TenantContext::class)->clear();

        $byService = collect($api->getJson('/api/v1/reports/revenue?range=today')->json('data.breakdown.by_service'))->keyBy('service_id');
        $this->assertSame('300.00', $byService[$f['haircut']->id]['gross_value']);
    }

    // --- Booking report ---

    public function test_booking_report_status_counts_and_rates(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $today = Carbon::now('UTC')->toDateString();

        $this->createBooking($f, ['status' => 'completed', 'booking_date' => $today]);
        $this->createBooking($f, ['status' => 'completed', 'booking_date' => $today]);
        $this->createBooking($f, ['status' => 'cancelled', 'booking_date' => $today, 'cancellation_reason' => 'Customer request']);
        $this->createBooking($f, ['status' => 'no_show', 'booking_date' => $today]);

        $summary = $api->getJson('/api/v1/reports/bookings?range=today')->assertOk()->json('data.summary');
        $this->assertSame(4, $summary['total']);
        $this->assertSame(2, $summary['completed']);
        $this->assertSame(1, $summary['cancelled']);
        $this->assertSame(1, $summary['no_show']);
        $this->assertEqualsWithDelta(0.25, $summary['cancellation_rate'], 0.0001);
        $this->assertEqualsWithDelta(0.25, $summary['no_show_rate'], 0.0001);
    }

    // --- Customer report ---

    public function test_customer_report_distinguishes_new_and_returning_customers(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $today = Carbon::now('UTC');

        // A returning customer: created well before this month, with a completed visit before the range.
        app(TenantContext::class)->set($f['tenant']);
        $returning = Customer::query()->create([
            'name' => 'Returning Rani', 'phone' => '9000000099', 'normalized_phone' => '9000000099', 'status' => BusinessStatus::ACTIVE,
            'created_at' => $today->clone()->subYear(),
        ]);
        app(TenantContext::class)->clear();
        $this->createBooking($f, ['status' => 'completed', 'booking_date' => $today->clone()->subYear()->addDay()->toDateString(), 'customer_id' => $returning->id]);
        $this->createBooking($f, ['status' => 'completed', 'booking_date' => $today->toDateString(), 'customer_id' => $returning->id]);

        // A brand-new customer created and booking within this month.
        app(TenantContext::class)->set($f['tenant']);
        $fresh = Customer::query()->create([
            'name' => 'New Naina', 'phone' => '9000000098', 'normalized_phone' => '9000000098', 'status' => BusinessStatus::ACTIVE,
        ]);
        app(TenantContext::class)->clear();
        $this->createBooking($f, ['status' => 'completed', 'booking_date' => $today->toDateString(), 'customer_id' => $fresh->id]);

        $summary = $api->getJson('/api/v1/reports/customers?range=this_month')->assertOk()->json('data.summary');
        $this->assertGreaterThanOrEqual(1, $summary['new_customers']);
        $this->assertGreaterThanOrEqual(1, $summary['returning_customers']);
    }

    // --- Staff report ---

    public function test_staff_report_excludes_staff_from_own_role_and_shows_completion_rate(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $today = Carbon::now('UTC')->toDateString();

        $this->createBooking($f, ['status' => 'completed', 'booking_date' => $today]);
        $this->createBooking($f, ['status' => 'cancelled', 'booking_date' => $today]);

        $data = $api->getJson('/api/v1/reports/staff?range=today')->assertOk()->json('data.data');
        $row = collect($data)->firstWhere('staff_id', $f['staff']->id);
        $this->assertSame(2, $row['assigned_bookings']);
        $this->assertSame(1, $row['completed_bookings']);
        $this->assertEqualsWithDelta(0.5, $row['completion_rate'], 0.0001);
    }

    // --- Branch report ---

    public function test_branch_report_includes_branches_with_zero_bookings(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        app(TenantContext::class)->set($f['tenant']);
        $secondBranch = Branch::query()->create(['salon_id' => $f['salon']->id, 'name' => 'Second', 'slug' => 'second-a', 'status' => BusinessStatus::ACTIVE, 'timezone' => 'UTC']);
        app(TenantContext::class)->clear();

        $this->createBooking($f, ['status' => 'completed', 'booking_date' => Carbon::now('UTC')->toDateString()]);

        $data = $api->getJson('/api/v1/reports/branches?range=this_month')->assertOk()->json('data.data');
        $this->assertCount(2, $data);
        $secondRow = collect($data)->firstWhere('branch_id', $secondBranch->id);
        $this->assertSame(0, $secondRow['bookings']);
    }

    // --- Coupon report ---

    public function test_coupon_report_reads_from_usage_ledger_not_current_config(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        app(TenantContext::class)->set($f['tenant']);
        $coupon = Coupon::query()->create([
            'code' => 'SAVE10', 'name' => 'Save 10', 'discount_type' => 'fixed_amount', 'discount_value' => 50,
            'usage_count' => 1, 'is_active' => true,
        ]);
        CouponUsage::query()->create([
            'coupon_id' => $coupon->id, 'customer_id' => $f['customer']->id, 'discount_amount' => 50, 'used_at' => now(),
        ]);
        app(TenantContext::class)->clear();
        $coupon->update(['discount_value' => 5000]); // later config change must not rewrite history

        $data = $api->getJson('/api/v1/reports/coupons?range=this_month')->assertOk()->json('data.data');
        $row = collect($data)->firstWhere('coupon_id', $coupon->id);
        $this->assertSame(1, $row['times_used']);
        $this->assertSame('50.00', $row['discount_given']);
    }

    // --- Membership report ---

    public function test_membership_report_counts_by_current_status_and_revenue_from_membership_payments(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        app(TenantContext::class)->set($f['tenant']);
        $plan = MembershipPlan::query()->create([
            'name' => 'Gold', 'code' => 'GOLD', 'price' => 999, 'currency' => 'INR', 'duration_days' => 365,
            'discount_type' => 'percentage', 'discount_value' => 10, 'is_active' => true,
        ]);
        $membership = CustomerMembership::query()->create([
            'customer_id' => $f['customer']->id, 'membership_plan_id' => $plan->id, 'status' => CustomerMembershipStatus::ACTIVE,
            'starts_at' => now(), 'expires_at' => now()->addYear(), 'purchased_amount' => 999, 'currency' => 'INR', 'source' => 'purchase',
        ]);
        MembershipPayment::query()->create([
            'customer_id' => $f['customer']->id, 'membership_plan_id' => $plan->id, 'customer_membership_id' => $membership->id,
            'amount' => 999, 'currency' => 'INR', 'status' => PaymentStatus::PAID, 'paid_at' => now(),
            'gateway' => 'fake', 'idempotency_key' => (string) Str::uuid(),
        ]);
        app(TenantContext::class)->clear();

        $summary = $api->getJson('/api/v1/reports/memberships?range=this_month')->assertOk()->json('data.summary');
        $this->assertSame(1, $summary['active_memberships']);
        $this->assertSame('999.00', $summary['membership_revenue']);
    }

    // --- Loyalty report ---

    public function test_loyalty_report_reads_ledger_for_earned_and_redeemed_points(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        app(TenantContext::class)->set($f['tenant']);
        $account = LoyaltyAccount::query()->create(['customer_id' => $f['customer']->id, 'balance' => 40, 'lifetime_earned' => 100, 'lifetime_redeemed' => 60]);
        LoyaltyTransaction::query()->create(['customer_id' => $f['customer']->id, 'loyalty_account_id' => $account->id, 'type' => LoyaltyTransactionType::EARN, 'points' => 100, 'balance_after' => 100]);
        LoyaltyTransaction::query()->create(['customer_id' => $f['customer']->id, 'loyalty_account_id' => $account->id, 'type' => LoyaltyTransactionType::REDEEM, 'points' => -60, 'balance_after' => 40]);
        app(TenantContext::class)->clear();

        $summary = $api->getJson('/api/v1/reports/loyalty?range=this_month')->assertOk()->json('data.summary');
        $this->assertSame(100, $summary['points_earned']);
        $this->assertSame(60, $summary['points_redeemed']);
        $this->assertSame(40, $summary['outstanding_points']);
    }

    // --- Fixtures ---

    private function fixture(string $slug, string $timezone = 'UTC'): array
    {
        $tenant = Tenant::query()->create(['name' => $slug, 'slug' => $slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);
        app(TenantContext::class)->set($tenant);

        $salon = Salon::query()->create(['name' => $slug, 'slug' => $slug, 'gender_type' => GenderType::UNISEX, 'status' => BusinessStatus::ACTIVE, 'timezone' => $timezone]);
        $branch = Branch::query()->create(['salon_id' => $salon->id, 'name' => 'Main', 'slug' => 'main-'.$slug, 'status' => BusinessStatus::ACTIVE, 'timezone' => $timezone]);
        foreach (range(0, 6) as $day) {
            BranchWorkingHour::query()->create(['branch_id' => $branch->id, 'day_of_week' => $day, 'is_open' => true, 'opening_time' => '09:00', 'closing_time' => '20:00']);
        }

        $category = ServiceCategory::query()->create(['branch_id' => $branch->id, 'name' => 'Hair', 'slug' => 'hair-'.$slug, 'status' => BusinessStatus::ACTIVE]);
        $haircut = Service::query()->create(['branch_id' => $branch->id, 'category_id' => $category->id, 'name' => 'Haircut', 'slug' => 'haircut-'.$slug, 'gender' => GenderType::UNISEX, 'price' => '300.00', 'duration_minutes' => 30, 'status' => BusinessStatus::ACTIVE]);

        $staff = Staff::query()->create(['name' => 'Amit', 'gender' => 'male', 'status' => BusinessStatus::ACTIVE]);
        $staff->branches()->sync([$branch->id => ['tenant_id' => $tenant->id]]);
        $staff->services()->sync([$haircut->id => ['tenant_id' => $tenant->id]]);
        foreach (range(0, 6) as $day) {
            StaffWorkingHour::query()->create(['staff_id' => $staff->id, 'day_of_week' => $day, 'is_working' => true, 'start_time' => '09:00', 'end_time' => '20:00']);
        }

        $customerUser = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $customer = Customer::query()->create(['user_id' => $customerUser->id, 'name' => 'Rahul', 'phone' => '90000000'.($slug === 'a' ? '01' : '02'), 'normalized_phone' => '90000000'.($slug === 'a' ? '01' : '02'), 'status' => BusinessStatus::ACTIVE]);

        app(TenantContext::class)->clear();

        return compact('tenant', 'owner', 'salon', 'branch', 'category', 'haircut', 'staff', 'customer', 'customerUser');
    }

    private function createStaff(array $f, string $name): Staff
    {
        app(TenantContext::class)->set($f['tenant']);
        $staff = Staff::query()->create(['name' => $name, 'gender' => 'female', 'status' => BusinessStatus::ACTIVE]);
        $staff->branches()->sync([$f['branch']->id => ['tenant_id' => $f['tenant']->id]]);
        $staff->services()->sync([$f['haircut']->id => ['tenant_id' => $f['tenant']->id]]);
        app(TenantContext::class)->clear();

        return $staff;
    }

    private function createBooking(array $f, array $overrides = []): Booking
    {
        app(TenantContext::class)->set($f['tenant']);
        $subtotal = $overrides['subtotal'] ?? 300;
        $discount = $overrides['discount'] ?? 0;
        $total = $overrides['total'] ?? ($subtotal - $discount);
        $booking = Booking::query()->create([
            'branch_id' => $f['branch']->id,
            'customer_id' => $overrides['customer_id'] ?? $f['customer']->id,
            'booking_date' => $overrides['booking_date'] ?? Carbon::now('UTC')->toDateString(),
            'start_time' => '10:00:00', 'end_time' => '10:30:00',
            'status' => $overrides['status'] ?? 'pending',
            'subtotal' => $subtotal, 'discount' => $discount, 'tax' => 0, 'total' => $total,
            'cancellation_reason' => $overrides['cancellation_reason'] ?? null,
        ]);
        BookingItem::query()->create([
            'booking_id' => $booking->id, 'service_id' => $f['haircut']->id, 'staff_id' => $f['staff']->id,
            'service_name' => 'Haircut', 'service_price' => $overrides['service_price'] ?? $subtotal, 'service_duration_minutes' => 30, 'quantity' => 1,
            'start_time' => '10:00:00', 'end_time' => '10:30:00', 'subtotal' => $subtotal,
        ]);
        app(TenantContext::class)->clear();

        return $booking;
    }
}
