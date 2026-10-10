<?php

namespace App\Services\Instagram;

use App\Enums\SalonMediaSource;
use App\Models\InstagramConnection;
use App\Models\SalonMedia;
use App\Support\InstagramUrl;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Pulls media METADATA (id, permalink, caption, type, thumbnail URL) through
 * the official API. Never downloads or re-hosts Instagram media files.
 *
 * Synced rows start hidden (`is_active = false`) so nothing the owner posted
 * on Instagram appears to customers until they choose to publish it, and a
 * re-sync only refreshes Instagram-owned fields — it never overrides the
 * owner's visibility, category, service link, ordering, or uploaded video.
 */
class InstagramMediaSyncService
{
    public function __construct(private readonly InstagramClient $client, private readonly InstagramConnectionService $connections) {}

    /** @return array{created: int, updated: int, skipped: int} */
    public function sync(InstagramConnection $connection): array
    {
        if (! $connection->isUsable()) {
            throw new InstagramApiException(InstagramApiException::AUTH, 'Your Instagram connection has expired. Please reconnect your account.');
        }

        $counts = ['created' => 0, 'updated' => 0, 'skipped' => 0];
        $ignored = DB::table('instagram_ignored_media')->where('tenant_id', $connection->tenant_id)->pluck('instagram_media_id')->flip()->all();
        $after = null;
        $maxPages = max(1, (int) config('salon_media.instagram_sync_max_pages', 10));

        try {
            for ($page = 0; $page < $maxPages; $page++) {
                $body = $this->client->mediaPage($connection->access_token, $after);
                foreach ((array) ($body['data'] ?? []) as $item) {
                    $counts[$this->upsert($item, $ignored)]++;
                }
                $after = $body['paging']['cursors']['after'] ?? null;
                if ($after === null || empty($body['paging']['next'])) {
                    break;
                }
            }
        } catch (InstagramApiException $exception) {
            if ($exception->kind === InstagramApiException::AUTH) {
                $this->connections->markExpired($connection, $exception->getMessage());
            }
            throw $exception;
        }

        $connection->forceFill(['last_synced_at' => now(), 'last_error' => null])->save();

        return $counts;
    }

    /**
     * @param  array<string, mixed>  $item
     * @param  array<string, mixed>  $ignored  Instagram ids the owner deleted (keys); they are never recreated.
     */
    private function upsert(array $item, array $ignored): string
    {
        $id = isset($item['id']) ? (string) $item['id'] : null;
        $permalink = isset($item['permalink']) ? (string) $item['permalink'] : null;
        $type = strtoupper((string) ($item['media_type'] ?? ''));
        if ($id === null || $permalink === null || ! in_array($type, ['VIDEO', 'IMAGE', 'CAROUSEL_ALBUM'], true)) {
            return 'skipped';
        }

        $fields = [
            'instagram_url' => $permalink,
            'instagram_thumbnail_url' => $item['thumbnail_url'] ?? null,
            'caption' => isset($item['caption']) ? mb_substr((string) $item['caption'], 0, 2200) : null,
            'media_type' => $type === 'VIDEO' ? 'video' : 'image',
            'instagram_posted_at' => isset($item['timestamp']) ? Carbon::parse($item['timestamp']) : null,
        ];
        $shortcode = InstagramUrl::shortcode($permalink);

        $media = SalonMedia::query()->where('instagram_media_id', $id)->first();
        if ($media === null && $shortcode !== null) {
            // The owner may already have added this very Reel by pasting its
            // link: adopt that row (same shortcode, not yet tied to an Instagram
            // id) instead of creating a duplicate. Their curation is untouched.
            $media = SalonMedia::query()->where('instagram_shortcode', $shortcode)->whereNull('instagram_media_id')->first();
            if ($media !== null) {
                $media->instagram_media_id = $id;
            } elseif (SalonMedia::query()->where('instagram_shortcode', $shortcode)->exists()) {
                // Same Reel already tracked under a different Instagram id: never duplicate it.
                return 'skipped';
            }
        }
        if ($media === null) {
            // The owner deleted this item earlier; a re-sync must not resurrect it.
            if (isset($ignored[$id])) {
                return 'skipped';
            }

            try {
                SalonMedia::query()->create($fields + [
                    'instagram_media_id' => $id,
                    'source' => SalonMediaSource::INSTAGRAM,
                    'is_active' => false,
                    'sort_order' => 0,
                ]);

                return 'created';
            } catch (UniqueConstraintViolationException $exception) {
                // A concurrent sync created the same item between our lookup and insert.
                // Reuse its row; anything else (an unrelated violation) is not ours to hide.
                $media = SalonMedia::query()->where('instagram_media_id', $id)->first();
                if ($media === null) {
                    if ($shortcode !== null && SalonMedia::query()->where('instagram_shortcode', $shortcode)->exists()) {
                        return 'skipped';
                    }

                    throw $exception;
                }
            }
        }

        // The owner's caption always wins: it is only filled while empty and never customized.
        if ($media->caption_customized || ($media->caption !== null && $media->caption !== '')) {
            unset($fields['caption']);
        }
        $media->update($fields);
        // A re-added (adopted) item is wanted again; drop its stale "ignored" marker.
        if (isset($ignored[$id])) {
            DB::table('instagram_ignored_media')->where('tenant_id', $media->tenant_id)->where('instagram_media_id', $id)->delete();
        }

        return 'updated';
    }
}
