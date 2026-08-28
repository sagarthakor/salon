<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('notifications', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('tenant_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            // Polymorphic reference to the domain record this notification is
            // about (a Booking, Subscription, ...). Manually declared (not
            // ->morphs()) because those models use ULID keys, not bigints.
            $table->string('notifiable_type')->nullable();
            $table->string('notifiable_id')->nullable();
            $table->string('type', 64);
            $table->string('title');
            $table->text('body');
            $table->json('data')->nullable();
            $table->timestamp('read_at')->nullable();
            $table->timestamps();
            $table->index('user_id');
            $table->index('tenant_id');
            $table->index('read_at');
            $table->index('created_at');
            $table->index(['notifiable_type', 'notifiable_id']);
            $table->index(['user_id', 'read_at']);
        });

        Schema::create('notification_deliveries', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignUlid('notification_id')->nullable()->constrained('notifications')->nullOnDelete();
            $table->string('event_type', 64);
            $table->string('channel', 16);
            $table->string('recipient');
            $table->string('provider', 32)->nullable();
            $table->string('provider_message_id')->nullable();
            $table->string('status', 16)->default('pending');
            $table->unsignedInteger('attempt_count')->default(0);
            $table->timestamp('last_attempt_at')->nullable();
            $table->timestamp('sent_at')->nullable();
            $table->timestamp('failed_at')->nullable();
            $table->text('failure_reason')->nullable();
            $table->json('metadata')->nullable();
            $table->timestamps();
            $table->index('tenant_id');
            $table->index('notification_id');
            $table->index('channel');
            $table->index('status');
            $table->index('provider_message_id');
        });

        Schema::create('user_device_tokens', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUlid('tenant_id')->nullable()->constrained()->nullOnDelete();
            $table->string('platform', 16);
            $table->string('token', 512);
            $table->string('device_identifier')->nullable();
            $table->timestamp('last_seen_at')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->unique('token');
            $table->index(['user_id', 'is_active']);
        });

        Schema::create('notification_preferences', function (Blueprint $table): void {
            $table->id();
            // A row with user_id = null is a tenant-wide default set by the
            // owner; a row with user_id set is a personal override. See
            // NotificationPreferenceResolver for precedence.
            $table->foreignUlid('tenant_id')->nullable()->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->nullable()->constrained('users')->cascadeOnDelete();
            $table->string('event_type', 64);
            $table->string('channel', 16);
            $table->boolean('enabled');
            $table->timestamps();
            $table->unique(['tenant_id', 'user_id', 'event_type', 'channel'], 'notif_pref_scope_unique');
            $table->index(['tenant_id', 'event_type']);
            $table->index(['user_id', 'event_type']);
        });

        Schema::create('booking_reminders', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('booking_id')->constrained('bookings')->cascadeOnDelete();
            $table->string('reminder_type', 16);
            $table->timestamp('scheduled_at');
            $table->timestamp('sent_at')->nullable();
            $table->timestamps();
            $table->unique(['booking_id', 'reminder_type']);
            $table->index(['tenant_id', 'scheduled_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('booking_reminders');
        Schema::dropIfExists('notification_preferences');
        Schema::dropIfExists('user_device_tokens');
        Schema::dropIfExists('notification_deliveries');
        Schema::dropIfExists('notifications');
    }
};
