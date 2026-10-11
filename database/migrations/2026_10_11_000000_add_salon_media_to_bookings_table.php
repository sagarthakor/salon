<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * "Book This Style": remembers which gallery item inspired a booking so the
 * salon can see the reference photo/video. `style_label` is a snapshot so the
 * booking still reads sensibly if the gallery item is later deleted
 * (`salon_media_id` is then nulled). See SALON_MEDIA_ARCHITECTURE.md.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('bookings', function (Blueprint $table): void {
            $table->foreignUlid('salon_media_id')->nullable()->after('customer_id')->constrained('salon_media')->nullOnDelete();
            $table->string('style_label', 160)->nullable()->after('salon_media_id');
        });
    }

    public function down(): void
    {
        Schema::table('bookings', function (Blueprint $table): void {
            $table->dropConstrainedForeignId('salon_media_id');
            $table->dropColumn('style_label');
        });
    }
};
