<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The salon's official Instagram profile link — deliberately separate from
 * `services.instagram_url` (a specific post/reel/video for one service; see
 * the earlier migration adding that column). Same 500-char ceiling as that
 * column for consistency, though a profile URL is always far shorter.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('salons', function (Blueprint $table): void {
            $table->string('instagram_url', 500)->nullable()->after('website');
        });
    }

    public function down(): void
    {
        Schema::table('salons', function (Blueprint $table): void {
            $table->dropColumn('instagram_url');
        });
    }
};
