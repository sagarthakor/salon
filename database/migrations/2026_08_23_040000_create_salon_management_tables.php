<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('salons', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('tenant_id')->unique()->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('slug')->unique();
            $table->text('description')->nullable();
            $table->string('gender_type', 16);
            $table->string('logo')->nullable();
            $table->string('cover_image')->nullable();
            $table->string('phone', 32)->nullable();
            $table->string('email')->nullable();
            $table->string('website')->nullable();
            $table->string('address_line_1')->nullable();
            $table->string('address_line_2')->nullable();
            $table->string('city')->nullable();
            $table->string('state')->nullable();
            $table->string('country', 2)->nullable();
            $table->string('postal_code', 32)->nullable();
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->string('timezone')->default('UTC');
            $table->string('status', 16)->default('active')->index();
            $table->timestamps();
            $table->softDeletes();
        });
        Schema::create('salon_settings', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('salon_id')->constrained()->cascadeOnDelete();
            $table->string('key', 64);
            $table->json('value')->nullable();
            $table->timestamps();
            $table->unique(['salon_id', 'key']);
            $table->index(['tenant_id', 'salon_id']);
        });
        Schema::create('branches', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('salon_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('slug');
            $table->string('phone', 32)->nullable();
            $table->string('email')->nullable();
            $table->string('address_line_1')->nullable();
            $table->string('address_line_2')->nullable();
            $table->string('city')->nullable();
            $table->string('state')->nullable();
            $table->string('country', 2)->nullable();
            $table->string('postal_code', 32)->nullable();
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->string('timezone')->default('UTC');
            $table->string('status', 16)->default('active')->index();
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['tenant_id', 'slug']);
            $table->index(['tenant_id', 'salon_id', 'status']);
        });
        Schema::create('branch_working_hours', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('branch_id')->constrained()->cascadeOnDelete();
            $table->unsignedTinyInteger('day_of_week');
            $table->boolean('is_open')->default(false);
            $table->time('opening_time')->nullable();
            $table->time('closing_time')->nullable();
            $table->timestamps();
            $table->unique(['branch_id', 'day_of_week']);
            $table->index(['tenant_id', 'branch_id']);
        });
        Schema::create('branch_holidays', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('branch_id')->constrained()->cascadeOnDelete();
            $table->date('holiday_date');
            $table->string('name');
            $table->boolean('is_closed')->default(true);
            $table->timestamps();
            $table->unique(['branch_id', 'holiday_date']);
            $table->index(['tenant_id', 'branch_id', 'holiday_date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('branch_holidays');
        Schema::dropIfExists('branch_working_hours');
        Schema::dropIfExists('branches');
        Schema::dropIfExists('salon_settings');
        Schema::dropIfExists('salons');
    }
};
