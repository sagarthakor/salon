<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Phase 13 (Reports + Analytics) indexes — purely additive, no column or
 * data changes. Each index targets a query pattern introduced by
 * app/Services/Reports/* that the Phase 1–12 indexes don't already cover:
 *
 *   - booking_items.service_id: ServiceReport/RevenueReport group by
 *     bi.service_id (staff_id was already indexed via
 *     [tenant_id, staff_id] from the booking-engine migration).
 *   - customer_profiles(tenant_id, created_at): CustomerReport's "new
 *     customers" filter and growth series both range-scan created_at.
 *   - coupon_usages(tenant_id, used_at): CouponReport's date-range filter —
 *     the ledger's primary time dimension.
 *   - customer_memberships(tenant_id, starts_at): MembershipReport ranges
 *     over starts_at (the purchase/grant date), distinct from the
 *     tenant_id/status/expires_at index already covering the active-
 *     membership lookups.
 *   - loyalty_transactions(tenant_id, created_at) and (tenant_id, type):
 *     LoyaltyReport's date-range filter plus its per-type ledger sums.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('booking_items', function (Blueprint $table): void {
            $table->index(['tenant_id', 'service_id']);
        });

        Schema::table('customer_profiles', function (Blueprint $table): void {
            $table->index(['tenant_id', 'created_at']);
        });

        Schema::table('coupon_usages', function (Blueprint $table): void {
            $table->index(['tenant_id', 'used_at']);
        });

        Schema::table('customer_memberships', function (Blueprint $table): void {
            $table->index(['tenant_id', 'starts_at']);
        });

        Schema::table('loyalty_transactions', function (Blueprint $table): void {
            $table->index(['tenant_id', 'created_at']);
            $table->index(['tenant_id', 'type']);
        });
    }

    public function down(): void
    {
        Schema::table('booking_items', function (Blueprint $table): void {
            $table->dropIndex(['tenant_id', 'service_id']);
        });

        Schema::table('customer_profiles', function (Blueprint $table): void {
            $table->dropIndex(['tenant_id', 'created_at']);
        });

        Schema::table('coupon_usages', function (Blueprint $table): void {
            $table->dropIndex(['tenant_id', 'used_at']);
        });

        Schema::table('customer_memberships', function (Blueprint $table): void {
            $table->dropIndex(['tenant_id', 'starts_at']);
        });

        Schema::table('loyalty_transactions', function (Blueprint $table): void {
            $table->dropIndex(['tenant_id', 'created_at']);
            $table->dropIndex(['tenant_id', 'type']);
        });
    }
};
