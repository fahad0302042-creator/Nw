import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku/core/parsing/url_utils.dart';

void main() {
  test('leaves absolute URLs untouched', () {
    expect(resolveUrl('https://example.com/a', 'https://base.com'), 'https://example.com/a');
  });

  test('resolves relative paths against base', () {
    expect(resolveUrl('/manga/1', 'https://example.com'), 'https://example.com/manga/1');
  });

  test('passes through null/empty', () {
    expect(resolveUrl(null, 'https://example.com'), isNull);
    expect(resolveUrl('', 'https://example.com'), '');
  });
}
