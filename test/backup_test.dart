import 'package:flutter_test/flutter_test.dart';
import 'package:kurayomi/data/backup/backup_service.dart';

Map<String, dynamic> good() => {
      'app': 'Kurayomi',
      'format': BackupService.formatVersion,
      'createdAt': '2026-01-01T00:00:00.000',
      'items': <dynamic>[],
      'categories': <dynamic>[],
    };

void main() {
  group('BackupService.validate', () {
    test('accepts a well-formed backup', () {
      expect(BackupService.validate(good()), isNull);
    });

    test('rejects a file from another app', () {
      // Restoring a Mihon/Tachiyomi backup would silently do nothing useful,
      // so say so rather than "0 items restored".
      final data = good()..['app'] = 'Mihon';
      expect(BackupService.validate(data), contains('Not a Kurayomi backup'));
    });

    test('rejects a backup from a newer app version', () {
      final data = good()..['format'] = BackupService.formatVersion + 1;
      final problem = BackupService.validate(data);
      expect(problem, contains('newer version'));
      expect(problem, contains('${BackupService.formatVersion}'));
    });

    test('rejects a missing or non-integer format', () {
      expect(BackupService.validate(good()..remove('format')),
          contains('format version'));
      expect(BackupService.validate(good()..['format'] = 'one'),
          contains('format version'));
    });

    test('rejects a backup with no items list', () {
      expect(BackupService.validate(good()..remove('items')),
          contains('no library data'));
      expect(BackupService.validate(good()..['items'] = 'nope'),
          contains('no library data'));
    });

    test('an older format version is still accepted', () {
      final data = good()..['format'] = 0;
      expect(BackupService.validate(data), isNull);
    });
  });
}
