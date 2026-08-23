<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\UserRole;
use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\LoginRequest;
use App\Http\Requests\Auth\RegisterRequest;
use App\Http\Resources\UserResource;
use App\Models\User;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class AuthController extends Controller
{
    public function register(RegisterRequest $request): JsonResponse
    {
        $user = User::query()->create([...$request->validated(), 'role' => UserRole::CUSTOMER]);

        return ApiResponse::success(['user' => new UserResource($user), 'token' => $user->createToken('mobile')->plainTextToken], 'Registration successful.', 201);
    }

    public function login(LoginRequest $request): JsonResponse
    {
        $user = User::query()->where('email', $request->validated('email'))->first();
        if ($user === null || ! Hash::check($request->validated('password'), $user->password)) {
            return ApiResponse::error('Invalid credentials.', [], 422);
        } $user->tokens()->where('name', 'mobile')->delete();

        return ApiResponse::success(['user' => new UserResource($user), 'token' => $user->createToken('mobile')->plainTextToken], 'Login successful.');
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->tokens()->delete();

        return ApiResponse::success(null, 'Logout successful.');
    }

    public function me(Request $request): JsonResponse
    {
        return ApiResponse::success(new UserResource($request->user()->load('tenants')), 'Authenticated user retrieved.');
    }
}
