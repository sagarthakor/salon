<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\SalonMediaSource;
use App\Http\Requests\Media\SalonMediaRequest;
use App\Http\Resources\SalonMediaResource;
use App\Models\SalonMedia;
use App\Support\ApiResponse;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;

/**
 * Owner management of the Hair Inspiration gallery. Every query goes through
 * SalonMedia's `BelongsToTenant` scope, so another tenant's item is a 404 —
 * never readable, editable, or replaceable. Tenant is never taken from the
 * request body.
 */
class SalonMediaController extends TenantManagementController
{
    public function index(Request $request): JsonResponse
    {
        $this->managedTenant();
        $query = SalonMedia::query()->with('service');
        foreach (['source', 'category', 'media_type', 'branch_id'] as $filter) {
            if ($request->filled($filter)) {
                $query->where($filter, $request->string($filter));
            }
        }
        if ($request->filled('is_active')) {
            $query->where('is_active', $request->boolean('is_active'));
        }
        $this->ordered($query);

        return ApiResponse::success(SalonMediaResource::collection($query->paginate(min($request->integer('per_page', 20), 100))), 'Gallery retrieved.');
    }

    public function store(SalonMediaRequest $request): JsonResponse
    {
        $this->managedTenant();
        $data = $request->validated();
        unset($data['video'], $data['thumbnail'], $data['image'], $data['remove_video'], $data['remove_thumbnail']);
        $data['caption_customized'] = filled($data['caption'] ?? null);
        $data['is_active'] ??= true;
        $data['sort_order'] ??= 0;
        $data['media_type'] = $request->hasFile('image') ? 'photo' : 'video';
        $data['source'] = $request->hasFile('video') || $request->hasFile('image') ? SalonMediaSource::UPLOAD : SalonMediaSource::INSTAGRAM;

        $paths = [];
        try {
            if ($request->hasFile('video')) {
                $paths[] = $data['video_path'] = $this->storeFile($request->file('video'), 'videos');
            }
            // A photo item keeps its image in `thumbnail_path` (the grid tile and the viewer share it).
            if ($request->hasFile('image')) {
                $paths[] = $data['thumbnail_path'] = $this->storeFile($request->file('image'), 'images');
            } elseif ($request->hasFile('thumbnail')) {
                $paths[] = $data['thumbnail_path'] = $this->storeFile($request->file('thumbnail'), 'thumbnails');
            }
            $media = SalonMedia::query()->create($data);
        } catch (\Throwable $exception) {
            foreach ($paths as $path) {
                Storage::disk(SalonMedia::disk())->delete($path);
            }
            throw $exception;
        }

        return ApiResponse::success(new SalonMediaResource($media->load('service')), 'Gallery item created.', 201);
    }

    public function show(string $media): JsonResponse
    {
        $this->managedTenant();

        return ApiResponse::success(new SalonMediaResource($this->find($media)->load('service')), 'Gallery item retrieved.');
    }

    public function update(SalonMediaRequest $request, string $media): JsonResponse
    {
        $this->managedTenant();
        $model = $this->find($media);
        $data = $request->validated();
        unset($data['video'], $data['thumbnail'], $data['image'], $data['remove_video'], $data['remove_thumbnail']);
        // Setting or deliberately clearing the caption (a value that differs from what is stored)
        // marks it owner-managed, so a later Instagram sync never refills it.
        if (array_key_exists('caption', $data) && $data['caption'] !== $model->caption) {
            $data['caption_customized'] = true;
        }
        // Omitted or null leaves the current position untouched (the column is NOT NULL).
        if (($data['sort_order'] ?? null) === null) {
            unset($data['sort_order']);
        }

        $obsolete = [];
        if ($request->hasFile('video')) {
            $obsolete[] = $model->video_path;
            $data['video_path'] = $this->storeFile($request->file('video'), 'videos');
        } elseif ($request->boolean('remove_video')) {
            $obsolete[] = $model->video_path;
            $data['video_path'] = null;
        }
        if ($request->hasFile('image') && $model->isPhoto()) {
            $obsolete[] = $model->thumbnail_path;
            $data['thumbnail_path'] = $this->storeFile($request->file('image'), 'images');
        } elseif ($request->hasFile('thumbnail')) {
            $obsolete[] = $model->thumbnail_path;
            $data['thumbnail_path'] = $this->storeFile($request->file('thumbnail'), 'thumbnails');
        } elseif ($request->boolean('remove_thumbnail') && ! $model->isPhoto()) {
            $obsolete[] = $model->thumbnail_path;
            $data['thumbnail_path'] = null;
        }

        // An item must always stay presentable: hosted video or Instagram link.
        $willHaveVideo = array_key_exists('video_path', $data) ? $data['video_path'] !== null : $model->video_path !== null;
        $willHaveLink = array_key_exists('instagram_url', $data) ? $data['instagram_url'] !== null : $model->instagram_url !== null;
        if (! $model->isPhoto() && ! $willHaveVideo && ! $willHaveLink) {
            return ApiResponse::error('A gallery item needs a hosted video or an Instagram link.', ['video' => ['A gallery item needs a hosted video or an Instagram link.']], 422);
        }

        $model->update($data);
        foreach (array_filter($obsolete) as $path) {
            Storage::disk(SalonMedia::disk())->delete($path);
        }

        return ApiResponse::success(new SalonMediaResource($model->fresh()->load('service')), 'Gallery item updated.');
    }

    public function destroy(string $media): JsonResponse
    {
        $this->managedTenant();
        $this->find($media)->delete();

        return ApiResponse::success(null, 'Gallery item deleted.');
    }

    /** Body: `ids` — the desired display order; unknown/other-tenant ids are rejected. */
    public function reorder(Request $request): JsonResponse
    {
        $tenant = $this->managedTenant();
        $data = $request->validate([
            'ids' => ['required', 'array', 'min:1', 'max:500'],
            'ids.*' => ['required', 'string', 'distinct', Rule::exists('salon_media', 'id')->where('tenant_id', $tenant->id)],
        ]);
        DB::transaction(function () use ($data): void {
            foreach (array_values($data['ids']) as $position => $id) {
                SalonMedia::query()->whereKey($id)->update(['sort_order' => $position + 1]);
            }
        });

        return ApiResponse::success(null, 'Gallery reordered.');
    }

    public static function ordered($query): void
    {
        $query->orderBy('sort_order')->orderByDesc('instagram_posted_at')->orderByDesc('created_at')->orderBy('id');
    }

    private function find(string $id): SalonMedia
    {
        return SalonMedia::query()->findOrFail($id);
    }

    /** Stored under a tenant-scoped folder with a generated name; the client filename is never used. */
    private function storeFile(UploadedFile $file, string $folder): string
    {
        $tenantId = app(TenantContext::class)->id();

        return $file->store("salon-media/{$tenantId}/{$folder}", SalonMedia::disk());
    }
}
