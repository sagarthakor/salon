<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Hair Inspiration / "Our Work" gallery. `salon_media` is tenant-owned
 * (salon-wide when `branch_id` is null); `instagram_connections` holds the
 * one official Instagram Professional-account authorization per tenant.
 * See SALON_MEDIA_ARCHITECTURE.md.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('salon_media', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('branch_id')->nullable()->constrained()->cascadeOnDelete();
            $table->foreignUlid('service_id')->nullable()->constrained()->nullOnDelete();
            $table->string('source', 16);
            $table->string('media_type', 16)->default('video');
            $table->string('category', 24)->nullable();
            $table->string('instagram_media_id', 64)->nullable();
            $table->string('instagram_url', 500)->nullable();
            // Case-sensitive Reel/post id, used to recognise the same Reel across URL spellings.
            $shortcode = $table->string('instagram_shortcode', 64)->nullable();
            if (Schema::getConnection()->getDriverName() === 'mysql') {
                $shortcode->collation('utf8mb4_bin');
            }
            $table->text('instagram_thumbnail_url')->nullable();
            $table->timestamp('instagram_posted_at')->nullable();
            $table->string('video_path')->nullable();
            $table->string('thumbnail_path')->nullable();
            $table->text('caption')->nullable();
            // True once the owner has set or cleared the caption themselves; a sync then never refills it.
            $table->boolean('caption_customized')->default(false);
            $table->boolean('is_active')->default(false);
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();
            $table->unique(['tenant_id', 'instagram_media_id']);
            $table->unique(['tenant_id', 'instagram_shortcode']);
            $table->index(['tenant_id', 'is_active', 'sort_order']);
            $table->index(['tenant_id', 'branch_id']);
            $table->index(['tenant_id', 'category']);
        });

        // Instagram media ids whose gallery item the owner deleted, so a later sync does not recreate them.
        Schema::create('instagram_ignored_media', function (Blueprint $table): void {
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('instagram_media_id', 64);
            $table->timestamp('created_at')->nullable();
            $table->primary(['tenant_id', 'instagram_media_id']);
        });

        Schema::create('instagram_connections', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('tenant_id')->unique()->constrained()->cascadeOnDelete();
            $table->foreignId('connected_by')->nullable()->constrained('users')->nullOnDelete();
            $table->string('instagram_user_id', 64);
            $table->string('username')->nullable();
            $table->string('account_type', 32)->nullable();
            // Encrypted at rest via the model's `encrypted` cast; never serialized.
            $table->text('access_token');
            $table->timestamp('token_expires_at')->nullable();
            $table->timestamp('token_refreshed_at')->nullable();
            $table->string('status', 16)->default('active');
            $table->string('last_error')->nullable();
            $table->timestamp('last_synced_at')->nullable();
            $table->timestamps();
            $table->index(['status', 'token_expires_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('instagram_connections');
        Schema::dropIfExists('instagram_ignored_media');
        Schema::dropIfExists('salon_media');
    }
};
