<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Phase 14 hardening — purely additive/corrective, no data changes.
 *
 * 1. `customer_memberships.customer_id`, `loyalty_accounts.customer_id`,
 *    `loyalty_transactions.customer_id`, and `loyalty_transactions.loyalty_account_id`
 *    were created with `cascadeOnDelete()`, inconsistent with every sibling
 *    financial/historical table in the same migration
 *    (`coupon_usages.customer_id`, `membership_payments.customer_id`,
 *    `bookings.customer_id` all use `restrictOnDelete()`). The app itself
 *    only ever soft-deletes a `Customer` (`Customer` uses `SoftDeletes`),
 *    so this cascade cannot fire through any current API path — but it is a
 *    real landmine: a future hard-delete of a customer row (an admin
 *    cleanup script, a GDPR-erasure feature, manual DB access) would
 *    silently and irrecoverably destroy that customer's loyalty ledger and
 *    membership history with no constraint stopping it. This migration
 *    brings all four in line with `restrictOnDelete()` — see
 *    SECURITY_HARDENING.md, "Cascade-delete inconsistency on customer-linked
 *    ledger tables."
 *
 * 2. `notifications(user_id, created_at)` — the notification inbox's
 *    primary query (`WHERE user_id = ? ORDER BY created_at DESC`) had no
 *    compound index covering both columns; only single-column `user_id`,
 *    single-column `created_at`, and an unrelated `(user_id, read_at)`
 *    index existed. See PERFORMANCE_HARDENING.md.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('customer_memberships', function (Blueprint $table): void {
            $table->dropForeign(['customer_id']);
            $table->foreign('customer_id')->references('id')->on('customer_profiles')->restrictOnDelete();
        });

        Schema::table('loyalty_accounts', function (Blueprint $table): void {
            $table->dropForeign(['customer_id']);
            $table->foreign('customer_id')->references('id')->on('customer_profiles')->restrictOnDelete();
        });

        Schema::table('loyalty_transactions', function (Blueprint $table): void {
            $table->dropForeign(['customer_id']);
            $table->foreign('customer_id')->references('id')->on('customer_profiles')->restrictOnDelete();
            $table->dropForeign(['loyalty_account_id']);
            $table->foreign('loyalty_account_id')->references('id')->on('loyalty_accounts')->restrictOnDelete();
        });

        Schema::table('notifications', function (Blueprint $table): void {
            $table->index(['user_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::table('customer_memberships', function (Blueprint $table): void {
            $table->dropForeign(['customer_id']);
            $table->foreign('customer_id')->references('id')->on('customer_profiles')->cascadeOnDelete();
        });

        Schema::table('loyalty_accounts', function (Blueprint $table): void {
            $table->dropForeign(['customer_id']);
            $table->foreign('customer_id')->references('id')->on('customer_profiles')->cascadeOnDelete();
        });

        Schema::table('loyalty_transactions', function (Blueprint $table): void {
            $table->dropForeign(['customer_id']);
            $table->foreign('customer_id')->references('id')->on('customer_profiles')->cascadeOnDelete();
            $table->dropForeign(['loyalty_account_id']);
            $table->foreign('loyalty_account_id')->references('id')->on('loyalty_accounts')->cascadeOnDelete();
        });

        Schema::table('notifications', function (Blueprint $table): void {
            $table->dropIndex(['user_id', 'created_at']);
        });
    }
};
