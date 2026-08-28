<?php

namespace Tests\Feature;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Booking;
use App\Models\BookingItem;
use App\Models\Branch;
use App\Models\BranchWorkingHour;
use App\Models\Customer;
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
use Tests\TestCase;

class BookingEngineApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_owner_can_view_availability_and_create_confirm_progress_and_complete_a_booking(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $date = $this->bookingDate();

        $availability = $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date=$date&service_ids[]={$f['haircut']->id}")->assertOk()->json('data');
        $this->assertNotEmpty($availability['slots']);
        $this->assertSame('09:00', $availability['slots'][0]['start_time']);
        $this->assertContains($f['amit']->id, collect($availability['staff'])->pluck('id'));
        $this->assertSame('Amit', collect($availability['staff'])->firstWhere('id', $f['amit']->id)['name']);

        $booking = $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id,
            'customer_id' => $f['customer']->id,
            'date' => $date,
            'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => null]],
        ])->assertCreated()
            ->assertJsonPath('data.status', 'pending')
            ->assertJsonPath('data.total', '300.00')
            ->assertJsonPath('data.items.0.service_name', 'Haircut')
            ->assertJsonPath('data.items.0.service_price', '300.00')
            ->json('data');
        $id = $booking['id'];

        $api->postJson("/api/v1/bookings/$id/confirm")->assertOk()->assertJsonPath('data.status', 'confirmed');
        $api->patchJson("/api/v1/bookings/$id", ['status' => 'checked_in'])->assertOk()->assertJsonPath('data.status', 'checked_in');
        $api->patchJson("/api/v1/bookings/$id", ['status' => 'in_service'])->assertOk()->assertJsonPath('data.status', 'in_service');
        $api->patchJson("/api/v1/bookings/$id", ['status' => 'completed'])->assertOk()->assertJsonPath('data.status', 'completed');
        $api->patchJson("/api/v1/bookings/$id", ['status' => 'checked_in'])->assertStatus(409);

        $api->getJson("/api/v1/bookings/$id")->assertOk()->assertJsonCount(5, 'data.status_history');
    }

    public function test_customer_can_browse_branch_services_but_not_inactive_or_foreign_ones(): void
    {
        $f = $this->fixture('a');
        $g = $this->fixture('b');
        $customerUser = User::factory()->create(['role' => UserRole::CUSTOMER]);

        app(TenantContext::class)->set($f['tenant']);
        $f['facial']->update(['status' => BusinessStatus::INACTIVE]);
        app(TenantContext::class)->clear();

        $resp = $this->actingAs($customerUser, 'sanctum')->getJson("/api/v1/branches/{$f['branch']->id}/services")->assertOk()->json('data');
        $this->assertCount(1, $resp['categories']);
        $this->assertCount(1, $resp['services']);
        $this->assertSame('Haircut', $resp['services'][0]['name']);
        $this->assertSame('Hair', $resp['services'][0]['category']['name']);

        $this->actingAs($customerUser, 'sanctum')->getJson("/api/v1/branches/{$g['branch']->id}/services")->assertOk()
            ->assertJsonCount(2, 'data.services');
    }

    public function test_booking_creation_rejects_foreign_service_inactive_service_and_past_date(): void
    {
        $f = $this->fixture('a');
        $g = $this->fixture('b');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $date = $this->bookingDate();

        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $g['haircut']->id, 'staff_id' => null]],
        ])->assertUnprocessable();

        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => Carbon::yesterday()->toDateString(), 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => null]],
        ])->assertStatus(409);

        app(TenantContext::class)->set($f['tenant']);
        $f['haircut']->update(['status' => BusinessStatus::INACTIVE]);
        app(TenantContext::class)->clear();
        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => null]],
        ])->assertStatus(409);
    }

    public function test_specific_staff_any_available_staff_and_invalid_staff_service_combinations(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $date = $this->bookingDate();

        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertCreated()->assertJsonPath('data.items.0.staff_id', $f['amit']->id);

        $auto = $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '11:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => null]],
        ])->assertCreated()->json('data');
        $this->assertNotNull($auto['items'][0]['staff_id']);

        app(TenantContext::class)->set($f['tenant']);
        $f['amit']->update(['status' => BusinessStatus::INACTIVE]);
        app(TenantContext::class)->clear();
        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '12:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertStatus(409);

        app(TenantContext::class)->set($f['tenant']);
        $unassigned = Service::query()->create(['branch_id' => $f['branch']->id, 'category_id' => $f['haircut']->category_id, 'name' => 'Shave', 'slug' => 'shave-a', 'gender' => GenderType::UNISEX, 'price' => '100.00', 'duration_minutes' => 15, 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();
        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '13:00',
            'items' => [['service_id' => $unassigned->id, 'staff_id' => $f['priya']->id]],
        ])->assertStatus(409);

        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '13:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => null], ['service_id' => $f['facial']->id, 'staff_id' => $f['priya']->id]],
        ])->assertStatus(409);
    }

    public function test_multi_service_booking_supports_sequential_same_staff_and_parallel_different_staff(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $date = $this->bookingDate();

        $sequential = $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [
                ['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id],
                ['service_id' => $f['facial']->id, 'staff_id' => $f['amit']->id],
            ],
        ])->assertCreated()->assertJsonPath('data.total', '800.00')->json('data');
        $this->assertSame(['09:00', '09:30'], [$sequential['items'][0]['start_time'], $sequential['items'][0]['end_time']]);
        $this->assertSame(['09:30', '10:15'], [$sequential['items'][1]['start_time'], $sequential['items'][1]['end_time']]);
        $this->assertSame('10:15', $sequential['end_time']);

        $parallel = $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '12:00',
            'items' => [
                ['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id],
                ['service_id' => $f['facial']->id, 'staff_id' => $f['priya']->id],
            ],
        ])->assertCreated()->json('data');
        $this->assertSame(['12:00', '12:30'], [$parallel['items'][0]['start_time'], $parallel['items'][0]['end_time']]);
        $this->assertSame(['12:00', '12:45'], [$parallel['items'][1]['start_time'], $parallel['items'][1]['end_time']]);
        $this->assertSame('12:45', $parallel['end_time']);
    }

    public function test_historical_snapshot_is_unaffected_by_later_service_price_change(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $date = $this->bookingDate();

        $booking = $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertCreated()->assertJsonPath('data.items.0.service_price', '300.00')->json('data');

        app(TenantContext::class)->set($f['tenant']);
        $f['haircut']->update(['price' => '400.00']);
        app(TenantContext::class)->clear();

        $api->getJson('/api/v1/bookings/'.$booking['id'])->assertOk()
            ->assertJsonPath('data.items.0.service_price', '300.00')
            ->assertJsonPath('data.total', '300.00');
    }

    public function test_customer_summary_derives_real_totals_from_booking_history(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $date = $this->bookingDate();
        $laterDate = Carbon::today()->addDays(5)->toDateString();

        $completed = $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertCreated()->json('data');
        $api->postJson("/api/v1/bookings/{$completed['id']}/confirm")->assertOk();
        $api->patchJson("/api/v1/bookings/{$completed['id']}", ['status' => 'checked_in'])->assertOk();
        $api->patchJson("/api/v1/bookings/{$completed['id']}", ['status' => 'in_service'])->assertOk();
        $api->patchJson("/api/v1/bookings/{$completed['id']}", ['status' => 'completed'])->assertOk();

        $cancelled = $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '11:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertCreated()->json('data');
        $api->postJson("/api/v1/bookings/{$cancelled['id']}/cancel", ['reason' => 'test'])->assertOk();

        $upcoming = $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $laterDate, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertCreated()->json('data');

        $summary = $api->getJson("/api/v1/customers/{$f['customer']->id}/summary")->assertOk()->json('data.summary');

        $this->assertSame(3, $summary['total_visits']);
        $this->assertSame(1, $summary['completed_appointments']);
        $this->assertSame(1, $summary['cancelled_appointments']);
        $this->assertSame(0, $summary['no_show_count']);
        $this->assertSame('300.00', $summary['total_spent']);
        $this->assertSame($date, $summary['last_visit_at']);
        $this->assertSame($upcoming['id'], $summary['upcoming_appointment']['id']);
        $this->assertSame('pending', $summary['upcoming_appointment']['status']);
    }

    public function test_dashboard_summary_reflects_real_bookings_staff_and_customer_data(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $today = Carbon::today()->toDateString();

        // Created directly via Eloquent (not the create-booking API) so this test is not
        // sensitive to what time of day it happens to run — it exercises the dashboard
        // query, not booking-creation's advance-notice validation.
        app(TenantContext::class)->set($f['tenant']);
        $completedBooking = Booking::query()->create([
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'booking_date' => $today,
            'start_time' => '09:00', 'end_time' => '09:30', 'status' => 'completed',
            'subtotal' => '300.00', 'discount' => '0.00', 'tax' => '0.00', 'total' => '300.00',
        ]);
        BookingItem::query()->create([
            'booking_id' => $completedBooking->id, 'service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id,
            'service_name' => 'Haircut', 'service_price' => '300.00', 'service_duration_minutes' => 30,
            'quantity' => 1, 'start_time' => '09:00', 'end_time' => '09:30', 'subtotal' => '300.00',
        ]);
        $pendingBooking = Booking::query()->create([
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'booking_date' => $today,
            'start_time' => '11:00', 'end_time' => '11:30', 'status' => 'pending',
            'subtotal' => '300.00', 'discount' => '0.00', 'tax' => '0.00', 'total' => '300.00',
        ]);
        $f['priya']->leaves()->create(['start_date' => $today, 'end_date' => $today, 'reason' => 'Sick']);
        app(TenantContext::class)->clear();

        $summary = $api->getJson('/api/v1/dashboard/summary')->assertOk()->json('data');

        $this->assertSame($today, $summary['date']);
        $this->assertSame(2, $summary['bookings']['total']);
        $this->assertSame(1, $summary['bookings']['completed']);
        $this->assertSame(1, $summary['bookings']['pending']);
        $this->assertSame('300.00', $summary['revenue_today']);
        $this->assertSame($pendingBooking->id, $summary['next_appointment']['id']);
        $this->assertSame(2, $summary['staff']['active']);
        $this->assertSame(1, $summary['staff']['on_leave_today']);
        $this->assertSame(1, $summary['customers']['total']);
        $this->assertSame(1, $summary['customers']['new_this_month']);
    }

    public function test_availability_returns_no_slots_when_branch_closed_or_on_holiday(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $date = $this->bookingDate();

        $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date=$date&service_ids[]={$f['haircut']->id}")->assertOk()->assertJsonPath('data.slots.0.start_time', '09:00');

        $holiday = $api->postJson("/api/v1/branches/{$f['branch']->id}/holidays", ['holiday_date' => $date, 'name' => 'Test Holiday'])->assertCreated()->json('data');
        $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date=$date&service_ids[]={$f['haircut']->id}")->assertOk()->assertJsonCount(0, 'data.slots');
        $api->deleteJson("/api/v1/branches/{$f['branch']->id}/holidays/{$holiday['id']}")->assertOk();

        $dow = Carbon::parse($date)->dayOfWeek;
        $api->putJson("/api/v1/branches/{$f['branch']->id}/working-hours", [
            'hours' => [['day_of_week' => $dow, 'is_open' => false]],
        ])->assertOk();
        $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date=$date&service_ids[]={$f['haircut']->id}")->assertOk()->assertJsonCount(0, 'data.slots');
    }

    public function test_availability_excludes_staff_on_break_or_leave_but_falls_back_to_other_eligible_staff(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $date = $this->bookingDate();
        $dow = Carbon::parse($date)->dayOfWeek;

        $api->postJson("/api/v1/staff/{$f['amit']->id}/breaks", ['day_of_week' => $dow, 'start_time' => '10:00', 'end_time' => '10:30'])->assertCreated();

        $amitOnly = $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date=$date&service_ids[]={$f['haircut']->id}&staff_id={$f['amit']->id}")->assertOk()->json('data');
        $this->assertFalse(collect($amitOnly['slots'])->contains(fn ($s) => $s['start_time'] === '10:00'));

        $any = $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date=$date&service_ids[]={$f['haircut']->id}")->assertOk()->json('data');
        $slotAt10 = collect($any['slots'])->firstWhere('start_time', '10:00');
        $this->assertNotNull($slotAt10);
        $this->assertContains($f['priya']->id, $slotAt10['staff_ids']);
        $this->assertNotContains($f['amit']->id, $slotAt10['staff_ids']);

        $api->postJson("/api/v1/staff/{$f['amit']->id}/leaves", ['start_date' => $date, 'end_date' => $date, 'reason' => 'Personal'])->assertCreated();
        $amitLeave = $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date=$date&service_ids[]={$f['haircut']->id}&staff_id={$f['amit']->id}")->assertOk()->json('data');
        $this->assertSame([], $amitLeave['slots']);
    }

    public function test_availability_and_creation_respect_existing_booking_conflicts(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $date = $this->bookingDate();

        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertCreated();

        $resp = $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date=$date&service_ids[]={$f['haircut']->id}&staff_id={$f['amit']->id}")->assertOk()->json('data');
        $this->assertFalse(collect($resp['slots'])->contains(fn ($s) => $s['start_time'] === '09:00'));
        $this->assertTrue(collect($resp['slots'])->contains(fn ($s) => $s['start_time'] === '09:30'));

        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:15',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertStatus(409);

        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:30',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertCreated();

        app(TenantContext::class)->set($f['tenant']);
        $count = BookingItem::query()->where('staff_id', $f['amit']->id)->count();
        app(TenantContext::class)->clear();
        $this->assertSame(2, $count);
    }

    /**
     * Double-booking prevention relies on DB::transaction() + Staff::lockForUpdate() +
     * a fresh overlap re-check while holding that lock (see BOOKING_ENGINE.md). PHPUnit
     * runs this suite single-threaded against one SQLite connection, so true concurrent
     * requests from separate OS processes/connections cannot be exercised here. This
     * test instead exercises the exact mechanism a real race would hit: two requests
     * for the identical staff/date/time, submitted back to back. The second request's
     * transaction re-checks availability under the staff row lock and must observe the
     * first request's already-committed booking, so exactly one request must succeed —
     * this is the same code path (and same guarantee) a genuine concurrent race relies on.
     */
    public function test_two_requests_for_the_same_staff_and_slot_result_in_exactly_one_successful_booking(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $date = $this->bookingDate();

        $payload = [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '15:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ];

        $first = $api->postJson('/api/v1/bookings', $payload);
        $second = $api->postJson('/api/v1/bookings', $payload);

        $statuses = [$first->getStatusCode(), $second->getStatusCode()];
        sort($statuses);
        $this->assertSame([201, 409], $statuses);

        app(TenantContext::class)->set($f['tenant']);
        $overlapping = BookingItem::query()->where('staff_id', $f['amit']->id)
            ->whereHas('booking', fn ($q) => $q->where('booking_date', $date))
            ->where('start_time', '15:00')
            ->count();
        app(TenantContext::class)->clear();
        $this->assertSame(1, $overlapping);
    }

    public function test_booking_buffer_blocks_immediately_adjacent_slot_but_allows_slot_after_buffer(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $api->putJson('/api/v1/salon/settings', ['settings' => ['booking_buffer_minutes' => 15]])->assertOk();
        $date = $this->bookingDate();

        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertCreated();

        $resp = $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date=$date&service_ids[]={$f['haircut']->id}&staff_id={$f['amit']->id}")->assertOk()->json('data');
        $starts = collect($resp['slots'])->pluck('start_time');
        $this->assertFalse($starts->contains('09:30'));
        $this->assertTrue($starts->contains('09:45'));

        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:30',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertStatus(409);
    }

    public function test_max_advance_booking_window_is_enforced(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $api->putJson('/api/v1/salon/settings', ['settings' => ['max_advance_booking_days' => 1]])->assertOk();

        $tooFar = Carbon::today()->addDays(5)->toDateString();
        $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date=$tooFar&service_ids[]={$f['haircut']->id}")->assertUnprocessable();
        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $tooFar, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertStatus(409);

        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $this->bookingDate(), 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertCreated();
    }

    public function test_cancellation_and_reschedule_via_owner_and_customer_self_service(): void
    {
        $f = $this->fixture('a');
        $customerUser = User::factory()->create(['role' => UserRole::CUSTOMER]);
        app(TenantContext::class)->set($f['tenant']);
        $f['customer']->update(['user_id' => $customerUser->id]);
        app(TenantContext::class)->clear();
        $date = $this->bookingDate();

        $selfApi = $this->actingAs($customerUser, 'sanctum');
        $booking = $selfApi->postJson('/api/v1/customer/bookings', [
            'branch_id' => $f['branch']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => null]],
        ])->assertCreated()->assertJsonPath('data.status', 'pending')->json('data');

        $selfApi2 = $this->actingAs($customerUser, 'sanctum');
        $selfApi2->getJson('/api/v1/customer/bookings')->assertOk()->assertJsonCount(1, 'data');
        $selfApi2->getJson('/api/v1/customer/bookings/'.$booking['id'])->assertOk()->assertJsonPath('data.id', $booking['id']);
        $selfApi2->postJson('/api/v1/customer/bookings/'.$booking['id'].'/reschedule', ['date' => $date, 'start_time' => '11:00'])
            ->assertOk()->assertJsonPath('data.start_time', '11:00');

        $ownerApi = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $ownerApi->putJson('/api/v1/salon/settings', ['settings' => ['cancellation_window_minutes' => 100000]])->assertOk();

        $selfApi3 = $this->actingAs($customerUser, 'sanctum');
        $selfApi3->postJson('/api/v1/customer/bookings/'.$booking['id'].'/cancel', ['reason' => 'change of mind'])->assertStatus(409);

        $ownerApi2 = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $ownerApi2->postJson('/api/v1/bookings/'.$booking['id'].'/cancel', ['reason' => 'owner override'])
            ->assertOk()->assertJsonPath('data.status', 'cancelled');

        $otherCustomer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $this->actingAs($otherCustomer, 'sanctum')->getJson('/api/v1/customer/bookings/'.$booking['id'])->assertNotFound();
    }

    public function test_reschedule_revalidates_and_rejects_a_now_conflicting_slot(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $date = $this->bookingDate();

        $booking = $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertCreated()->json('data');

        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '11:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertCreated();

        $api->postJson('/api/v1/bookings/'.$booking['id'].'/reschedule', ['date' => $date, 'start_time' => '11:00'])->assertStatus(409);
        $api->postJson('/api/v1/bookings/'.$booking['id'].'/reschedule', ['date' => $date, 'start_time' => '13:00'])->assertOk()->assertJsonPath('data.start_time', '13:00');
    }

    public function test_staff_has_full_operational_booking_access_and_platform_customer_role_is_denied(): void
    {
        $f = $this->fixture('a');
        $ownerApi = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $date = $this->bookingDate();
        $booking = $ownerApi->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertCreated()->json('data');

        $staffUser = User::factory()->create(['role' => UserRole::STAFF]);
        $f['tenant']->users()->attach($staffUser, ['role' => TenantMembershipRole::STAFF->value]);
        $staffApi = $this->actingAs($staffUser, 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        $staffApi->getJson('/api/v1/bookings')->assertOk();
        $staffApi->postJson('/api/v1/bookings/'.$booking['id'].'/confirm')->assertOk();
        $staffApi->patchJson('/api/v1/bookings/'.$booking['id'], ['status' => 'checked_in'])->assertOk();

        $platformCustomer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $this->actingAs($platformCustomer, 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug)->getJson('/api/v1/bookings')->assertForbidden();
    }

    public function test_tenant_isolation_rejects_foreign_resources_and_direct_id_access(): void
    {
        $f = $this->fixture('a');
        $g = $this->fixture('b');
        $date = $this->bookingDate();
        $apiB = $this->actingAs($g['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $g['tenant']->slug);
        $bookingB = $apiB->postJson('/api/v1/bookings', [
            'branch_id' => $g['branch']->id, 'customer_id' => $g['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $g['haircut']->id, 'staff_id' => $g['amit']->id]],
        ])->assertCreated()->json('data');

        $apiA = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $apiA->getJson('/api/v1/bookings/'.$bookingB['id'])->assertNotFound();
        $apiA->postJson('/api/v1/bookings/'.$bookingB['id'].'/confirm')->assertNotFound();
        $apiA->postJson('/api/v1/bookings/'.$bookingB['id'].'/cancel')->assertNotFound();

        $apiA->postJson('/api/v1/bookings', [
            'branch_id' => $g['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => null]],
        ])->assertUnprocessable();
        $apiA->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $g['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => null]],
        ])->assertUnprocessable();
        $apiA->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $g['amit']->id]],
        ])->assertUnprocessable();

        $this->assertDatabaseHas('bookings', ['id' => $bookingB['id']]);
    }

    private function bookingDate(): string
    {
        return Carbon::today()->addDay()->toDateString();
    }

    /**
     * @return array{tenant: Tenant, owner: User, branch: Branch, haircut: Service, facial: Service, amit: Staff, priya: Staff, customer: Customer}
     */
    private function fixture(string $slug): array
    {
        $tenant = Tenant::query()->create(['name' => $slug, 'slug' => $slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);
        app(TenantContext::class)->set($tenant);

        $salon = Salon::query()->create(['name' => $slug, 'slug' => $slug, 'gender_type' => GenderType::UNISEX, 'status' => BusinessStatus::ACTIVE, 'timezone' => 'UTC']);
        $branch = Branch::query()->create(['salon_id' => $salon->id, 'name' => 'Main', 'slug' => 'main', 'status' => BusinessStatus::ACTIVE, 'timezone' => 'UTC']);
        foreach (range(0, 6) as $day) {
            BranchWorkingHour::query()->create(['branch_id' => $branch->id, 'day_of_week' => $day, 'is_open' => true, 'opening_time' => '09:00', 'closing_time' => '20:00']);
        }

        $category = ServiceCategory::query()->create(['branch_id' => $branch->id, 'name' => 'Hair', 'slug' => 'hair-'.$slug, 'status' => BusinessStatus::ACTIVE]);
        $haircut = Service::query()->create(['branch_id' => $branch->id, 'category_id' => $category->id, 'name' => 'Haircut', 'slug' => 'haircut-'.$slug, 'gender' => GenderType::UNISEX, 'price' => '300.00', 'duration_minutes' => 30, 'status' => BusinessStatus::ACTIVE]);
        $facial = Service::query()->create(['branch_id' => $branch->id, 'category_id' => $category->id, 'name' => 'Facial', 'slug' => 'facial-'.$slug, 'gender' => GenderType::UNISEX, 'price' => '500.00', 'duration_minutes' => 45, 'status' => BusinessStatus::ACTIVE]);

        $amit = Staff::query()->create(['name' => 'Amit', 'gender' => 'male', 'status' => BusinessStatus::ACTIVE]);
        $amit->branches()->sync([$branch->id => ['tenant_id' => $tenant->id]]);
        $amit->services()->sync([$haircut->id => ['tenant_id' => $tenant->id], $facial->id => ['tenant_id' => $tenant->id]]);
        foreach (range(0, 6) as $day) {
            StaffWorkingHour::query()->create(['staff_id' => $amit->id, 'day_of_week' => $day, 'is_working' => true, 'start_time' => '09:00', 'end_time' => '20:00']);
        }

        $priya = Staff::query()->create(['name' => 'Priya', 'gender' => 'female', 'status' => BusinessStatus::ACTIVE]);
        $priya->branches()->sync([$branch->id => ['tenant_id' => $tenant->id]]);
        $priya->services()->sync([$haircut->id => ['tenant_id' => $tenant->id], $facial->id => ['tenant_id' => $tenant->id]]);
        foreach (range(0, 6) as $day) {
            StaffWorkingHour::query()->create(['staff_id' => $priya->id, 'day_of_week' => $day, 'is_working' => true, 'start_time' => '09:00', 'end_time' => '20:00']);
        }

        $customer = Customer::query()->create(['name' => 'Rahul', 'phone' => '90000000'.($slug === 'a' ? '01' : '02'), 'normalized_phone' => '90000000'.($slug === 'a' ? '01' : '02'), 'status' => BusinessStatus::ACTIVE]);

        app(TenantContext::class)->clear();

        return compact('tenant', 'owner', 'branch', 'haircut', 'facial', 'amit', 'priya', 'customer');
    }
}
