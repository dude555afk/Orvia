import '../../../shared/widgets/markdown_line_lexer.dart';

/// Builds a speech-only version of chat text. Displayed messages stay intact.
final class TtsSpeechTextCleaner {
  const TtsSpeechTextCleaner._();

  static final RegExp _fenceContainerPrefix = RegExp(
    r'^[ \t]*(?:(?:>[ \t]*)|(?:(?:[*+-]|\d+\.)[ \t]+))*',
  );

  static String clean(String input) {
    if (input.trim().isEmpty) return '';

    var text = _removeFencedCode(input);

    // Preserve short display names, but never narrate executable inline code.
    text = text.replaceAllMapped(
      RegExp(r'(`+)([^`\r\n]*?)\1'),
      (match) {
        final label = (match.group(2) ?? '').trim();
        return RegExp(r'^[A-Za-z][A-Za-z0-9 ._+#/-]{0,60}
    text = text.replaceAll(RegExp(r'\uE200[\s\S]*?\uE201'), ' ');
    text = text.replaceAll(
      RegExp(
        r'【(?:turn\d+[a-z]+\d+|[a-f0-9]{20,}|afn[a-z0-9]{15,})】',
        caseSensitive: false,
      ),
      ' ',
    );
    text = text.replaceAll(
      RegExp(r'^\s*\[\^[^\]]+\]:.*$', multiLine: true),
      '',
    );
    text = text.replaceAll(RegExp(r'\[\^[^\]]+\]'), ' ');
    text = text.replaceAll(RegExp(r'\[\d+\]'), ' ');
    text = text.replaceAll(
      RegExp(
        r'\b(?:cite|citation)\s*:\s*[a-f0-9]{24,}\b',
        caseSensitive: false,
      ),
      ' ',
    );

    // Keep link labels, but do not read out the destination or image syntax.
    text = text.replaceAll(RegExp(r'!\[[^\]]*\]\([^\r\n)]*\)'), ' ');
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]\r\n]+)\]\([^\r\n)]*\)'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAll(RegExp(r'<(?:https?://|www\.)[^>\s]+>'), ' ');
    text = text.replaceAll(
      RegExp(r'(?:https?://|www\.)[^\s<>)\]]+', caseSensitive: false),
      ' ',
    );
    text = text.replaceAll(
      RegExp(r'<\/?[a-z][a-z0-9]*(?:\s[^<>]*)?>', caseSensitive: false),
      ' ',
    );

    text = text.replaceAll(
      RegExp(
        r'^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)*\|?\s*$',
        multiLine: true,
      ),
      ' ',
    );
    text = text.replaceAll(RegExp(r'^\s*[-*_]{3,}\s*$', multiLine: true), ' ');
    text = text.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^\s{0,3}>+\s*', multiLine: true), '');
    text = text.replaceAll(
      RegExp(r'^\s{0,3}(?:[-*+]|\d+[.)])\s+', multiLine: true),
      '',
    );
    text = text.replaceAll(RegExp(r'^\s*\[[ xX]\]\s*', multiLine: true), '');
    text = text.replaceAll('**', '');
    text = text.replaceAll('~~', '');
    text = text.replaceAllMapped(
      RegExp(r'\*([^\s*](?:[^\r\n]*?[^\s*])?)\*'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'(?<!\w)_([^\s_](?:[^\r\n]*?[^\s_])?)_(?!\w)'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAll(String.fromCharCode(0x60), '');
    text = text.replaceAll('|', ', ');
    text = text.replaceAll(RegExp(r'[✅☑✔✓]'), ' yes ');
    text = text.replaceAll(RegExp(r'[❌✗✘]'), ' no ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _removeFencedCode(String input) {
    final lexer = MarkdownLineLexer();
    final lines = <String>[];
    for (final line in input.split('\n')) {
      final prefix = _fenceContainerPrefix.firstMatch(line);
      final unwrapped = line.substring(prefix?.end ?? 0);
      lines.add(lexer.consumeFence(unwrapped) ? '' : line);
    }
    return lines.join('\n');
  }
}
).hasMatch(label)
            ? label
            : ' ';
      },
    );
    text = markdownRemoveCode(text);

    // Citation payloads are metadata, never words to narrate.
    text = text.replaceAll(RegExp(r'\uE200[\s\S]*?\uE201'), ' ');
    text = text.replaceAll(
      RegExp(
        r'【(?:turn\d+[a-z]+\d+|[a-f0-9]{20,}|afn[a-z0-9]{15,})】',
        caseSensitive: false,
      ),
      ' ',
    );
    text = text.replaceAll(
      RegExp(r'^\s*\[\^[^\]]+\]:.*$', multiLine: true),
      '',
    );
    text = text.replaceAll(RegExp(r'\[\^[^\]]+\]'), ' ');
    text = text.replaceAll(RegExp(r'\[\d+\]'), ' ');
    text = text.replaceAll(
      RegExp(
        r'\b(?:cite|citation)\s*:\s*[a-f0-9]{24,}\b',
        caseSensitive: false,
      ),
      ' ',
    );

    // Keep link labels, but do not read out the destination or image syntax.
    text = text.replaceAll(RegExp(r'!\[[^\]]*\]\([^\r\n)]*\)'), ' ');
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]\r\n]+)\]\([^\r\n)]*\)'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAll(RegExp(r'<(?:https?://|www\.)[^>\s]+>'), ' ');
    text = text.replaceAll(
      RegExp(r'(?:https?://|www\.)[^\s<>)\]]+', caseSensitive: false),
      ' ',
    );
    text = text.replaceAll(
      RegExp(r'<\/?[a-z][a-z0-9]*(?:\s[^<>]*)?>', caseSensitive: false),
      ' ',
    );

    text = text.replaceAll(
      RegExp(
        r'^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)*\|?\s*$',
        multiLine: true,
      ),
      ' ',
    );
    text = text.replaceAll(RegExp(r'^\s*[-*_]{3,}\s*$', multiLine: true), ' ');
    text = text.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^\s{0,3}>+\s*', multiLine: true), '');
    text = text.replaceAll(
      RegExp(r'^\s{0,3}(?:[-*+]|\d+[.)])\s+', multiLine: true),
      '',
    );
    text = text.replaceAll(RegExp(r'^\s*\[[ xX]\]\s*', multiLine: true), '');
    text = text.replaceAll('**', '');
    text = text.replaceAll('~~', '');
    text = text.replaceAllMapped(
      RegExp(r'\*([^\s*](?:[^\r\n]*?[^\s*])?)\*'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'(?<!\w)_([^\s_](?:[^\r\n]*?[^\s_])?)_(?!\w)'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAll(String.fromCharCode(0x60), '');
    text = text.replaceAll('|', ', ');
    text = text.replaceAll(RegExp(r'[✅☑✔✓]'), ' yes ');
    text = text.replaceAll(RegExp(r'[❌✗✘]'), ' no ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _removeFencedCode(String input) {
    final lexer = MarkdownLineLexer();
    final lines = <String>[];
    for (final line in input.split('\n')) {
      final prefix = _fenceContainerPrefix.firstMatch(line);
      final unwrapped = line.substring(prefix?.end ?? 0);
      lines.add(lexer.consumeFence(unwrapped) ? '' : line);
    }
    return lines.join('\n');
  }
}
