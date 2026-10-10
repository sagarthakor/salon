<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;

class InstagramConnection extends Model
{
    use BelongsToTenant, HasUlids;

    public const STATUS_ACTIVE = 'active';

    public const STATUS_EXPIRED = 'expired';

    protected $fillable = ['connected_by', 'instagram_user_id', 'username', 'account_type', 'access_token', 'token_expires_at', 'token_refreshed_at', 'status', 'last_error', 'last_synced_at'];

    /** The token must never appear in any serialized form of this model. */
    protected $hidden = ['access_token'];

    protected function casts(): array
    {
        return [
            'access_token' => 'encrypted',
            'token_expires_at' => 'datetime',
            'token_refreshed_at' => 'datetime',
            'last_synced_at' => 'datetime',
        ];
    }

    public function isUsable(): bool
    {
        return $this->status === self::STATUS_ACTIVE
            && ($this->token_expires_at === null || $this->token_expires_at->isFuture());
    }
}
