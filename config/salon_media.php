<?php

return [
    // Disk for owner-uploaded videos/thumbnails. `public` matches service
    // images; switch to an S3/CDN-backed disk via env with no code change.
    'disk' => env('SALON_MEDIA_DISK', 'public'),

    'max_video_kb' => (int) env('SALON_MEDIA_MAX_VIDEO_KB', 51200),
    'max_thumbnail_kb' => 5120,

    // Hard cap on Instagram pages fetched per sync (50 items/page).
    'instagram_sync_max_pages' => (int) env('INSTAGRAM_SYNC_MAX_PAGES', 10),
];
