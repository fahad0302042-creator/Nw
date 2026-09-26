import 'package:flutter_test/flutter_test.dart';
import 'package:kurayomi/data/library/library_updater.dart';

void main() {
  group('UpdateResult.summary', () {
    test('reports nothing found', () {
      const r = UpdateResult(
        titlesWithUpdates: 0,
        newUnits: 0,
        updatedTitles: [],
        failures: [],
      );
      expect(r.summary, 'No new chapters');
    });

    test('mentions failures even when nothing was found', () {
      const r = UpdateResult(
        titlesWithUpdates: 0,
        newUnits: 0,
        updatedTitles: [],
        failures: ['A', 'B'],
      );
      expect(r.summary, contains('2 failed'));
    });

    test('uses singular and plural correctly', () {
      const one = UpdateResult(
        titlesWithUpdates: 1,
        newUnits: 3,
        updatedTitles: ['A'],
        failures: [],
      );
      expect(one.summary, '3 new in 1 title');

      const many = UpdateResult(
        titlesWithUpdates: 2,
        newUnits: 5,
        updatedTitles: ['A', 'B'],
        failures: [],
      );
      expect(many.summary, '5 new in 2 titles');
    });

    test('cancellation wins over everything else', () {
      const r = UpdateResult(
        titlesWithUpdates: 4,
        newUnits: 9,
        updatedTitles: ['A'],
        failures: [],
        cancelled: true,
      );
      expect(r.summary, 'Update cancelled');
    });

    test('empty constructor is a no-op result', () {
      const r = UpdateResult.empty();
      expect(r.newUnits, 0);
      expect(r.summary, 'No new chapters');
    });
  });
}
