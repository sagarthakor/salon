<?php

namespace App\Models;

use App\Enums\SalonMediaCategory;
use App\Enums\SalonMediaSource;
use App\Models\Concerns\BelongsToTenant;
use App\Support\InstagramUrl;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

class SalonMedia extends Model
{
    use BelongsToTenant, HasUlids;

    protected $table = 'salon_media';

    protected $fillable = ['branch_id', 'service_id', 'source', 'media_type', 'category', 'instagram_media_id', 'instagram_url', 'instagram_shortcode', 'instagram_thumbnail_url', 'instagram_posted_at', 'video_path', 'thumbnail_path', 'caption', 'caption_customized', 'is_active', 'sort_order'];

    protected function casts(): array
    {
        return [
            'source' => SalonMediaSource::class,
            'category' => SalonMediaCategory::class,
            'is_active' => 'boolean',
            'caption_customized' => 'boolean',
            'instagram_posted_at' => 'datetime',
        ];
    }

    /** Removing a row never leaves its hosted files orphaned in storage. */
    protected static function booted(): void
    {
        // The shortcode always mirrors instagram_url, so no code path (manual
        // add, edit, sync) can store a link without its dedupe key.
        static::saving(function (SalonMedia $media): void {
            if ($media->isDirty('instagram_url')) {
                $media->instagram_shortcode = $media->instagram_url === null ? null : InstagramUrl::shortcode($media->instagram_url);
            }
        });
        static::deleted(function (SalonMedia $media): void {
            $media->deleteStoredFiles();
            // Remember an owner-deleted Instagram item so the next sync does not bring it back.
            if ($media->instagram_media_id !== null) {
                DB::table('instagram_ignored_media')->insertOrIgnore([
                    'tenant_id' => $media->tenant_id,
                    'instagram_media_id' => $media->instagram_media_id,
                    'created_at' => now(),
                ]);
            }
        });
    }

    public static function disk(): string
    {
        return (string) config('salon_media.disk', 'public');
    }

    public function deleteStoredFiles(): void
    {
        foreach ([$this->video_path, $this->thumbnail_path] as $path) {
            if ($path !== null) {
                Storage::disk(self::disk())->delete($path);
            }
        }
    }

    public function isPhoto(): bool
    {
        return $this->media_type === 'photo';
    }

    /** Hosted thumbnail (or the photo itself), else Instagram's expiring CDN thumbnail. */
    public function thumbnailUrl(): ?string
    {
        return $this->thumbnail_path !== null ? Storage::disk(self::disk())->url($this->thumbnail_path) : $this->instagram_thumbnail_url;
    }

    public function hasNativeVideo(): bool
    {
        return $this->video_path !== null;
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function service(): BelongsTo
    {
        return $this->belongsTo(Service::class);
    }
}
