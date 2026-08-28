import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network/api_client.dart';
import 'storage/secure_storage.dart';

/// App-wide infrastructure providers. Feature-level repository/state
/// providers live next to their feature (e.g.
/// `features/auth/presentation/providers/auth_provider.dart`) and depend on
/// these rather than constructing their own `ApiClient`.
final secureStorageProvider = Provider<SecureStorage>((ref) => SecureStorage());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(secureStorage: ref.watch(secureStorageProvider));
});
