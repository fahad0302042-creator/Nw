import 'package:flutter_test/flutter_test.dart';
import 'package:kurayomi/extensions/repo_url.dart';

void main() {
  group('RepoUrl.normalize', () {
    test('leaves a direct index.json alone', () {
      const url = 'https://example.com/repo/index.json';
      expect(RepoUrl.normalize(url), url);
    });

    test('adds a missing scheme', () {
      expect(RepoUrl.normalize('example.com/repo/index.json'),
          'https://example.com/repo/index.json');
    });

    test('rewrites a GitHub blob page to raw content', () {
      // The single most common mistake: copying the page you are looking at.
      expect(
        RepoUrl.normalize(
            'https://github.com/someone/repo/blob/main/index.json'),
        'https://raw.githubusercontent.com/someone/repo/main/index.json',
      );
    });

    test('rewrites a GitHub tree URL and appends the filename', () {
      expect(
        RepoUrl.normalize('https://github.com/someone/repo/tree/main/dist'),
        'https://raw.githubusercontent.com/someone/repo/main/dist/index.json',
      );
    });

    test('appends index.json to a folder URL, with or without a slash', () {
      expect(RepoUrl.normalize('https://example.com/repo'),
          'https://example.com/repo/index.json');
      expect(RepoUrl.normalize('https://example.com/repo/'),
          'https://example.com/repo/index.json');
    });

    test('keeps a non-standard filename such as index.min.json', () {
      const url = 'https://example.com/repo/index.min.json';
      expect(RepoUrl.normalize(url), url);
    });

    test('trims surrounding whitespace from a paste', () {
      expect(RepoUrl.normalize('  https://example.com/a/index.json \n'),
          'https://example.com/a/index.json');
    });

    test('empty input stays empty rather than becoming "https://"', () {
      expect(RepoUrl.normalize('   '), '');
    });
  });

  group('isGithubPage', () {
    test('flags github.com but not raw.githubusercontent.com', () {
      expect(RepoUrl.isGithubPage('https://github.com/a/b'), isTrue);
      expect(
          RepoUrl.isGithubPage('https://raw.githubusercontent.com/a/b/c.json'),
          isFalse);
    });
  });
}
