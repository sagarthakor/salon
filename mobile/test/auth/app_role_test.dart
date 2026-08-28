import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/features/auth/data/models/app_role.dart';

void main() {
  group('AppRole.fromBackendRole', () {
    test('maps every literal backend role to its navigation group', () {
      expect(AppRole.fromBackendRole('customer'), AppRole.customer);
      expect(AppRole.fromBackendRole('salon_owner'), AppRole.ownerAdmin);
      expect(AppRole.fromBackendRole('super_admin'), AppRole.ownerAdmin);
      expect(AppRole.fromBackendRole('staff'), AppRole.staff);
    });

    test('an unrecognized role never grants owner/admin navigation — it falls back to unknown', () {
      expect(AppRole.fromBackendRole('something_new'), AppRole.unknown);
      expect(AppRole.fromBackendRole(''), AppRole.unknown);
    });
  });
}
