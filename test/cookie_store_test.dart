import 'package:flutter_test/flutter_test.dart';
import 'package:kurayomi/data/net/cookie_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CookieStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await CookieStore.instance();
    await store.clearAll();
  });

  test('hostOf extracts and lowercases the host', () {
    expect(CookieStore.hostOf('https://Site.Test/a/b?c=1'), 'site.test');
    expect(CookieStore.hostOf('not a url'), '');
  });

  test('stores and rebuilds a Cookie header', () async {
    await store.saveCookies('https://site.test/x', {
      'cf_clearance': 'abc',
      'session': 'xyz',
    });

    final header = store.cookieHeader('https://site.test/other');
    expect(header, contains('cf_clearance=abc'));
    expect(header, contains('session=xyz'));
  });

  test('sends parent-domain cookies to subdomains, as a browser does', () async {
    await store.saveCookies('https://site.test', {'a': '1'});
    expect(store.cookieHeader('https://cdn.site.test/img.jpg'), contains('a=1'));
    // ...but not to an unrelated host that merely ends similarly.
    expect(store.cookieHeader('https://notsite.test'), isNull);
  });

  test('parses Set-Cookie headers, ignoring attributes', () async {
    await store.ingestSetCookie('https://site.test', [
      'cf_clearance=v1; path=/; expires=Wed, 01 Jan 2025 00:00:00 GMT; HttpOnly',
      'theme=dark; Path=/',
      'malformed-no-equals',
    ]);

    final header = store.cookieHeader('https://site.test')!;
    expect(header, contains('cf_clearance=v1'));
    expect(header, contains('theme=dark'));
    expect(header, isNot(contains('HttpOnly')));
    expect(header, isNot(contains('path')));
  });

  test('tracks clearance per host', () async {
    await store.saveCookies('https://a.test', {'cf_clearance': 'x'});
    await store.saveCookies('https://b.test', {'session': 'y'});

    expect(store.hasClearance('https://a.test'), isTrue);
    expect(store.hasClearance('https://b.test'), isFalse);
  });

  test('pins a User-Agent per host, falling back to the default', () async {
    expect(store.userAgentFor('https://site.test'),
        CookieStore.defaultUserAgent);

    await store.saveUserAgent('https://site.test', 'CustomUA/1.0');
    expect(store.userAgentFor('https://site.test'), 'CustomUA/1.0');
    expect(store.userAgentFor('https://other.test'),
        CookieStore.defaultUserAgent);
  });

  test('clearHost removes only that host', () async {
    await store.saveCookies('https://a.test', {'k': '1'});
    await store.saveCookies('https://b.test', {'k': '2'});

    await store.clearHost('https://a.test');

    expect(store.cookieHeader('https://a.test'), isNull);
    expect(store.cookieHeader('https://b.test'), contains('k=2'));
    expect(store.knownHosts, ['b.test']);
  });
}
