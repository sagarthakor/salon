<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('coupons', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            // Always stored normalized (uppercased, trimmed) — see Coupon::normalizeCode().
            $table->string('code', 32);
            $table->string('name');
            $table->text('description')->nullable();
            $table->string('discount_type', 16);
            $table->decimal('discount_value', 12, 2);
            $table->decimal('minimum_booking_amount', 12, 2)->nullable();
            $table->decimal('maximum_discount_amount', 12, 2)->nullable();
            $table->timestamp('starts_at')->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->unsignedInteger('usage_limit')->nullable();
            $table->unsignedInteger('usage_limit_per_customer')->nullable();
            $table->unsignedInteger('usage_count')->default(0);
            $table->boolean('is_active')->default(true);
            $table->boolean('first_booking_only')->default(false);
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['tenant_id', 'code']);
            $table->index(['tenant_id', 'is_active']);
        });

        Schema::create('coupon_services', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('coupon_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('service_id')->constrained()->cascadeOnDelete();
            $table->timestamps();
            $table->unique(['coupon_id', 'service_id']);
        });

        Schema::create('coupon_categories', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('coupon_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('category_id')->constrained('service_categories')->cascadeOnDelete();
            $table->timestamps();
            $table->unique(['coupon_id', 'category_id']);
        });

        // Auditable usage ledger — never mutated/deleted; `coupons.usage_count`
        // is a denormalized counter kept in lockstep with this table inside
        // the same locked transaction (see CouponService::reserve()).
        Schema::create('coupon_usages', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('coupon_id')->constrained()->restrictOnDelete();
            $table->foreignUlid('customer_id')->constrained('customer_profiles')->restrictOnDelete();
            $table->foreignUlid('booking_id')->nullable()->constrained()->nullOnDelete();
            $table->decimal('discount_amount', 12, 2);
            $table->timestamp('used_at');
            $table->timestamps();
            $table->index(['tenant_id', 'coupon_id']);
            $table->index(['tenant_id', 'customer_id']);
            // One coupon usage per booking — a booking can only ever apply one
            // coupon (see stacking rules), so this also guards against a
            // double-submitted booking request double-consuming a usage slot.
            $table->unique(['coupon_id', 'booking_id']);
        });

        Schema::create('membership_plans', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('code', 32);
            $table->text('description')->nullable();
            $table->decimal('price', 12, 2);
            $table->string('currency', 3)->default('INR');
            $table->unsignedInteger('duration_days');
            $table->string('discount_type', 16);
            $table->decimal('discount_value', 12, 2);
            $table->decimal('maximum_discount_amount', 12, 2)->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['tenant_id', 'code']);
            $table->index(['tenant_id', 'is_active']);
        });

        Schema::create('membership_plan_services', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('membership_plan_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('service_id')->constrained()->cascadeOnDelete();
            $table->timestamps();
            $table->unique(['membership_plan_id', 'service_id']);
        });

        Schema::create('membership_plan_categories', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('membership_plan_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('category_id')->constrained('service_categories')->cascadeOnDelete();
            $table->timestamps();
            $table->unique(['membership_plan_id', 'category_id']);
        });

        // A new row per purchase/renewal — never overwritten, so a customer's
        // full membership history stays intact even after it expires or a new
        // one is purchased. See "Membership renewal" in the architecture doc.
        Schema::create('customer_memberships', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('customer_id')->constrained('customer_profiles')->cascadeOnDelete();
            $table->foreignUlid('membership_plan_id')->constrained()->restrictOnDelete();
            $table->string('status', 16)->default('active');
            $table->timestamp('starts_at');
            $table->timestamp('expires_at');
            $table->decimal('purchased_amount', 12, 2);
            $table->string('currency', 3)->default('INR');
            // 'purchase' (paid through membership_payments) or 'owner_grant'
            // (manually granted, no payment — see MembershipService::grant()).
            $table->string('source', 16)->default('purchase');
            $table->timestamps();
            $table->index(['tenant_id', 'customer_id', 'status']);
            $table->index(['tenant_id', 'status', 'expires_at']);
        });

        // Deliberately its own table, not a repurposed `payments` row: Phase
        // 10's `payments.subscription_id` is a required FK into the SaaS
        // `subscriptions` table — a completely different domain (owner pays
        // platform vs. customer pays salon; see "Subscription vs Membership"
        // in the architecture doc). Both still go through the exact same
        // `PaymentGatewayInterface` — no second gateway.
        Schema::create('membership_payments', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('customer_id')->constrained('customer_profiles')->restrictOnDelete();
            $table->foreignUlid('membership_plan_id')->constrained()->restrictOnDelete();
            $table->foreignUlid('customer_membership_id')->nullable()->constrained()->nullOnDelete();
            $table->decimal('amount', 12, 2);
            $table->string('currency', 3)->default('INR');
            $table->string('status', 16)->default('pending');
            $table->string('gateway', 32);
            $table->string('gateway_order_id')->nullable();
            $table->string('gateway_payment_id')->nullable();
            $table->string('gateway_signature')->nullable();
            $table->string('idempotency_key')->unique();
            $table->string('failure_reason')->nullable();
            $table->timestamp('paid_at')->nullable();
            $table->timestamp('failed_at')->nullable();
            $table->timestamps();
            $table->index(['tenant_id', 'customer_id']);
            $table->index(['gateway_order_id']);
        });

        Schema::create('loyalty_accounts', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('customer_id')->constrained('customer_profiles')->cascadeOnDelete();
            $table->unsignedInteger('balance')->default(0);
            $table->unsignedInteger('lifetime_earned')->default(0);
            $table->unsignedInteger('lifetime_redeemed')->default(0);
            $table->timestamps();
            $table->unique(['tenant_id', 'customer_id']);
        });

        // Immutable ledger — every balance-changing operation creates exactly
        // one row here; `loyalty_accounts.balance` is always derivable as the
        // running sum of `points` (kept denormalized for cheap reads, but
        // never mutated without a matching transaction row — see
        // LoyaltyService).
        Schema::create('loyalty_transactions', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('customer_id')->constrained('customer_profiles')->cascadeOnDelete();
            $table->foreignUlid('loyalty_account_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('booking_id')->nullable()->constrained()->nullOnDelete();
            $table->string('type', 16);
            // Signed delta actually applied to the balance (EARN/positive
            // ADJUSTMENT are +, REDEEM/EXPIRE/negative ADJUSTMENT are -).
            $table->integer('points');
            $table->unsignedInteger('balance_after');
            $table->text('description')->nullable();
            $table->string('reference_type', 32)->nullable();
            $table->string('reference_id')->nullable();
            $table->timestamps();
            $table->index(['tenant_id', 'customer_id']);
            $table->index(['loyalty_account_id']);
            // NULL booking_id rows (adjustments, expirations) are
            // unconstrained by a unique index in every supported driver —
            // this only ever deduplicates a *booking-linked* transaction
            // (e.g. at most one EARN per booking), which is exactly the
            // idempotency guarantee needed. See "Loyalty idempotency".
            $table->unique(['booking_id', 'type']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('loyalty_transactions');
        Schema::dropIfExists('loyalty_accounts');
        Schema::dropIfExists('membership_payments');
        Schema::dropIfExists('customer_memberships');
        Schema::dropIfExists('membership_plan_categories');
        Schema::dropIfExists('membership_plan_services');
        Schema::dropIfExists('membership_plans');
        Schema::dropIfExists('coupon_usages');
        Schema::dropIfExists('coupon_categories');
        Schema::dropIfExists('coupon_services');
        Schema::dropIfExists('coupons');
    }
};
