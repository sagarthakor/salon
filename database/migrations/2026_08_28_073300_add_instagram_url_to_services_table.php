<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * `services.image` (nullable string) and `services.description` (nullable
 * text) already existed from Phase 3 — only `instagram_url` is new here.
 * 500 chars comfortably covers Instagram's own URL length (share links with
 * a tracking query string included) without inviting arbitrary long input.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('services', function (Blueprint $table): void {
            $table->string('instagram_url', 500)->nullable()->after('image');
        });
    }

    public function down(): void
    {
        Schema::table('services', function (Blueprint $table): void {
            $table->dropColumn('instagram_url');
        });
    }
};
