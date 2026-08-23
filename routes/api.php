<?php

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\BranchController;
use App\Http\Controllers\Api\V1\BranchHolidayController;
use App\Http\Controllers\Api\V1\BranchWorkingHourController;
use App\Http\Controllers\Api\V1\SalonController;
use App\Http\Controllers\Api\V1\ServiceCategoryController;
use App\Http\Controllers\Api\V1\ServiceController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function (): void {
    Route::prefix('auth')->middleware('throttle:auth')->group(function (): void {
        Route::post('register', [AuthController::class, 'register']);
        Route::post('login', [AuthController::class, 'login']);
    });
    Route::middleware('auth:sanctum')->prefix('auth')->group(function (): void {
        Route::post('logout', [AuthController::class, 'logout']);
        Route::get('me', [AuthController::class, 'me']);
    });

    Route::middleware(['auth:sanctum', 'tenant.context'])->group(function (): void {
        Route::get('salon', [SalonController::class, 'show']);
        Route::post('salon', [SalonController::class, 'store']);
        Route::match(['put', 'patch'], 'salon', [SalonController::class, 'update']);
        Route::get('salon/settings', [SalonController::class, 'settings']);
        Route::match(['put', 'patch'], 'salon/settings', [SalonController::class, 'updateSettings']);

        Route::apiResource('branches', BranchController::class);
        Route::get('branches/{branch}/working-hours', [BranchWorkingHourController::class, 'index']);
        Route::put('branches/{branch}/working-hours', [BranchWorkingHourController::class, 'update']);
        Route::get('branches/{branch}/holidays', [BranchHolidayController::class, 'index']);
        Route::post('branches/{branch}/holidays', [BranchHolidayController::class, 'store']);
        Route::match(['put', 'patch'], 'branches/{branch}/holidays/{holiday}', [BranchHolidayController::class, 'update']);
        Route::delete('branches/{branch}/holidays/{holiday}', [BranchHolidayController::class, 'destroy']);
        Route::apiResource('service-categories', ServiceCategoryController::class);
        Route::apiResource('services', ServiceController::class);
    });
});
