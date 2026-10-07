import 'package:Kelivo/core/services/tts/tts_text_chunker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TtsTextChunker', () {
    test('splits long text on sentence boundaries', () {
      final chunks = TtsTextChunker.split(
        '\u7B2C\u4E00\u53E5\u5F88\u77ED。\u7B2C\u4E8C\u53E5\u4E5F\u4E0D\u957F！Third sentence is readable. '
        'Fourth sentence should start a new chunk.',
        maxChunkLength: 32,
      );

      expect(chunks, hasLength(greaterThan(1)));
      expect(chunks.every((chunk) => chunk.text.length <= 32), isTrue);
      expect(
        chunks.first.text,
        '\u7B2C\u4E00\u53E5\u5F88\u77ED。\u7B2C\u4E8C\u53E5\u4E5F\u4E0D\u957F！',
      );
      expect(chunks.first.startOffset, 0);
      expect(chunks[1].startOffset, chunks.first.text.length);
    });

    test('hard-splits unpunctuated text without dropping characters', () {
      final source = List.filled(95, 'a').join();
      final chunks = TtsTextChunker.split(source, maxChunkLength: 30);

      expect(chunks.map((chunk) => chunk.text).join(), source);
      expect(chunks.map((chunk) => chunk.text.length), [30, 30, 30, 5]);
      expect(chunks.last.startOffset, 90);
    });

    test('returns no chunks for blank input', () {
      expect(TtsTextChunker.split('   \n\n  '), isEmpty);
    });
  });
}
