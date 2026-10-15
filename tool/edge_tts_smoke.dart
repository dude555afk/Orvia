import 'dart:io';
import 'package:orvia/core/services/tts/edge_modern_client.dart';

Future<void> main() async {
  try {
    final result = await EdgeModernClient.synthesize(
      'Testing Orvia Edge neural voice.',
      'en-US-AriaNeural',
    );
    if (result.length < 1024) {
      throw StateError('Edge returned suspiciously short audio: ${result.length}');
    }
    stdout.writeln('Verified real Edge audio; bytes: ${result.length}');
  } catch (e, st) {
    stderr.writeln('Edge voice smoke test failed: $e\n$st');
    exitCode = 1;
  }
}
