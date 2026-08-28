import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/features/owner/staff/data/models/staff_member.dart';
import 'package:salon_customer/features/owner/staff/data/models/staff_schedule.dart';

void main() {
  group('StaffMember.fromJson', () {
    test('parses a full staff resource, including nested branches and commission', () {
      final staff = StaffMember.fromJson({
        'id': 'stf-1',
        'user_id': 42,
        'name': 'Priya Verma',
        'photo': 'https://cdn.test/priya.jpg',
        'phone': '9876543210',
        'email': 'priya@example.test',
        'gender': 'female',
        'bio': 'Senior stylist',
        'joining_date': '2024-01-15',
        'status': 'active',
        'commission_type': 'percentage',
        'commission_value': '15.5',
        'branches': [
          {
            'id': 'br-1',
            'name': 'MG Road',
            'slug': 'mg-road',
            'address': null,
            'timezone': 'Asia/Kolkata',
            'status': 'active',
          },
        ],
      });

      expect(staff.name, 'Priya Verma');
      expect(staff.isActive, isTrue);
      expect(staff.commissionValue, 15.5);
      expect(staff.branches, hasLength(1));
      expect(staff.branches.first.name, 'MG Road');
    });

    test('a staff member with no branches assigned yet parses to an empty list, not null', () {
      final staff = StaffMember.fromJson({
        'id': 'stf-2',
        'name': 'New Hire',
        'gender': 'male',
        'status': 'inactive',
      });

      expect(staff.branches, isEmpty);
      expect(staff.isActive, isFalse);
      expect(staff.userId, isNull);
      expect(staff.photo, isNull);
    });
  });

  group('StaffWorkingHourEntry', () {
    test('round-trips through toJson/fromJson', () {
      const entry = StaffWorkingHourEntry(dayOfWeek: 1, isWorking: true, startTime: '09:00', endTime: '18:00');
      final restored = StaffWorkingHourEntry.fromJson(entry.toJson());

      expect(restored.dayOfWeek, 1);
      expect(restored.isWorking, isTrue);
      expect(restored.startTime, '09:00');
      expect(restored.endTime, '18:00');
    });

    test('copyWith only overrides the fields passed, keeping dayOfWeek fixed', () {
      const entry = StaffWorkingHourEntry(dayOfWeek: 3, isWorking: false, startTime: null, endTime: null);
      final updated = entry.copyWith(isWorking: true, startTime: '10:00', endTime: '17:00');

      expect(updated.dayOfWeek, 3);
      expect(updated.isWorking, isTrue);
      expect(updated.startTime, '10:00');
    });
  });

  group('StaffBreakEntry.fromJson', () {
    test('parses id/day/times as required (non-nullable) fields', () {
      final entry = StaffBreakEntry.fromJson({'id': 7, 'day_of_week': 2, 'start_time': '13:00', 'end_time': '14:00'});

      expect(entry.id, 7);
      expect(entry.dayOfWeek, 2);
      expect(entry.startTime, '13:00');
      expect(entry.endTime, '14:00');
    });
  });

  group('StaffLeaveEntry.fromJson', () {
    test('reason is optional', () {
      final withReason = StaffLeaveEntry.fromJson({
        'id': 3,
        'start_date': '2026-09-01',
        'end_date': '2026-09-03',
        'reason': 'Family event',
        'status': 'approved',
      });
      final withoutReason = StaffLeaveEntry.fromJson({
        'id': 4,
        'start_date': '2026-09-10',
        'end_date': '2026-09-10',
        'status': 'pending',
      });

      expect(withReason.reason, 'Family event');
      expect(withoutReason.reason, isNull);
      expect(withoutReason.status, 'pending');
    });
  });
}
