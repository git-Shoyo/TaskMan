import 'package:flutter_test/flutter_test.dart';
import 'package:taskman/systems/app_user.dart';

void main() {
  group('AppUser', () {
    test('normalizes searchable values', () {
      expect(
        AppUser.normalizeSearchValue('  User.Name@example.com  '),
        'user.name@example.com',
      );
      expect(AppUser.normalizeSearchValue(null), '');
    });

    test('reads user id from taskman uri qr value', () {
      expect(
        AppUser.readSearchValueFromQr('taskman://user/member-123'),
        'member-123',
      );
      expect(
        AppUser.readSearchValueFromQr('taskman://invite?userId=member-456'),
        'member-456',
      );
    });

    test('reads user id from json qr value', () {
      expect(
        AppUser.readSearchValueFromQr('{"userId":"member-789"}'),
        'member-789',
      );
      expect(
        AppUser.readSearchValueFromQr('{"email":"user@example.com"}'),
        'user@example.com',
      );
    });
  });
}
