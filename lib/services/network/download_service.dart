import 'dart:io';

import 'package:medito/exceptions/app_error.dart';

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  // Without these a stalled connection never completes and never fails: the
  // download sat at "downloading" until the app was killed.
  static const _connectTimeout = Duration(seconds: 30);
  static const _stallTimeout = Duration(seconds: 60);

  final _client = HttpClient()..connectionTimeout = _connectTimeout;

  factory DownloadService() {
    return _instance;
  }

  DownloadService._internal();

  Future<void> downloadFile(
    String url,
    String savePath, {
    void Function(int received, int total)? onProgress,
  }) async {
    final request = await _client.getUrl(Uri.parse(url));
    request.headers.add(HttpHeaders.acceptEncodingHeader, '*');

    final response = await request.close().timeout(_stallTimeout);
    final contentLength = response.contentLength;
    var receivedBytes = 0;

    // Stream into a sibling `.part` file and only move it into place once the
    // whole body has arrived. Writing straight to savePath left a truncated
    // file behind whenever the connection dropped mid-body, and callers decide
    // whether something is downloaded by checking that the file exists — so a
    // fragment was cached as a complete download forever, and the audio player
    // failed on it every time with no way to recover.
    final partialFile = File('$savePath.part');
    final sink = partialFile.openWrite();
    var sinkClosed = false;

    Future<void> closeSink() async {
      if (sinkClosed) return;
      sinkClosed = true;
      await sink.close();
    }

    try {
      // Times out when no bytes arrive for [_stallTimeout], however long the
      // whole file takes.
      await for (final chunk in response.timeout(_stallTimeout)) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(receivedBytes, contentLength);
      }
      await closeSink();

      if (response.statusCode >= 400) {
        throw switch (response.statusCode) {
          HttpStatus.notFound => const NotFoundError(),
          HttpStatus.unauthorized => const UnauthorizedError(),
          >= 500 => const ServerError(),
          _ => const UnknownError(),
        };
      }

      await partialFile.rename(savePath);
    } catch (_) {
      await closeSink();
      if (await partialFile.exists()) {
        await partialFile.delete();
      }
      rethrow;
    }
  }

  void dispose() {
    _client.close();
  }
}
