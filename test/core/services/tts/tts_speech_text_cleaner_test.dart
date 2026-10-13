import 'package:flutter_test/flutter_test.dart';
import 'package:orvia/core/services/tts/tts_speech_text_cleaner.dart';

void main() {
  group('TtsSpeechTextCleaner', () {
    test('keeps meaning without reading Markdown and citation syntax', () {
      const input = '# STT options\n'
          '- **Local speech** works. citeturn0search2\n'
          '- ✅ [Sherpa](https://example.org/model) is available.\n'
          '> It also works for বাংলা. 【turn1search3】';
      final spoken = TtsSpeechTextCleaner.clean(input);

      expect(spoken, contains('STT options'));
      expect(spoken, contains('Local speech works.'));
      expect(spoken, contains('Sherpa is available.'));
      expect(spoken, contains('বাংলা.'));
      expect(spoken, isNot(contains('turn0search2')));
      expect(spoken, isNot(contains('https://')));
      expect(spoken, isNot(contains('**')));
      expect(spoken, isNot(contains('✅')));
    });

    test('skips fenced code, but keeps inline names', () {
      const source = 'Use `Edge TTS` for speech.\n'
          '~~~dart\nprint("do not narrate this code");\n~~~\n'
          'Normal explanation continues.';
      expect(
        TtsSpeechTextCleaner.clean(source),
        'Use Edge TTS for speech. Normal explanation continues.',
      );
    });

    test('skips reference identifiers, images and table dividers', () {
      const source = 'Model | Works\n'
          '|---|:---:|\n'
          'Whisper | ✅\n'
          '![Preview](https://assets.example.org/p.png)\n'
          'Result [4] [^ref] 【afn90c006461a560f54593f0bb8878c495】';
      final spoken = TtsSpeechTextCleaner.clean(source);
      expect(spoken, contains('Model , Works'));
      expect(spoken, contains('Whisper , yes'));
      expect(spoken, contains('Result'));
      expect(spoken, isNot(contains('---')));
      expect(spoken, isNot(contains('Preview')));
      expect(spoken, isNot(contains('afn90')));
      expect(spoken, isNot(contains('ref')));
    });

    test('preserves identifiers, equations, and Bengali', () {
      expect(
        TtsSpeechTextCleaner.clean(
          'foo_bar is fine. 2 * 3 = 6. STT and বাংলা.',
        ),
        'foo_bar is fine. 2 * 3 = 6. STT and বাংলা.',
      );
      expect(TtsSpeechTextCleaner.clean('   '), isEmpty);
    });
  });
}
