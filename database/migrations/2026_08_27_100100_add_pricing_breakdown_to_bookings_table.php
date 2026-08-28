<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Additive only — every existing column (including `discount`, which
     * Phase 6's Flutter Booking model already parses) keeps its exact
     * existing meaning: `discount` remains the single combined discount
     * total (coupon + membership + loyalty), so an existing booking created
     * before Phase 12 renders identically. The new columns below are the
     * *breakdown* behind that total, plus the immutable historical
     * references — see "Booking snapshot" in
     * LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md: once a booking is created,
     * later changes to a coupon/membership plan must never alter it.
     */
    public function up(): void
    {
        Schema::table('bookings', function (Blueprint $table): void {
            $table->foreignUlid('coupon_id')->nullable()->after('total')->constrained()->nullOnDelete();
            $table->string('coupon_code', 32)->nullable()->after('coupon_id');
            $table->decimal('coupon_discount', 12, 2)->default(0)->after('coupon_code');
            $table->foreignUlid('customer_membership_id')->nullable()->after('coupon_discount')->constrained()->nullOnDelete();
            $table->decimal('membership_discount', 12, 2)->default(0)->after('customer_membership_id');
            $table->unsignedInteger('loyalty_points_redeemed')->default(0)->after('membership_discount');
            $table->decimal('loyalty_discount', 12, 2)->default(0)->after('loyalty_points_redeemed');
            // Filled in when the booking completes and loyalty points are
            // earned from it — 0 if loyalty is disabled or the booking never
            // reached COMPLETED. See LoyaltyService::earnForBooking().
            $table->unsignedInteger('loyalty_points_earned')->default(0)->after('loyalty_discount');
            $table->index(['tenant_id', 'coupon_id']);
        });
    }

    public function down(): void
    {
        Schema::table('bookings', function (Blueprint $table): void {
            $table->dropForeign(['customer_membership_id']);
            $table->dropForeign(['coupon_id']);
            $table->dropColumn([
                'coupon_id', 'coupon_code', 'coupon_discount', 'customer_membership_id',
                'membership_discount', 'loyalty_points_redeemed', 'loyalty_discount', 'loyalty_points_earned',
            ]);
        });
    }
};
