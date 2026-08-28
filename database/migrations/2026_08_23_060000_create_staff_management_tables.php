<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('staff_profiles', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('name');
            $table->string('photo')->nullable();
            $table->string('phone', 32)->nullable();
            $table->string('email')->nullable();
            $table->string('gender', 16);
            $table->text('bio')->nullable();
            $table->date('joining_date')->nullable();
            $table->string('status', 16)->default('active');
            $table->string('commission_type', 16)->nullable();
            $table->decimal('commission_value', 8, 2)->nullable();
            $table->timestamps();
            $table->softDeletes();
            $table->unique(['tenant_id', 'user_id']);
            $table->index(['tenant_id', 'status']);
        });
        Schema::create('staff_branches', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('staff_id')->constrained('staff_profiles')->cascadeOnDelete();
            $table->foreignUlid('branch_id')->constrained()->cascadeOnDelete();
            $table->timestamps();
            $table->unique(['staff_id', 'branch_id']);
            $table->index(['tenant_id', 'branch_id']);
        });
        Schema::create('staff_services', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('staff_id')->constrained('staff_profiles')->cascadeOnDelete();
            $table->foreignUlid('service_id')->constrained()->cascadeOnDelete();
            $table->timestamps();
            $table->unique(['staff_id', 'service_id']);
            $table->index(['tenant_id', 'service_id']);
        });
        Schema::create('staff_working_hours', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('staff_id')->constrained('staff_profiles')->cascadeOnDelete();
            $table->unsignedTinyInteger('day_of_week');
            $table->boolean('is_working')->default(false);
            $table->time('start_time')->nullable();
            $table->time('end_time')->nullable();
            $table->timestamps();
            $table->unique(['staff_id', 'day_of_week']);
            $table->index(['tenant_id', 'staff_id']);
        });
        Schema::create('staff_breaks', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('staff_id')->constrained('staff_profiles')->cascadeOnDelete();
            $table->unsignedTinyInteger('day_of_week');
            $table->time('start_time');
            $table->time('end_time');
            $table->timestamps();
            $table->index(['tenant_id', 'staff_id', 'day_of_week']);
        });
        Schema::create('staff_leaves', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('staff_id')->constrained('staff_profiles')->cascadeOnDelete();
            $table->date('start_date');
            $table->date('end_date');
            $table->text('reason')->nullable();
            $table->string('status', 16)->default('approved');
            $table->timestamps();
            $table->index(['tenant_id', 'staff_id', 'start_date', 'end_date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('staff_leaves');
        Schema::dropIfExists('staff_breaks');
        Schema::dropIfExists('staff_working_hours');
        Schema::dropIfExists('staff_services');
        Schema::dropIfExists('staff_branches');
        Schema::dropIfExists('staff_profiles');
    }
};
