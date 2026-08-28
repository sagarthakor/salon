<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The platform-level master service catalog — deliberately NOT tenant-scoped
 * (no `tenant_id`, no `BelongsToTenant`). A new tenant's own services are a
 * one-time COPY of this data (see CatalogProvisioningService); nothing here
 * is ever read live by a tenant's booking/pricing/media logic. See
 * MASTER_CATALOG_ARCHITECTURE.md.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('master_service_categories', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->string('audience', 16);
            $table->string('name');
            $table->string('slug');
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->unique(['audience', 'slug']);
        });

        Schema::create('master_services', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('master_service_category_id')->constrained('master_service_categories')->cascadeOnDelete();
            $table->string('audience', 16);
            $table->string('name');
            $table->string('slug');
            $table->text('description')->nullable();
            $table->unsignedInteger('default_duration_minutes');
            $table->decimal('default_price', 12, 2)->nullable();
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->unique(['master_service_category_id', 'slug']);
            $table->index('audience');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('master_services');
        Schema::dropIfExists('master_service_categories');
    }
};
