import 'search_service.dart';

// The app presents web-search tool output in English. Upstream providers can
// ignore language preferences and return Chinese titles or snippets.
// Exclude those entries before their text reaches the model or the tool UI.
final RegExp _chineseCharacters = RegExp(r'[\u3400-\u9FFF\uF900-\uFAFF]');

SearchResult filterChineseSearchResults(SearchResult result) {
  final answer = result.answer;
  return SearchResult(
    answer: answer != null && !_chineseCharacters.hasMatch(answer)
        ? answer
        : null,
    items: result.items
        .where(
          (item) =>
              !_chineseCharacters.hasMatch(item.title) &&
              !_chineseCharacters.hasMatch(item.text),
        )
        .toList(),
  );
}
