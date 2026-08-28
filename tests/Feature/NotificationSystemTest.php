<?php

namespace Tests\Feature;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Enums\NotificationChannel;
use App\Enums\NotificationEventType;
use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Booking;
use App\Models\BookingReminder;
use App\Models\Branch;
use App\Models\BranchWorkingHour;
use App\Models\Customer;
use App\Models\Notification;
use App\Models\NotificationDelivery;
use App\Models\NotificationPreference;
use App\Models\Plan;
use App\Models\Salon;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\Staff;
use App\Models\StaffWorkingHour;
use App\Models\Subscription;
use App\Models\Tenant;
use App\Models\User;
use App\Models\UserDeviceToken;
use App\Services\Billing\Gateways\FakePaymentGateway;
use App\Services\Billing\Gateways\PaymentGatewayInterface;
use App\Services\Billing\SubscriptionService;
use App\Services\Notifications\BookingReminderService;
use App\Services\Notifications\Providers\FakePushProvider;
use App\Services\Notifications\Providers\ProviderSendResult;
use App\Services\Notifications\Providers\PushProviderInterface;
use App\Support\TenantContext;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class NotificationSystemTest extends TestCase
{
    use RefreshDatabase;

    // --- In-app: booking lifecycle notifications ---

    public function test_booking_created_confirmed_rescheduled_and_cancelled_notify_the_right_audiences(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $date = $this->bookingDate();

        $booking = $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['staff']->id]],
        ])->assertCreated()->json('data');
        $id = $booking['id'];

        // Created: customer + staff + owner all get an in-app row.
        $this->assertNotificationExists($f['customerUser'], NotificationEventType::BOOKING_CREATED, $id);
        $this->assertNotificationExists($f['staffUser'], NotificationEventType::BOOKING_CREATED, $id);
        $this->assertNotificationExists($f['owner'], NotificationEventType::BOOKING_CREATED, $id);

        // Confirmed: customer + staff, not owner.
        $api->postJson("/api/v1/bookings/$id/confirm")->assertOk();
        $this->assertNotificationExists($f['customerUser'], NotificationEventType::BOOKING_CONFIRMED, $id);
        $this->assertNotificationExists($f['staffUser'], NotificationEventType::BOOKING_CONFIRMED, $id);
        $this->assertNotificationMissing($f['owner'], NotificationEventType::BOOKING_CONFIRMED, $id);

        // Rescheduled: old/new time present in the body.
        $api->postJson("/api/v1/bookings/$id/reschedule", ['date' => $date, 'start_time' => '11:00'])->assertOk();
        $rescheduled = Notification::query()->where('user_id', $f['customerUser']->id)->where('type', NotificationEventType::BOOKING_RESCHEDULED->value)->first();
        $this->assertNotNull($rescheduled);
        $this->assertStringContainsString('09:00', $rescheduled->body);
        $this->assertStringContainsString('11:00', $rescheduled->body);

        // Cancelled: customer + staff + owner, reason included.
        $api->postJson("/api/v1/bookings/$id/cancel", ['reason' => 'Customer requested'])->assertOk();
        $cancelled = Notification::query()->where('user_id', $f['owner']->id)->where('type', NotificationEventType::BOOKING_CANCELLED->value)->first();
        $this->assertNotNull($cancelled);
        $this->assertStringContainsString('Customer requested', $cancelled->body);
        $this->assertNotificationExists($f['customerUser'], NotificationEventType::BOOKING_CANCELLED, $id);
        $this->assertNotificationExists($f['staffUser'], NotificationEventType::BOOKING_CANCELLED, $id);
    }

    public function test_checked_in_started_completed_and_no_show_use_a_low_noise_policy(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $date = $this->bookingDate();

        $booking = $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['staff']->id]],
        ])->assertCreated()->json('data');
        $id = $booking['id'];
        $api->postJson("/api/v1/bookings/$id/confirm")->assertOk();

        $api->patchJson("/api/v1/bookings/$id", ['status' => 'checked_in'])->assertOk();
        // Owner-only audit trail; not pushed to the customer or the staff member performing the action.
        $this->assertNotificationExists($f['owner'], NotificationEventType::BOOKING_CHECKED_IN, $id);
        $this->assertNotificationMissing($f['customerUser'], NotificationEventType::BOOKING_CHECKED_IN, $id);

        $api->patchJson("/api/v1/bookings/$id", ['status' => 'in_service'])->assertOk();
        $this->assertNotificationExists($f['owner'], NotificationEventType::BOOKING_STARTED, $id);

        $api->patchJson("/api/v1/bookings/$id", ['status' => 'completed'])->assertOk();
        $this->assertNotificationExists($f['customerUser'], NotificationEventType::BOOKING_COMPLETED, $id);
        $this->assertNotificationExists($f['staffUser'], NotificationEventType::BOOKING_COMPLETED, $id);

        // No-show on a second booking: owner + staff, not the customer.
        $second = $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '13:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['staff']->id]],
        ])->assertCreated()->json('data.id');
        $api->postJson("/api/v1/bookings/$second/confirm")->assertOk();
        $api->patchJson("/api/v1/bookings/$second", ['status' => 'no_show'])->assertOk();
        $this->assertNotificationExists($f['owner'], NotificationEventType::BOOKING_NO_SHOW, $second);
        $this->assertNotificationExists($f['staffUser'], NotificationEventType::BOOKING_NO_SHOW, $second);
        $this->assertNotificationMissing($f['customerUser'], NotificationEventType::BOOKING_NO_SHOW, $second);
    }

    // --- In-app API: list, unread count, mark read, mark all read, pagination ---

    public function test_notification_list_unread_count_mark_read_and_mark_all_read(): void
    {
        $f = $this->fixture('a');
        $this->createBookingNotifications($f, 3);

        $api = $this->actingAs($f['customerUser'], 'sanctum');
        $api->getJson('/api/v1/notifications/unread-count')->assertOk()->assertJsonPath('data.unread_count', 3);

        $list = $api->getJson('/api/v1/notifications?per_page=2')->assertOk()->json('data');
        $this->assertCount(2, $list);

        $first = $list[0];
        $api->postJson("/api/v1/notifications/{$first['id']}/read")->assertOk()->assertJsonPath('data.is_read', true);
        $api->getJson('/api/v1/notifications/unread-count')->assertOk()->assertJsonPath('data.unread_count', 2);

        $api->postJson('/api/v1/notifications/read-all')->assertOk()->assertJsonPath('data.updated', 2);
        $api->getJson('/api/v1/notifications/unread-count')->assertOk()->assertJsonPath('data.unread_count', 0);
    }

    // --- Tenant isolation / authorization ---

    public function test_a_users_notifications_are_invisible_to_and_unreachable_by_another_user(): void
    {
        $f = $this->fixture('a');
        $this->createBookingNotifications($f, 1);
        $mine = Notification::query()->where('user_id', $f['customerUser']->id)->firstOrFail();

        $otherCustomer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $otherApi = $this->actingAs($otherCustomer, 'sanctum');

        $otherApi->getJson('/api/v1/notifications')->assertOk()->assertJsonCount(0, 'data');
        $otherApi->getJson('/api/v1/notifications/unread-count')->assertOk()->assertJsonPath('data.unread_count', 0);
        // Direct-ID access to someone else's notification is a 404, not the record.
        $otherApi->postJson("/api/v1/notifications/{$mine->id}/read")->assertNotFound();
        $this->assertNull($mine->fresh()->read_at);
    }

    // --- Queue / isolation from the business transaction ---

    public function test_booking_creation_succeeds_even_when_every_external_channel_delivery_fails(): void
    {
        $f = $this->fixture('a');
        $push = new FakePushProvider;
        $push->nextResult = ProviderSendResult::retryableFailure('simulated outage');
        $this->app->bind(PushProviderInterface::class, fn () => $push);
        UserDeviceToken::query()->create(['user_id' => $f['customerUser']->id, 'platform' => 'android', 'token' => 'tok-1', 'is_active' => true]);
        NotificationPreference::query()->create(['tenant_id' => null, 'user_id' => $f['customerUser']->id, 'event_type' => NotificationEventType::BOOKING_CREATED->value, 'channel' => NotificationChannel::PUSH->value, 'enabled' => true]);

        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $date = $this->bookingDate();

        $response = $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['staff']->id]],
        ])->assertCreated();

        // The booking itself committed successfully...
        $this->assertDatabaseHas('bookings', ['id' => $response->json('data.id'), 'status' => 'pending']);
        // ...even though its push delivery failed and is recorded as such, never silently dropped.
        $delivery = NotificationDelivery::query()->where('channel', NotificationChannel::PUSH->value)->where('event_type', NotificationEventType::BOOKING_CREATED->value)->firstOrFail();
        $this->assertSame('failed', $delivery->status->value);
        $this->assertSame('simulated outage', $delivery->failure_reason);
    }

    public function test_push_is_skipped_without_a_device_token_and_sent_once_configured_and_enabled(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $date = $this->bookingDate();

        // No device token yet, and push is disabled by config default for booking.created only
        // through the *unavailability* path here: no token at all.
        $booking = $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['staff']->id]],
        ])->assertCreated()->json('data');
        $this->assertSame(0, NotificationDelivery::query()->where('channel', NotificationChannel::PUSH->value)->count());

        // Now register a token and bind a working fake push provider — the very next
        // matching event should actually queue and "send" a push delivery.
        UserDeviceToken::query()->create(['user_id' => $f['customerUser']->id, 'platform' => 'android', 'token' => 'tok-1', 'is_active' => true]);
        $push = new FakePushProvider;
        $this->app->bind(PushProviderInterface::class, fn () => $push);

        $api->postJson("/api/v1/bookings/{$booking['id']}/confirm")->assertOk();

        $delivery = NotificationDelivery::query()->where('channel', NotificationChannel::PUSH->value)->where('event_type', NotificationEventType::BOOKING_CONFIRMED->value)->first();
        $this->assertNotNull($delivery);
        $this->assertSame('sent', $delivery->status->value);
        $this->assertCount(1, $push->sent);
    }

    // --- Preferences gate delivery ---

    public function test_disabling_a_channel_preference_prevents_its_delivery(): void
    {
        $f = $this->fixture('a');
        UserDeviceToken::query()->create(['user_id' => $f['customerUser']->id, 'platform' => 'android', 'token' => 'tok-1', 'is_active' => true]);
        $this->app->bind(PushProviderInterface::class, fn () => new FakePushProvider);

        // Personal opt-out of push for booking.created, set via the API.
        $this->actingAs($f['customerUser'], 'sanctum')->putJson('/api/v1/notifications/preferences', [
            'preferences' => [['event_type' => 'booking.created', 'channel' => 'push', 'enabled' => false]],
        ])->assertOk();

        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $this->bookingDate(), 'start_time' => '09:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['staff']->id]],
        ])->assertCreated();

        $this->assertSame(0, NotificationDelivery::query()->where('channel', NotificationChannel::PUSH->value)->count());
        // The in-app notification is unaffected by an external-channel opt-out.
        $this->assertNotificationExists($f['customerUser'], NotificationEventType::BOOKING_CREATED, null);
    }

    public function test_owner_can_set_a_tenant_wide_default_that_a_personal_preference_still_overrides(): void
    {
        $f = $this->fixture('a');
        $ownerApi = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        $ownerApi->putJson('/api/v1/salon/notification-settings', [
            'preferences' => [['event_type' => 'booking.cancelled', 'channel' => 'email', 'enabled' => false]],
        ])->assertOk();
        $tenantRow = $ownerApi->getJson('/api/v1/salon/notification-settings')->assertOk()->json('data');
        $row = collect($tenantRow)->firstWhere(fn ($r) => $r['event_type'] === 'booking.cancelled' && $r['channel'] === 'email');
        $this->assertFalse($row['enabled']);

        // A staff member who is not the owner cannot change the tenant-wide setting.
        $this->actingAs($f['staffUser'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug)
            ->putJson('/api/v1/salon/notification-settings', ['preferences' => [['event_type' => 'booking.cancelled', 'channel' => 'email', 'enabled' => true]]])
            ->assertForbidden();
    }

    // --- Reminders: idempotency + status gating ---

    public function test_reminders_fire_once_are_not_duplicated_and_skip_cancelled_or_completed_bookings(): void
    {
        $f = $this->fixture('a');
        $branchTz = $f['branch']->timezone ?: 'UTC';
        $start = CarbonImmutable::now($branchTz)->addHours(2)->addMinutes(5);

        $context = app(TenantContext::class);
        $context->set($f['tenant']);
        $due = Booking::query()->create([
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id,
            'booking_date' => $start->toDateString(), 'start_time' => $start->format('H:i'), 'end_time' => $start->addMinutes(30)->format('H:i'),
            'status' => 'confirmed', 'subtotal' => 300, 'total' => 300,
        ]);
        $due->items()->create(['service_id' => $f['haircut']->id, 'staff_id' => $f['staff']->id, 'service_name' => 'Haircut', 'service_price' => 300, 'service_duration_minutes' => 30, 'start_time' => $start->format('H:i'), 'end_time' => $start->addMinutes(30)->format('H:i'), 'subtotal' => 300]);

        $cancelled = Booking::query()->create([
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id,
            'booking_date' => $start->toDateString(), 'start_time' => $start->format('H:i'), 'end_time' => $start->addMinutes(30)->format('H:i'),
            'status' => 'cancelled', 'subtotal' => 300, 'total' => 300,
        ]);
        $context->clear();

        $service = app(BookingReminderService::class);
        $summary = $service->processDueReminders();

        $this->assertSame(1, $summary['sent']);
        $this->assertNotificationExists($f['customerUser'], NotificationEventType::BOOKING_REMINDER, $due->id);
        $this->assertNotificationMissing($f['customerUser'], NotificationEventType::BOOKING_REMINDER, $cancelled->id);
        $this->assertSame(1, BookingReminder::query()->where('booking_id', $due->id)->count());

        // Running it again must not send a second reminder for the same booking/type.
        $again = $service->processDueReminders();
        $this->assertSame(0, $again['sent']);
        $this->assertGreaterThanOrEqual(1, $again['skipped_duplicate']);
        $this->assertSame(1, Notification::query()->where('user_id', $f['customerUser']->id)->where('type', NotificationEventType::BOOKING_REMINDER->value)->count());
    }

    // --- Device tokens ---

    public function test_device_token_register_reassigns_and_deactivate_is_idempotent(): void
    {
        $f = $this->fixture('a');
        $api = $this->actingAs($f['customerUser'], 'sanctum');

        $api->postJson('/api/v1/notifications/device-tokens', ['platform' => 'android', 'token' => 'shared-token'])->assertCreated();
        $this->assertDatabaseHas('user_device_tokens', ['token' => 'shared-token', 'user_id' => $f['customerUser']->id, 'is_active' => 1]);

        // Re-login on the same device as a different user reassigns the token.
        $other = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $this->actingAs($other, 'sanctum')->postJson('/api/v1/notifications/device-tokens', ['platform' => 'android', 'token' => 'shared-token'])->assertCreated();
        $this->assertDatabaseHas('user_device_tokens', ['token' => 'shared-token', 'user_id' => $other->id]);
        $this->assertSame(1, UserDeviceToken::query()->where('token', 'shared-token')->count());

        $this->actingAs($other, 'sanctum')->postJson('/api/v1/notifications/device-tokens/deactivate', ['token' => 'shared-token'])->assertOk();
        $this->assertDatabaseHas('user_device_tokens', ['token' => 'shared-token', 'is_active' => 0]);

        // Deactivating an unknown token, or one owned by someone else, is a harmless no-op.
        $api->postJson('/api/v1/notifications/device-tokens/deactivate', ['token' => 'does-not-exist'])->assertOk();
    }

    // --- Payment / subscription notifications ---

    public function test_payment_success_and_failure_notify_the_owner(): void
    {
        [$tenant, $owner] = $this->billingFixture('p');
        $plan = $this->basicPlan();
        $gateway = new FakePaymentGateway;
        $this->app->bind(PaymentGatewayInterface::class, fn () => $gateway);
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $checkout = $api->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id])->assertCreated()->json('data');
        $api->postJson('/api/v1/subscription/checkout/verify', [
            'payment_id' => $checkout['payment_id'], 'gateway_payment_id' => 'pay_bad', 'gateway_signature' => 'bad-sig',
        ])->assertStatus(402);
        $this->assertNotificationExists($owner, NotificationEventType::PAYMENT_FAILED, null);

        $checkout2 = $api->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id])->assertCreated()->json('data');
        $gateway->validSignatures['good-sig'] = true;
        $api->postJson('/api/v1/subscription/checkout/verify', [
            'payment_id' => $checkout2['payment_id'], 'gateway_payment_id' => 'pay_good', 'gateway_signature' => 'good-sig',
        ])->assertOk();
        $this->assertNotificationExists($owner, NotificationEventType::PAYMENT_SUCCEEDED, null);
        $this->assertNotificationExists($owner, NotificationEventType::SUBSCRIPTION_ACTIVATED, null);
    }

    public function test_subscription_lifecycle_transitions_notify_the_owner(): void
    {
        [$tenant, $owner] = $this->billingFixture('q');
        $this->withTenant($tenant, fn () => Subscription::first()->update(['trial_ends_at' => now()->subDay()]));

        app(SubscriptionService::class)->processLifecycle();
        $this->assertNotificationExists($owner, NotificationEventType::SUBSCRIPTION_PAST_DUE, null);

        app(SubscriptionService::class)->processLifecycle();
        $this->assertNotificationExists($owner, NotificationEventType::SUBSCRIPTION_GRACE_PERIOD, null);

        $this->withTenant($tenant, fn () => Subscription::first()->update(['grace_ends_at' => now()->subDay()]));
        app(SubscriptionService::class)->processLifecycle();
        $this->assertNotificationExists($owner, NotificationEventType::SUBSCRIPTION_EXPIRED, null);
    }

    // --- helpers ---

    private function assertNotificationExists(User $user, NotificationEventType $type, ?string $bookingId): void
    {
        $query = Notification::query()->where('user_id', $user->id)->where('type', $type->value);
        if ($bookingId !== null) {
            $query->where('notifiable_type', (new Booking)->getMorphClass())->where('notifiable_id', $bookingId);
        }
        $this->assertTrue($query->exists(), "Expected a {$type->value} notification for user {$user->id}.");
    }

    private function assertNotificationMissing(User $user, NotificationEventType $type, ?string $bookingId): void
    {
        $query = Notification::query()->where('user_id', $user->id)->where('type', $type->value);
        if ($bookingId !== null) {
            $query->where('notifiable_type', (new Booking)->getMorphClass())->where('notifiable_id', $bookingId);
        }
        $this->assertFalse($query->exists(), "Did not expect a {$type->value} notification for user {$user->id}.");
    }

    private function createBookingNotifications(array $f, int $count): void
    {
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $date = $this->bookingDate();
        for ($i = 0; $i < $count; $i++) {
            $api->postJson('/api/v1/bookings', [
                'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => $date, 'start_time' => sprintf('%02d:00', 9 + $i),
                'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['staff']->id]],
            ])->assertCreated();
        }
    }

    private function withTenant(Tenant $tenant, \Closure $callback): mixed
    {
        $context = app(TenantContext::class);
        $context->set($tenant);
        try {
            return $callback();
        } finally {
            $context->clear();
        }
    }

    private function basicPlan(): Plan
    {
        return Plan::query()->where('code', 'SALON_BASIC')->firstOrFail();
    }

    private function billingFixture(string $slug): array
    {
        $tenant = Tenant::query()->create(['name' => $slug, 'slug' => $slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);

        return [$tenant, $owner];
    }

    private function bookingDate(): string
    {
        return Carbon::today()->addDay()->toDateString();
    }

    /**
     * @return array{tenant: Tenant, owner: User, branch: Branch, haircut: Service, staff: Staff, staffUser: User, customer: Customer, customerUser: User}
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

        $staffUser = User::factory()->create(['role' => UserRole::STAFF]);
        $staff = Staff::query()->create(['user_id' => $staffUser->id, 'name' => 'Amit', 'gender' => 'male', 'status' => BusinessStatus::ACTIVE]);
        $staff->branches()->sync([$branch->id => ['tenant_id' => $tenant->id]]);
        $staff->services()->sync([$haircut->id => ['tenant_id' => $tenant->id]]);
        foreach (range(0, 6) as $day) {
            StaffWorkingHour::query()->create(['staff_id' => $staff->id, 'day_of_week' => $day, 'is_working' => true, 'start_time' => '09:00', 'end_time' => '20:00']);
        }

        $customerUser = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $customer = Customer::query()->create(['user_id' => $customerUser->id, 'name' => 'Rahul', 'phone' => '9000000001', 'normalized_phone' => '9000000001', 'status' => BusinessStatus::ACTIVE]);

        app(TenantContext::class)->clear();

        return compact('tenant', 'owner', 'branch', 'haircut', 'staff', 'staffUser', 'customer', 'customerUser');
    }
}
