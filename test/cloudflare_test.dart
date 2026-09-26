import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurayomi/data/net/cloudflare.dart';

Response<String> res(
  int status, {
  String body = '',
  Map<String, List<String>> headers = const {},
}) =>
    Response<String>(
      requestOptions: RequestOptions(path: 'https://site.test'),
      statusCode: status,
      data: body,
      headers: Headers.fromMap({
        'content-type': ['text/html'],
        ...headers,
      }),
    );

void main() {
  group('ChallengeDetector', () {
    test('detects the cf-mitigated header regardless of status', () {
      expect(
        ChallengeDetector.isChallenge(res(200, headers: {
          'cf-mitigated': ['challenge']
        })),
        isTrue,
      );
    });

    test('detects the classic interstitial bodies', () {
      expect(
          ChallengeDetector.isChallenge(
              res(403, body: '<html><title>Just a moment...</title></html>')),
          isTrue);
      expect(
          ChallengeDetector.isChallenge(
              res(503, body: '<html>window._cf_chl_opt = {}</html>')),
          isTrue);
      expect(
          ChallengeDetector.isChallenge(
              res(403, body: '<html>cf-browser-verification</html>')),
          isTrue);
    });

    test('detects DDoS-Guard and Sucuri too', () {
      expect(
          ChallengeDetector.isChallenge(
              res(403, body: '<html>DDoS-Guard protection</html>')),
          isTrue);
      expect(ChallengeDetector.describe(res(403, body: '<html>DDoS-Guard</html>')),
          'DDoS-Guard');
      expect(
          ChallengeDetector.describe(
              res(403, body: '<html>sucuri_cloudproxy</html>')),
          'Sucuri');
    });

    test('a 403 with a JSON body is a real auth error, not a challenge', () {
      // This is the important one: throwing a WebView at a genuine 403 from
      // an API endpoint would be maddening for the user.
      final r = Response<String>(
        requestOptions: RequestOptions(path: 'https://api.site.test/v1'),
        statusCode: 403,
        data: '{"error":"forbidden"}',
        headers: Headers.fromMap({
          'content-type': ['application/json']
        }),
      );
      expect(ChallengeDetector.isChallenge(r), isFalse);
    });

    test('ordinary responses are left alone', () {
      expect(ChallengeDetector.isChallenge(res(200, body: '<html>ok</html>')),
          isFalse);
      expect(ChallengeDetector.isChallenge(res(404, body: '<html>nope</html>')),
          isFalse);
      expect(ChallengeDetector.isChallenge(res(500, body: '<html>boom</html>')),
          isFalse);
    });

    test('a bare 403 with no challenge markers is not a challenge', () {
      expect(ChallengeDetector.isChallenge(res(403, body: '<html>denied</html>')),
          isFalse);
    });
  });

  test('ChallengeFailedException reads clearly', () {
    final e = ChallengeFailedException('https://site.test', 'cancelled');
    expect(e.toString(), contains('site.test'));
    expect(e.toString(), contains('cancelled'));
  });
}
