<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Services\Instagram\InstagramApiException;
use App\Services\Instagram\InstagramConnectionService;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

/**
 * OAuth redirect target. Reached by the owner's browser, so there is no
 * bearer token: authenticity comes entirely from the single-use, tenant-bound
 * `state` created by an authenticated owner (see InstagramConnectionService).
 * Renders a tiny static page and never echoes provider payloads or tokens.
 */
class InstagramCallbackController extends Controller
{
    public function __invoke(Request $request, InstagramConnectionService $service): Response
    {
        if ($request->filled('error') || ! $request->filled('code') || ! $request->filled('state')) {
            return $this->page('Instagram was not connected', 'Authorization was cancelled or denied. You can close this window and try again from the app.', 400);
        }
        try {
            $connection = $service->completeAuthorization($request->string('state')->toString(), $request->string('code')->toString());
        } catch (InstagramApiException $exception) {
            return $this->page('Instagram was not connected', $exception->getMessage(), $exception->httpStatus() === 429 ? 429 : 400);
        }

        return $this->page('Instagram connected', 'Connected'.($connection->username ? ' as @'.$connection->username : '').'. You can close this window and return to the app.', 200);
    }

    private function page(string $title, string $message, int $status): Response
    {
        $title = e($title);
        $message = e($message);

        return response(
            "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>{$title}</title></head><body style=\"font-family:system-ui,sans-serif;max-width:28rem;margin:4rem auto;padding:0 1rem;text-align:center\"><h1>{$title}</h1><p>{$message}</p></body></html>",
            $status,
            ['Content-Type' => 'text/html; charset=UTF-8', 'Cache-Control' => 'no-store', 'Referrer-Policy' => 'no-referrer'],
        );
    }
}
