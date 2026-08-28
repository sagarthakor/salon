<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Adds the audience classification to tenant-owned categories/services —
 * nullable, so every existing row (predating this feature) keeps working
 * unchanged. `services.master_service_id` tracks which master catalog
 * service a row was provisioned from, purely for idempotency (see
 * CatalogProvisioningService) — never a live reference a tenant's own price/
 * media/etc. reads through; `nullOnDelete()` so a master catalog row being
 * removed later can never affect (let alone delete) an already-provisioned
 * tenant service.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('service_categories', function (Blueprint $table): void {
            $table->string('audience', 16)->nullable()->after('branch_id');
            $table->index(['tenant_id', 'audience']);
        });

        Schema::table('services', function (Blueprint $table): void {
            $table->string('audience', 16)->nullable()->after('category_id');
            $table->foreignUlid('master_service_id')->nullable()->after('audience')->constrained('master_services')->nullOnDelete();
            $table->index(['tenant_id', 'audience']);
        });
    }

    public function down(): void
    {
        Schema::table('services', function (Blueprint $table): void {
            $table->dropForeign(['master_service_id']);
            $table->dropIndex(['tenant_id', 'audience']);
            $table->dropColumn(['audience', 'master_service_id']);
        });

        Schema::table('service_categories', function (Blueprint $table): void {
            $table->dropIndex(['tenant_id', 'audience']);
            $table->dropColumn('audience');
        });
    }
};
