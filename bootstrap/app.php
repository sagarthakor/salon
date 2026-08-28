<?php

use App\Http\Middleware\EnsureActiveSubscription;
use App\Http\Middleware\ResolveTenantContext;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->alias([
            'tenant.context' => ResolveTenantContext::class,
            'subscription.active' => EnsureActiveSubscription::class,
        ]);

        // This is a pure JSON API with no 'login' named route (no web
        // auth views exist). Laravel's own default guest-redirect tries to
        // build one regardless of what the client's Accept header says,
        // which throws RouteNotFoundException — a real 500 instead of the
        // intended 401 — for any unauthenticated request that doesn't
        // happen to send `Accept: application/json` (every client this
        // project controls does, but a bare curl/health-check/monitoring
        // request won't). Returning null here means "never redirect,
        // always let AuthenticationException fall through to the JSON
        // exception handler below" — found during Phase 15 production
        // smoke testing; see SECURITY_HARDENING.md.
        $middleware->redirectGuestsTo(fn () => null);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );
        $exceptions->render(function (ValidationException $exception, Request $request) {
            if ($request->is('api/*')) {
                return response()->json(['success' => false, 'message' => 'The submitted data is invalid.', 'errors' => $exception->errors()], 422);
            }
        });
        $exceptions->render(function (AuthenticationException $exception, Request $request) {
            if ($request->is('api/*')) {
                return response()->json(['success' => false, 'message' => 'Unauthenticated.', 'errors' => (object) []], 401);
            }
        });
        $exceptions->render(function (AuthorizationException $exception, Request $request) {
            if ($request->is('api/*')) {
                return response()->json(['success' => false, 'message' => 'You are not authorized to perform this action.', 'errors' => (object) []], 403);
            }
        });
    })->create();
