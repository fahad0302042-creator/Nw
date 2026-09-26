import 'package:dio/dio.dart';

/// Shared Dio instance used by the source engine and extension repository
/// fetcher. Extensions can still override headers per-request.
class AppHttpClient {
  AppHttpClient._();

  static final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (status) => status != null && status < 500,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) Tsundoku/0.1 (+https://github.com)'
      },
    ),
  );
}
