<?php

namespace Tests\Feature;

use App\Enums\SubscriptionStatus;
use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Payment;
use App\Models\Plan;
use App\Models\Subscription;
use App\Models\Tenant;
use App\Models\User;
use App\Models\WebhookEvent;
use App\Services\Billing\Gateways\FakePaymentGateway;
use App\Services\Billing\Gateways\PaymentGatewayInterface;
use App\Services\Billing\SubscriptionService;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class BillingApiTest extends TestCase
{
    use RefreshDatabase;

    private FakePaymentGateway $gateway;

    protected function setUp(): void
    {
        parent::setUp();
        $this->gateway = new FakePaymentGateway;
        $this->app->bind(PaymentGatewayInterface::class, fn () => $this->gateway);
    }

    // --- Tenant auto-trial (Tenant::booted) ---

    public function test_a_new_tenant_automatically_starts_a_trial_on_the_default_active_plan(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->getJson('/api/v1/subscription')
            ->assertOk()
            ->assertJsonPath('data.status', 'trialing')
            ->assertJsonPath('data.plan.code', 'SALON_BASIC')
            ->assertJsonPath('data.plan.amount', '500.00')
            ->assertJsonPath('data.plan.currency', 'INR');
    }

    // --- Plan management ---

    public function test_super_admin_can_manage_plans_but_tenant_owner_cannot(): void
    {
        $admin = User::factory()->create(['role' => UserRole::SUPER_ADMIN]);
        $api = $this->actingAs($admin, 'sanctum');

        $plan = $api->postJson('/api/v1/platform/plans', [
            'name' => 'Salon Pro', 'code' => 'SALON_PRO', 'amount' => 999, 'currency' => 'INR',
            'billing_interval' => 'month', 'billing_interval_count' => 1, 'trial_days' => 7,
        ])->assertCreated()->assertJsonPath('data.amount', '999.00')->json('data');

        $api->patchJson("/api/v1/platform/plans/{$plan['id']}", [
            'name' => 'Salon Pro', 'code' => 'SALON_PRO', 'amount' => 1099, 'currency' => 'INR',
            'billing_interval' => 'month', 'billing_interval_count' => 1, 'trial_days' => 7,
        ])->assertOk()->assertJsonPath('data.amount', '1099.00');

        $api->postJson("/api/v1/platform/plans/{$plan['id']}/deactivate")->assertOk()->assertJsonPath('data.is_active', false);
        $api->getJson('/api/v1/platform/plans')->assertOk()->assertJsonCount(2, 'data');
        $api->postJson("/api/v1/platform/plans/{$plan['id']}/activate")->assertOk()->assertJsonPath('data.is_active', true);

        [$tenant, $owner] = $this->fixture('a');
        $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug)
            ->postJson('/api/v1/platform/plans', ['name' => 'x', 'code' => 'X', 'amount' => 1, 'currency' => 'INR', 'billing_interval' => 'month', 'billing_interval_count' => 1, 'trial_days' => 0])
            ->assertForbidden();
    }

    public function test_only_active_plans_appear_in_the_tenant_facing_plan_list(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $admin = User::factory()->create(['role' => UserRole::SUPER_ADMIN]);
        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/platform/plans', [
            'name' => 'Inactive Plan', 'code' => 'INACTIVE_ONE', 'amount' => 1, 'currency' => 'INR',
            'billing_interval' => 'month', 'billing_interval_count' => 1, 'trial_days' => 0, 'is_active' => false,
        ])->assertCreated();

        $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug)
            ->getJson('/api/v1/subscription/plans')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.code', 'SALON_BASIC');
    }

    // --- Pricing / amount tampering ---

    public function test_checkout_always_uses_the_server_side_plan_price_and_ignores_a_client_supplied_amount(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $plan = $this->basicPlan();
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id, 'amount' => 1, 'price' => 1, 'currency' => 'USD'])
            ->assertCreated()
            ->assertJsonPath('data.amount', '500.00')
            ->assertJsonPath('data.currency', 'INR');

        $this->assertSame(500.0, $this->gateway->createdOrders[0]['amount']);
    }

    // --- Checkout + verification happy path ---

    public function test_checkout_then_verify_with_a_valid_signature_activates_the_subscription_and_pays_the_invoice(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $plan = $this->basicPlan();
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $checkout = $api->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id])->assertCreated()->json('data');
        $signature = 'valid-sig';
        $this->gateway->validSignatures[$signature] = true;

        $api->postJson('/api/v1/subscription/checkout/verify', [
            'payment_id' => $checkout['payment_id'],
            'gateway_payment_id' => 'pay_test_1',
            'gateway_signature' => $signature,
        ])->assertOk()
            ->assertJsonPath('data.status', 'active')
            ->assertJsonPath('data.plan.code', 'SALON_BASIC');

        $this->assertDatabaseHas('payments', ['id' => $checkout['payment_id'], 'status' => 'paid']);

        $invoices = $api->getJson('/api/v1/subscription/invoices')->assertOk()->json('data');
        $this->assertSame('paid', $invoices[0]['status']);
        $this->assertSame('500.00', $invoices[0]['total']);
        $this->assertStringStartsWith('INV-', $invoices[0]['invoice_number']);

        // Idempotent: verifying again with the same (now-consumed) payment
        // does not fail, double-charge, or re-activate from scratch.
        $api->postJson('/api/v1/subscription/checkout/verify', [
            'payment_id' => $checkout['payment_id'],
            'gateway_payment_id' => 'pay_test_1',
            'gateway_signature' => $signature,
        ])->assertOk()->assertJsonPath('data.status', 'active');
    }

    public function test_verify_with_an_invalid_signature_fails_the_payment_and_moves_the_subscription_to_past_due(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $plan = $this->basicPlan();
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $checkout = $api->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id])->assertCreated()->json('data');

        $api->postJson('/api/v1/subscription/checkout/verify', [
            'payment_id' => $checkout['payment_id'],
            'gateway_payment_id' => 'pay_bad',
            'gateway_signature' => 'not-a-registered-signature',
        ])->assertStatus(402);

        $this->assertDatabaseHas('payments', ['id' => $checkout['payment_id'], 'status' => 'failed']);
        $api->getJson('/api/v1/subscription')->assertOk()->assertJsonPath('data.status', 'past_due');
    }

    public function test_checkout_idempotency_key_returns_the_same_payment_instead_of_creating_a_second_order(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $plan = $this->basicPlan();
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $key = 'retry-key-123';
        $first = $api->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id], ['Idempotency-Key' => $key])->assertCreated()->json('data');
        $second = $api->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id], ['Idempotency-Key' => $key])->assertCreated()->json('data');

        $this->assertSame($first['payment_id'], $second['payment_id']);
        $this->assertCount(1, $this->gateway->createdOrders);
        $this->assertDatabaseCount('payments', 1);
    }

    /**
     * Regression test for Phase 14: the gateway call in initiateCheckout()
     * now happens outside the DB transaction that creates the invoice/
     * payment rows (so a slow/unresponsive gateway never holds a database
     * lock open — see PERFORMANCE_HARDENING.md). That means a failed
     * gateway call no longer rolls back the Payment row it already
     * committed; a retry with the same Idempotency-Key must reuse that
     * exact pending row (and its invoice) rather than accumulating a new
     * invoice on every failed attempt.
     */
    public function test_checkout_retry_after_a_gateway_failure_reuses_the_same_pending_payment_and_invoice(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $plan = $this->basicPlan();
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $key = 'retry-after-failure-key';
        $this->gateway->failNextCreateOrder = true;
        $api->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id], ['Idempotency-Key' => $key])->assertStatus(500);

        $this->assertDatabaseCount('payments', 1);
        $this->assertDatabaseCount('invoices', 1);
        $pending = Payment::withoutGlobalScope('tenant')->where('idempotency_key', $key)->first();
        $this->assertSame('pending', $pending->status->value);
        $this->assertNull($pending->gateway_order_id);

        $retry = $api->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id], ['Idempotency-Key' => $key])->assertCreated()->json('data');

        $this->assertSame($pending->id, $retry['payment_id']);
        $this->assertNotNull($retry['gateway_order_id']);
        $this->assertDatabaseCount('payments', 1);
        $this->assertDatabaseCount('invoices', 1);
        $this->assertCount(1, $this->gateway->createdOrders);
    }

    /**
     * Regression test for Phase 14: checkout/verify/renew previously had no
     * application-level rate limit at all beyond login/register. See
     * "Rate limiting" in SECURITY_HARDENING.md.
     */
    public function test_checkout_endpoint_is_rate_limited(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $plan = $this->basicPlan();
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        for ($i = 0; $i < 10; $i++) {
            $api->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id])->assertCreated();
        }
        $api->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id])->assertStatus(429);
    }

    // --- Webhooks ---

    public function test_webhook_with_a_valid_signature_activates_the_subscription_and_a_duplicate_delivery_is_a_no_op(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $plan = $this->basicPlan();
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $checkout = $api->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id])->assertCreated()->json('data');

        $signature = 'webhook-valid';
        $this->gateway->validSignatures[$signature] = true;
        $payload = [
            'event' => 'payment.captured',
            'payload' => ['payment' => ['entity' => ['id' => 'pay_webhook_1', 'order_id' => $checkout['gateway_order_id']]]],
        ];
        $headers = ['X-Razorpay-Signature' => $signature, 'X-Razorpay-Event-Id' => 'evt_1'];

        $this->postJson('/api/v1/webhooks/razorpay', $payload, $headers)->assertOk();
        $this->assertDatabaseHas('payments', ['id' => $checkout['payment_id'], 'status' => 'paid']);
        $this->assertDatabaseCount('webhook_events', 1);

        // Duplicate delivery of the same event id — must not double-process.
        $this->postJson('/api/v1/webhooks/razorpay', $payload, $headers)->assertOk();
        $this->assertDatabaseCount('webhook_events', 1);
        $this->assertDatabaseCount('payments', 1);
        $api->getJson('/api/v1/subscription/invoices')->assertJsonCount(1, 'data');
    }

    /**
     * Regression test for a real bug this phase found: `alreadyProcessed`
     * used to check only whether a `webhook_events` row existed, not
     * whether it had actually finished processing. A delivery whose
     * `process()` call throws (e.g. a transient DB error) left a row with
     * `processed_at` still null — and a Razorpay retry of that exact event
     * would then be silently swallowed as "already processed" forever,
     * even though the payment never actually got applied. Fixed by keying
     * "already handled" off `processed_at`, not row existence — see
     * PaymentWebhookController and "Webhook idempotency" in
     * SECURITY_HARDENING.md.
     */
    public function test_webhook_retries_a_previously_unprocessed_event_row_instead_of_treating_it_as_a_duplicate(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $plan = $this->basicPlan();
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $checkout = $api->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id])->assertCreated()->json('data');

        // Simulates a prior delivery that recorded the event row but crashed
        // before `process()` completed — `processed_at` is still null.
        WebhookEvent::query()->create([
            'gateway' => 'fake',
            'gateway_event_id' => 'evt_crashed',
            'event_type' => 'payment.captured',
            'payload' => [],
        ]);

        $signature = 'webhook-retry-valid';
        $this->gateway->validSignatures[$signature] = true;
        $payload = [
            'event' => 'payment.captured',
            'payload' => ['payment' => ['entity' => ['id' => 'pay_retry_1', 'order_id' => $checkout['gateway_order_id']]]],
        ];

        $this->postJson('/api/v1/webhooks/razorpay', $payload, ['X-Razorpay-Signature' => $signature, 'X-Razorpay-Event-Id' => 'evt_crashed'])
            ->assertOk()->assertJsonPath('message', 'Webhook processed.');

        $this->assertDatabaseHas('payments', ['id' => $checkout['payment_id'], 'status' => 'paid']);
        $this->assertDatabaseCount('webhook_events', 1);
        $this->assertNotNull(WebhookEvent::query()->where('gateway_event_id', 'evt_crashed')->first()->processed_at);

        // Now that it's genuinely processed, a true duplicate delivery is
        // still correctly a no-op.
        $this->postJson('/api/v1/webhooks/razorpay', $payload, ['X-Razorpay-Signature' => $signature, 'X-Razorpay-Event-Id' => 'evt_crashed'])
            ->assertOk()->assertJsonPath('message', 'Event already processed.');
        $this->assertDatabaseCount('webhook_events', 1);
    }

    public function test_webhook_with_an_invalid_signature_is_rejected_and_never_processed(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $plan = $this->basicPlan();
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $checkout = $api->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id])->assertCreated()->json('data');

        $payload = [
            'event' => 'payment.captured',
            'payload' => ['payment' => ['entity' => ['id' => 'pay_x', 'order_id' => $checkout['gateway_order_id']]]],
        ];

        $this->postJson('/api/v1/webhooks/razorpay', $payload, ['X-Razorpay-Signature' => 'tampered', 'X-Razorpay-Event-Id' => 'evt_bad'])
            ->assertStatus(400);

        $this->assertDatabaseCount('webhook_events', 0);
        $this->assertDatabaseHas('payments', ['id' => $checkout['payment_id'], 'status' => 'pending']);
    }

    public function test_webhook_payment_failed_event_marks_payment_failed_and_subscription_past_due(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $plan = $this->basicPlan();
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $checkout = $api->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id])->assertCreated()->json('data');

        $signature = 'webhook-fail-sig';
        $this->gateway->validSignatures[$signature] = true;
        $payload = [
            'event' => 'payment.failed',
            'payload' => ['payment' => ['entity' => ['id' => 'pay_failed_1', 'order_id' => $checkout['gateway_order_id'], 'error_description' => 'Card declined']]],
        ];

        $this->postJson('/api/v1/webhooks/razorpay', $payload, ['X-Razorpay-Signature' => $signature, 'X-Razorpay-Event-Id' => 'evt_fail_1'])->assertOk();

        $this->assertDatabaseHas('payments', ['id' => $checkout['payment_id'], 'status' => 'failed', 'failure_reason' => 'Card declined']);
        $api->getJson('/api/v1/subscription')->assertJsonPath('data.status', 'past_due');
    }

    // --- Invoice historical pricing ---

    public function test_a_later_plan_price_change_never_alters_an_already_issued_invoice(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $plan = $this->basicPlan();
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $checkout = $api->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id])->assertCreated()->json('data');
        $signature = 'history-sig';
        $this->gateway->validSignatures[$signature] = true;
        $api->postJson('/api/v1/subscription/checkout/verify', ['payment_id' => $checkout['payment_id'], 'gateway_payment_id' => 'pay_h', 'gateway_signature' => $signature])->assertOk();

        $api->getJson('/api/v1/subscription/invoices')->assertJsonPath('data.0.total', '500.00');

        $admin = User::factory()->create(['role' => UserRole::SUPER_ADMIN]);
        $this->actingAs($admin, 'sanctum')->patchJson("/api/v1/platform/plans/{$plan->id}", [
            'name' => $plan->name, 'code' => $plan->code, 'amount' => 600, 'currency' => 'INR',
            'billing_interval' => 'month', 'billing_interval_count' => 1, 'trial_days' => 14,
        ])->assertOk();

        $api->getJson('/api/v1/subscription/invoices')->assertJsonPath('data.0.total', '500.00');
    }

    // --- Subscription lifecycle (time-based transitions) ---

    public function test_lifecycle_moves_an_expired_trial_through_grace_period_to_expired(): void
    {
        [$tenant] = $this->fixture('a');
        $service = app(SubscriptionService::class);

        // One scheduler tick fully settles a trial that expired one or more
        // days ago: TRIALING -> PAST_DUE -> GRACE_PERIOD within this single
        // `processLifecycle()` call (each pass sweeps every subscription
        // eligible at that point, including ones just transitioned earlier
        // in the same pass) — see SAAS_BILLING_ARCHITECTURE.md.
        $this->withTenant($tenant, fn () => Subscription::first()->update(['trial_ends_at' => now()->subDay()]));
        $service->processLifecycle();
        $graceEndsAt = $this->withTenant($tenant, function () {
            $sub = Subscription::first();
            $this->assertSame('grace_period', $sub->status->value);

            return $sub->grace_ends_at;
        });
        $this->assertNotNull($graceEndsAt);

        $this->withTenant($tenant, fn () => Subscription::first()->update(['grace_ends_at' => now()->subDay()]));
        $service->processLifecycle();
        $this->assertSame('expired', $this->withTenant($tenant, fn () => Subscription::first()->status->value));
    }

    public function test_a_failed_payment_stays_past_due_until_the_next_scheduler_tick_promotes_it_to_grace_period(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $plan = $this->basicPlan();
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $checkout = $api->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id])->assertCreated()->json('data');

        $api->postJson('/api/v1/subscription/checkout/verify', [
            'payment_id' => $checkout['payment_id'],
            'gateway_payment_id' => 'pay_bad',
            'gateway_signature' => 'invalid',
        ])->assertStatus(402);

        $this->assertSame('past_due', $this->withTenant($tenant, fn () => Subscription::first()->status->value));

        app(SubscriptionService::class)->processLifecycle();
        $this->assertSame('grace_period', $this->withTenant($tenant, fn () => Subscription::first()->status->value));
    }

    public function test_cancel_at_period_end_keeps_access_until_period_end_then_becomes_cancelled(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $this->withTenant($tenant, function (): void {
            $sub = Subscription::first();
            app(SubscriptionService::class)->activate($sub, $sub->plan, CarbonImmutable::now());
        });

        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $api->postJson('/api/v1/subscription/cancel')
            ->assertOk()
            ->assertJsonPath('data.cancel_at_period_end', true)
            ->assertJsonPath('data.status', 'active');

        // still active now — business access continues
        $api->getJson('/api/v1/branches')->assertOk();

        $this->withTenant($tenant, fn () => Subscription::first()->update(['current_period_end' => now()->subDay()]));
        app(SubscriptionService::class)->processLifecycle();

        $this->assertSame('cancelled', $this->withTenant($tenant, fn () => Subscription::first()->status->value));
    }

    // --- Subscription access control (EnsureActiveSubscription) ---

    public function test_expired_subscription_blocks_business_routes_but_never_billing_routes(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $this->withTenant($tenant, fn () => Subscription::first()->update(['status' => SubscriptionStatus::EXPIRED]));
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->getJson('/api/v1/branches')->assertStatus(402);
        $api->getJson('/api/v1/dashboard/summary')->assertStatus(402);

        $api->getJson('/api/v1/subscription')->assertOk();
        $api->getJson('/api/v1/subscription/plans')->assertOk();
        $api->getJson('/api/v1/subscription/payments')->assertOk();
        $api->getJson('/api/v1/subscription/invoices')->assertOk();
        $api->postJson('/api/v1/subscription/renew')->assertCreated();
    }

    public function test_trialing_and_grace_period_subscriptions_keep_normal_business_access(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $api->getJson('/api/v1/branches')->assertOk();

        $this->withTenant($tenant, fn () => Subscription::first()->update(['status' => SubscriptionStatus::GRACE_PERIOD, 'grace_ends_at' => now()->addDay()]));
        $api->getJson('/api/v1/branches')->assertOk();
    }

    // --- Authorization ---

    public function test_customer_cannot_access_any_subscription_endpoint(): void
    {
        [$tenant] = $this->fixture('a');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $this->actingAs($customer, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug)
            ->getJson('/api/v1/subscription')->assertForbidden();
    }

    public function test_staff_can_view_billing_but_cannot_checkout_renew_or_cancel(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $staffUser = User::factory()->create(['role' => UserRole::STAFF]);
        $tenant->users()->attach($staffUser, ['role' => TenantMembershipRole::STAFF->value]);
        $staffApi = $this->actingAs($staffUser, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $staffApi->getJson('/api/v1/subscription')->assertOk();
        $staffApi->getJson('/api/v1/subscription/payments')->assertOk();
        $staffApi->getJson('/api/v1/subscription/invoices')->assertOk();

        $plan = $this->basicPlan();
        $staffApi->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id])->assertForbidden();
        $staffApi->postJson('/api/v1/subscription/renew')->assertForbidden();
        $staffApi->postJson('/api/v1/subscription/cancel')->assertForbidden();
    }

    // --- Tenant isolation ---

    public function test_a_tenant_cannot_verify_or_list_another_tenants_payments_or_invoices(): void
    {
        [$tenantA, $ownerA] = $this->fixture('a');
        [$tenantB, $ownerB] = $this->fixture('b');
        $plan = $this->basicPlan();
        $apiA = $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug);
        $checkoutA = $apiA->postJson('/api/v1/subscription/checkout', ['plan_id' => $plan->id])->assertCreated()->json('data');

        $apiB = $this->actingAs($ownerB, 'sanctum')->withHeader('X-Tenant-Slug', $tenantB->slug);
        $apiB->postJson('/api/v1/subscription/checkout/verify', [
            'payment_id' => $checkoutA['payment_id'],
            'gateway_payment_id' => 'pay_x',
            'gateway_signature' => 'y',
        ])->assertNotFound();

        $apiB->getJson('/api/v1/subscription/payments')->assertOk()->assertJsonCount(0, 'data');
        $apiB->getJson('/api/v1/subscription/invoices')->assertOk()->assertJsonCount(0, 'data');

        // tenant B's own subscription is entirely unaffected by tenant A's checkout
        $apiB->getJson('/api/v1/subscription')->assertJsonPath('data.status', 'trialing');
    }

    private function basicPlan(): Plan
    {
        return Plan::query()->where('code', 'SALON_BASIC')->firstOrFail();
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

    private function fixture(string $slug): array
    {
        $tenant = Tenant::query()->create(['name' => $slug, 'slug' => $slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);

        return [$tenant, $owner];
    }
}
