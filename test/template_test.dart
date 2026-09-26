import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku/core/parsing/template.dart';

void main() {
  test('replaces known placeholders', () {
    final result = applyTemplate('{a}/{b}', {'a': 'x', 'b': 'y'});
    expect(result, 'x/y');
  });

  test('leaves unknown placeholders untouched', () {
    final result = applyTemplate('{a}/{missing}', {'a': 'x'});
    expect(result, 'x/{missing}');
  });

  test('skips null values', () {
    final result = applyTemplate('{a}', {'a': null});
    expect(result, '{a}');
  });

  test('percent-encodes when requested', () {
    final result = applyTemplate('q={q}', {'q': 'one piece'}, encodeValues: true);
    expect(result, 'q=one%20piece');
  });
}
