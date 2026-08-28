<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        // Platform-global, never tenant-scoped — every salon subscribes to one
        // of these. Deliberately not a `BelongsToTenant` model.
        Schema::create('plans', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->string('name');
            $table->string('code')->unique();
            $table->text('description')->nullable();
            $table->decimal('amount', 12, 2);
            $table->string('currency', 3)->default('INR');
            $table->string('billing_interval', 8)->default('month');
            $table->unsignedInteger('billing_interval_count')->default(1);
            $table->unsignedInteger('trial_days')->default(0);
            $table->boolean('is_active')->default(true);
            $table->json('features')->nullable();
            $table->timestamps();
            $table->index(['is_active']);
        });

        // One row per tenant (unique tenant_id) — the subscription persists
        // across its whole lifecycle (trial → active → renewals → cancel);
        // renewals extend the same row rather than creating a new one. See
        // SAAS_BILLING_ARCHITECTURE.md for the full state machine.
        Schema::create('subscriptions', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('tenant_id')->unique()->constrained()->cascadeOnDelete();
            $table->foreignUlid('plan_id')->constrained()->restrictOnDelete();
            $table->string('status', 16)->default('trialing');
            $table->timestamp('trial_starts_at')->nullable();
            $table->timestamp('trial_ends_at')->nullable();
            $table->timestamp('starts_at')->nullable();
            $table->timestamp('current_period_start')->nullable();
            $table->timestamp('current_period_end')->nullable();
            $table->boolean('cancel_at_period_end')->default(false);
            $table->timestamp('cancelled_at')->nullable();
            // Not in the phase brief's suggested column list — added because
            // PAST_DUE/GRACE_PERIOD need a concrete end-of-grace instant to
            // transition on; see SAAS_BILLING_ARCHITECTURE.md.
            $table->timestamp('grace_ends_at')->nullable();
            $table->timestamp('ended_at')->nullable();
            $table->string('gateway', 32)->nullable();
            $table->string('gateway_customer_id')->nullable();
            $table->string('gateway_subscription_id')->nullable();
            $table->timestamps();
            $table->index(['status']);
            $table->index(['gateway_subscription_id']);
        });

        Schema::create('invoices', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('subscription_id')->constrained()->restrictOnDelete();
            // Atomically assigned by InvoiceNumberGenerator (a locked counter
            // row) — never random, never just a display formatting of the
            // ulid. Format: INV-{year}-{6-digit sequence}.
            $table->string('invoice_number')->unique();
            $table->decimal('subtotal', 12, 2);
            $table->decimal('tax', 12, 2)->default(0);
            $table->decimal('total', 12, 2);
            $table->string('currency', 3)->default('INR');
            $table->string('status', 16)->default('draft');
            $table->timestamp('billing_period_start')->nullable();
            $table->timestamp('billing_period_end')->nullable();
            $table->timestamp('issued_at')->nullable();
            $table->timestamp('paid_at')->nullable();
            $table->timestamp('due_at')->nullable();
            $table->timestamps();
            $table->index(['tenant_id', 'status']);
            $table->index(['subscription_id']);
        });

        // Line items snapshot the plan's name/price *at the time of billing*
        // (`description`, `unit_amount`) — never a live join to `plans`, so a
        // later plan price change can never alter a historical invoice.
        Schema::create('invoice_items', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('invoice_id')->constrained()->cascadeOnDelete();
            $table->string('description');
            $table->unsignedInteger('quantity')->default(1);
            $table->decimal('unit_amount', 12, 2);
            $table->decimal('amount', 12, 2);
            $table->json('metadata')->nullable();
            $table->timestamps();
            $table->index(['tenant_id', 'invoice_id']);
        });

        Schema::create('payments', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('subscription_id')->constrained()->restrictOnDelete();
            $table->foreignUlid('invoice_id')->nullable()->constrained()->nullOnDelete();
            $table->decimal('amount', 12, 2);
            $table->string('currency', 3)->default('INR');
            $table->string('status', 16)->default('pending');
            $table->string('payment_method')->nullable();
            $table->string('gateway', 32);
            $table->string('gateway_payment_id')->nullable();
            $table->string('gateway_order_id')->nullable();
            $table->string('gateway_signature')->nullable();
            $table->timestamp('paid_at')->nullable();
            $table->timestamp('failed_at')->nullable();
            $table->string('failure_reason')->nullable();
            $table->string('idempotency_key')->unique();
            $table->json('metadata')->nullable();
            $table->timestamps();
            $table->index(['tenant_id', 'status']);
            $table->index(['subscription_id']);
            $table->index(['gateway_payment_id']);
            $table->index(['gateway_order_id']);
        });

        // Platform-global (a webhook arrives with no authenticated tenant
        // session — see PaymentWebhookController) idempotency ledger. Unique
        // per (gateway, gateway_event_id) so a retried/duplicated webhook
        // delivery is a safe no-op.
        Schema::create('webhook_events', function (Blueprint $table): void {
            $table->id();
            $table->string('gateway', 32);
            $table->string('gateway_event_id');
            $table->string('event_type');
            $table->json('payload')->nullable();
            $table->timestamp('processed_at')->nullable();
            $table->timestamps();
            $table->unique(['gateway', 'gateway_event_id']);
        });

        // Backs InvoiceNumberGenerator's atomic sequence — a single locked
        // row rather than an auto-increment column, so the number can be
        // reserved inside the same DB transaction that creates the invoice.
        Schema::create('invoice_number_counters', function (Blueprint $table): void {
            $table->id();
            $table->unsignedBigInteger('next_number')->default(1);
        });
        DB::table('invoice_number_counters')->insert(['next_number' => 1]);

        // The default commercial plan (see SAAS_BILLING_ARCHITECTURE.md for
        // why this is seeded in the migration itself, not only in
        // DatabaseSeeder: every tenant — including ones created directly by
        // Phase 1–9 feature tests via Eloquent, never through a seeder — is
        // given a trial subscription against an active plan the instant it's
        // created (see Tenant::booted()), so a real plan row must exist in
        // every environment, migrations included).
        DB::table('plans')->insert([
            'id' => (string) Str::ulid(),
            'name' => 'Salon Basic',
            'code' => 'SALON_BASIC',
            'description' => 'The default Salon SaaS plan.',
            'amount' => 500.00,
            'currency' => 'INR',
            'billing_interval' => 'month',
            'billing_interval_count' => 1,
            'trial_days' => 14,
            'is_active' => true,
            'features' => null,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function down(): void
    {
        Schema::dropIfExists('invoice_number_counters');
        Schema::dropIfExists('webhook_events');
        Schema::dropIfExists('payments');
        Schema::dropIfExists('invoice_items');
        Schema::dropIfExists('invoices');
        Schema::dropIfExists('subscriptions');
        Schema::dropIfExists('plans');
    }
};
