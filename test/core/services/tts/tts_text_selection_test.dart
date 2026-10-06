import 'package:Kelivo/core/services/tts/tts_text_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TtsTextSelection', () {
    test('keeps full text by default', () {
      expect(
        TtsTextSelection.apply(
          '\u65C1\u767D “\u4F60\u597D” (\u52A8\u4F5C)',
          mode: TtsTextSelectionMode.fullText,
        ),
        '\u65C1\u767D “\u4F60\u597D” (\u52A8\u4F5C)',
      );
    });

    test('extracts full-width and half-width quoted text', () {
      expect(
        TtsTextSelection.apply(
          '\u65C1\u767D “\u4F60\u597D” then \'\u4E16\u754C\' and "again" plus ‘\u518D\u89C1’.',
          mode: TtsTextSelectionMode.quotedOnly,
        ),
        '\u4F60\u597D\n\u4E16\u754C\nagain\n\u518D\u89C1',
      );
    });

    test('ignores quoted text inside fenced and inline code', () {
      expect(
        TtsTextSelection.apply(
          '\u65C1\u767D “\u4FDD\u7559”\n'
          '```dart\n'
          'print("\u4EE3\u7801\u5757");\n'
          '```\n'
          '\u4EE5\u53CA `print("\u884C\u5185\u4EE3\u7801")`。',
          mode: TtsTextSelectionMode.quotedOnly,
        ),
        '\u4FDD\u7559',
      );
    });

    test('ignores quoted text inside all supported fence forms', () {
      for (final source in const [
        '\u65C1\u767D “\u4FDD\u7559”\n~~~dart\nprint("\u6CE2\u6D6A\u7EBF");\n~~~',
        '\u65C1\u767D “\u4FDD\u7559”\n````markdown\n```\nprint("\u53D8\u957F\u56F4\u680F");\n````',
        '\u65C1\u767D “\u4FDD\u7559”\n```dart\n``` not-a-closer\nprint("\u4F2A\u5173\u95ED");\n```',
        '\u65C1\u767D “\u4FDD\u7559”\n> ```dart\n> print("\u5F15\u7528\u56F4\u680F");\n> ```',
        '\u65C1\u767D “\u4FDD\u7559”\n```dart\nprint("\u672A\u95ED\u5408");',
      ]) {
        expect(
          TtsTextSelection.apply(source, mode: TtsTextSelectionMode.quotedOnly),
          '\u4FDD\u7559',
          reason: source,
        );
      }
    });

    test('ignores quoted text inside multi-backtick inline code', () {
      expect(
        TtsTextSelection.apply(
          '\u65C1\u767D “\u4FDD\u7559”\u4EE5\u53CA ``print("\u884C\u5185\u4EE3\u7801")``。',
          mode: TtsTextSelectionMode.quotedOnly,
        ),
        '\u4FDD\u7559',
      );
    });

    test('does not pair unmatched backticks across lines', () {
      expect(
        TtsTextSelection.apply(
          '`\u7B2C\u4E00\u884C\n\u65C1\u767D “\u5E94\u6717\u8BFB”\n\u7B2C\u4E09\u884C`',
          mode: TtsTextSelectionMode.quotedOnly,
        ),
        '\u5E94\u6717\u8BFB',
      );
    });

    test('extracts half-width quotes next to CJK text but skips apostrophes', () {
      expect(
        TtsTextSelection.apply(
          '\u4ED6\u8BF4\'\u4F60\u597D\'，\u5979\u8BF4"\u4E16\u754C"，don\'t read apostrophes.',
          mode: TtsTextSelectionMode.quotedOnly,
        ),
        '\u4F60\u597D\n\u4E16\u754C',
      );
    });

    test('does not close an unmatched quote with an apostrophe in a word', () {
      expect(
        TtsTextSelection.apply(
          '\u4ED6\u8BF4\'\u4F60\u597D，don\'t stop.',
          mode: TtsTextSelectionMode.quotedOnly,
        ),
        '\u4ED6\u8BF4\'\u4F60\u597D，don\'t stop.',
      );
    });

    test('keeps text outside full-width and half-width parentheses', () {
      expect(
        TtsTextSelection.apply(
          '\u4F60\u597D（\u52A8\u4F5C）\u4E16\u754C (stage direction) \u7EE7\u7EED',
          mode: TtsTextSelectionMode.outsideParentheses,
        ),
        '\u4F60\u597D \u4E16\u754C \u7EE7\u7EED',
      );
    });

    test('extracts markdown and html italic text', () {
      expect(
        TtsTextSelection.apply(
          '\u6B63\u4F53 *\u659C\u4F53\u4E00* and _\u659C\u4F53\u4E8C_ plus <em>\u659C\u4F53\u4E09</em>.',
          mode: TtsTextSelectionMode.italicOnly,
        ),
        '\u659C\u4F53\u4E00\n\u659C\u4F53\u4E8C\n\u659C\u4F53\u4E09',
      );
    });

    test('ignores italic text inside fenced and inline code', () {
      expect(
        TtsTextSelection.apply(
          '\u65C1\u767D *\u4FDD\u7559*\n'
          '```dart\n'
          'final value = "*\u4EE3\u7801\u5757*";\n'
          '```\n'
          '\u4EE5\u53CA `_\u884C\u5185\u4EE3\u7801_`。',
          mode: TtsTextSelectionMode.italicOnly,
        ),
        '\u4FDD\u7559',
      );
    });

    test('removes markdown and html italic text for non-italic mode', () {
      expect(
        TtsTextSelection.apply(
          '\u6B63\u4F53 *\u659C\u4F53\u4E00* and _\u659C\u4F53\u4E8C_ plus <i>\u659C\u4F53\u4E09</i> done.',
          mode: TtsTextSelectionMode.nonItalic,
        ),
        '\u6B63\u4F53 and plus done.',
      );
    });

    test('falls back to original text when selected content is empty', () {
      expect(
        TtsTextSelection.apply(
          '\u6CA1\u6709\u5F15\u53F7\u7684\u5185\u5BB9',
          mode: TtsTextSelectionMode.quotedOnly,
        ),
        '\u6CA1\u6709\u5F15\u53F7\u7684\u5185\u5BB9',
      );
    });

    test('fallback excludes code when no selected content remains', () {
      expect(
        TtsTextSelection.apply(
          '\u666E\u901A\u65C1\u767D\n'
          '```dart\n'
          'print("\u4E0D\u5E94\u6717\u8BFB");\n'
          '```',
          mode: TtsTextSelectionMode.quotedOnly,
        ),
        '\u666E\u901A\u65C1\u767D',
      );
    });
  });
}
