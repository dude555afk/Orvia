import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'edge_v2_token.dart';

/// Microsoft Edge Read Aloud (unofficial). No device/system voice fallback.
class EdgeModernClient {
  const EdgeModernClient._();

  static const _legacy =
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';
  static const _modern =
      'wss://api.msedgeservices.com/tts/cognitiveservices/websocket/v1';
  static const _origin = 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold';
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/155.0.0.0 Safari/537.36 Edg/155.0.0.0';

  static Uri endpoint({required bool modern, required String token}) {
    return Uri.parse(modern ? _modern : _legacy).replace(
      queryParameters: {
        modern ? 'Ocp-Apim-Subscription-Key' : 'TrustedClientToken':
            EdgeV2Token.clientKey,
        'Sec-MS-GEC': token,
        'Sec-MS-GEC-Version': EdgeV2Token.protocolVersion,
        'ConnectionId': const Uuid().v4().replaceAll('-', ''),
      },
    );
  }

  static String _xml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static int _audioHeaderEnd(List<int> bytes) {
    final delim = ascii.encode('Path:audio\r\n');
    for (var i = 0; i <= bytes.length - delim.length; i++) {
      var matches = true;
      for (var j = 0; j < delim.length; j++) {
        if (bytes[i + j] != delim[j]) {
          matches = false;
          break;
        }
      }
      if (matches) return i + delim.length;
    }
    return -1;
  }

  static Future<Uint8List> synthesize(String text, String voice) async {
    final token = EdgeV2Token.generate();
    Object? firstFailure;
    for (final modern in [false, true]) {
      try {
        return await _oneRequest(
          endpoint(modern: modern, token: token),
          text,
          voice,
        ).timeout(const Duration(seconds: 30));
      } catch (error) {
        firstFailure ??= error;
        if (modern) {
          throw StateError(
            'Edge neural voice could not connect on either Microsoft endpoint. '
            'First: $firstFailure. Second: $error',
          );
        }
      }
    }
    throw StateError('Edge TTS did not return audio');
  }

  static Future<Uint8List> _oneRequest(
    Uri uri,
    String text,
    String voice,
  ) async {
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: {
        'Origin': _origin,
        'User-Agent': _ua,
        'Pragma': 'no-cache',
        'Cache-Control': 'no-cache',
      },
    ).timeout(const Duration(seconds: 12));
    try {
      final stamp = DateTime.now().toUtc().toIso8601String();
      final requestId = const Uuid().v4().replaceAll('-', '');
      final speechConfig = jsonEncode({
        'context': {
          'synthesis': {
            'audio': {
              'metadataoptions': {
                'sentenceBoundaryEnabled': 'false',
                'wordBoundaryEnabled': 'false',
              },
              'outputFormat': 'audio-24khz-96kbitrate-mono-mp3',
            },
          },
        },
      });
      socket.add(
        'X-Timestamp:$stamp\r\n'
        'Content-Type:application/json; charset=utf-8\r\n'
        'Path:speech.config\r\n\r\n$speechConfig',
      );
      socket.add(
        'X-RequestId:$requestId\r\n'
        'Content-Type:application/ssml+xml\r\n'
        'X-Timestamp:$stamp\r\n'
        'Path:ssml\r\n\r\n'
        "<speak version='1.0' xml:lang='en-US'>"
        "<voice name='${_xml(voice)}'>${_xml(text)}</voice></speak>",
      );
      final audio = BytesBuilder(copy: false);
      var finished = false;
      await for (final message in socket) {
        if (message is String) {
          if (message.contains('Path:turn.end')) {
            finished = true;
            break;
          }
          continue;
        }
        if (message is! List<int>) continue;
        final end = _audioHeaderEnd(message);
        if (end >= 0) audio.add(message.sublist(end));
      }
      if (!finished || audio.length == 0) {
        throw const FormatException(
          'Edge WebSocket closed before completing audio synthesis.',
        );
      }
      return audio.takeBytes();
    } finally {
      await socket.close();
    }
  }
}
