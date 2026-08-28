/// Compile-time environment configuration.
///
/// The API base URL is never hard-coded: it is supplied via `--dart-define`
/// at build/run time, with a sensible default for local Android-emulator
/// development so `flutter run` works out of the box against `php artisan
/// serve`. See MOBILE_API_INTEGRATION.md / FLUTTER_SETUP.md for the exact
/// values to use for a physical device, iOS simulator, and production.
class AppConfig {
  const AppConfig._();

  /// `10.0.2.2` is the Android emulator's alias for the host machine's
  /// `127.0.0.1` — the emulator cannot reach `localhost`/`127.0.0.1` directly
  /// because that resolves to the emulator itself, not the host.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// Enables verbose request/response logging. Off by default in release
  /// builds; on by default in debug builds unless explicitly overridden.
  static const bool enableNetworkLogging = bool.fromEnvironment(
    'ENABLE_NETWORK_LOGGING',
    defaultValue: true,
  );
}
