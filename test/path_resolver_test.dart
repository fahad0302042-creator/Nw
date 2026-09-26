import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku/core/parsing/path_resolver.dart';

void main() {
  group('resolveJsonPath', () {
    test('returns root for empty/., \$', () {
      final root = {'a': 1};
      expect(resolveJsonPath(root, ''), root);
      expect(resolveJsonPath(root, '.'), root);
      expect(resolveJsonPath(root, r'$'), root);
    });

    test('resolves nested map keys', () {
      final root = {
        'attributes': {
          'title': {'en': 'One Piece'}
        }
      };
      expect(resolveJsonPath(root, 'attributes.title.en'), 'One Piece');
    });

    test('resolves list indices', () {
      final root = {
        'data': [
          {'name': 'a'},
          {'name': 'b'},
        ]
      };
      expect(resolveJsonPath(root, 'data.1.name'), 'b');
    });

    test('resolves filter segments on lists of maps', () {
      final root = {
        'relationships': [
          {'type': 'author', 'attributes': {'name': 'Oda'}},
          {'type': 'cover_art', 'attributes': {'fileName': 'cover.jpg'}},
        ]
      };
      expect(
        resolveJsonPath(root, 'relationships.type=cover_art.attributes.fileName'),
        'cover.jpg',
      );
      expect(
        resolveJsonPath(root, 'relationships.type=author.attributes.name'),
        'Oda',
      );
    });

    test('returns null for missing paths instead of throwing', () {
      expect(resolveJsonPath({'a': 1}, 'b.c.d'), isNull);
      expect(resolveJsonPath(null, 'a.b'), isNull);
    });

    test('resolveJsonPathAsString stringifies non-string values', () {
      expect(resolveJsonPathAsString({'n': 42}, 'n'), '42');
    });
  });
}
