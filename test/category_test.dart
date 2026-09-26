import 'package:flutter_test/flutter_test.dart';
import 'package:kurayomi/domain/models/category.dart';

void main() {
  test('virtual categories use negative ids so they cannot clash with rows',
      () {
    expect(LibraryCategory.all.id, lessThan(0));
    expect(LibraryCategory.uncategorized.id, lessThan(0));
    expect(LibraryCategory.all.id,
        isNot(equals(LibraryCategory.uncategorized.id)));
    expect(LibraryCategory.all.isVirtual, isTrue);
  });

  test('a real category is not virtual', () {
    const c = LibraryCategory(id: 1, name: 'Reading', sortOrder: 0);
    expect(c.isVirtual, isFalse);
  });

  test('round-trips through a database row', () {
    const c = LibraryCategory(id: 7, name: 'On hold', sortOrder: 2);
    final restored = LibraryCategory.fromRow({'id': 7, ...c.toRow()});
    expect(restored.id, 7);
    expect(restored.name, 'On hold');
    expect(restored.sortOrder, 2);
  });
}
