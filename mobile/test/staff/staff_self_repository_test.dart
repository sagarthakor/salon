import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_client.dart';
import 'package:salon_customer/features/owner/staff/data/repositories/staff_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient client;

  setUp(() {
    client = MockApiClient();
  });

  group('StaffRepository.me', () {
    test('calls GET /staff/me and parses the resolved staff profile', () async {
      when(() => client.get<Map<String, dynamic>>('/staff/me')).thenAnswer(
        (_) async => {
          'id': 'stf-1',
          'user_id': 4,
          'name': 'Amit',
          'gender': 'male',
          'status': 'active',
          'branches': [
            {'id': 'br-1', 'name': 'Main Branch', 'slug': 'main-branch', 'address': null, 'timezone': 'UTC', 'status': 'active'},
          ],
        },
      );

      final staff = await StaffRepository(client).me();

      expect(staff.id, 'stf-1');
      expect(staff.name, 'Amit');
      expect(staff.branches, hasLength(1));
      verify(() => client.get<Map<String, dynamic>>('/staff/me')).called(1);
    });
  });
}
