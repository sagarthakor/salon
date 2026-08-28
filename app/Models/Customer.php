<?php

namespace App\Models;

use App\Enums\BusinessStatus;
use App\Enums\CustomerGender;
use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class Customer extends Model
{
    use BelongsToTenant, HasUlids, SoftDeletes;

    protected $table = 'customer_profiles';

    protected $fillable = ['user_id', 'name', 'phone', 'country_code', 'normalized_phone', 'email', 'gender', 'date_of_birth', 'profile_photo', 'address', 'status'];

    protected function casts(): array
    {
        return ['gender' => CustomerGender::class, 'status' => BusinessStatus::class, 'date_of_birth' => 'date:Y-m-d'];
    }

    public static function normalizePhone(string $phone, ?string $countryCode): string
    {
        $digits = preg_replace('/\D+/', '', $phone) ?? '';
        $codeDigits = $countryCode ? (preg_replace('/\D+/', '', $countryCode) ?? '') : '';

        return $codeDigits !== '' ? $codeDigits.$digits : $digits;
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function notes(): HasMany
    {
        return $this->hasMany(CustomerNote::class);
    }

    public function bookings(): HasMany
    {
        return $this->hasMany(Booking::class);
    }
}
