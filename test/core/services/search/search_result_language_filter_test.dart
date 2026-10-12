import 'package:flutter_test/flutter_test.dart';
import 'package:orvia/core/services/search/search_result_language_filter.dart';
import 'package:orvia/core/services/search/search_service.dart';

void main() {
  test('removes Chinese search results and provider answers', () {
    final original = SearchResult(
      answer: '中文回答',
      items: [
        SearchResultItem(
          title: 'Flutter docs',
          url: 'https://flutter.dev',
          text: 'Build apps with Flutter.',
        ),
        SearchResultItem(
          title: '电影频道 Movie',
          url: 'https://example.com/movie',
          text: 'Movie listing',
        ),
        SearchResultItem(
          title: 'More videos',
          url: 'https://example.com/videos',
          text: '剧情简介 Chinese-language description',
        ),
      ],
    );

    final filtered = filterChineseSearchResults(original);

    expect(filtered.answer, isNull);
    expect(filtered.items, hasLength(1));
    expect(filtered.items.single.title, 'Flutter docs');
    expect(filtered.items.single.url, 'https://flutter.dev');
    expect(original.items, hasLength(3));
  });

  test('preserves English answers and result metadata', () {
    final original = SearchResult(
      answer: 'An English summary.',
      items: [
        SearchResultItem(
          title: 'Video',
          url: 'https://youtube.com/watch?v=example',
          text: 'Video description',
          id: 'abc123',
          index: 2,
        ),
      ],
    );

    final filtered = filterChineseSearchResults(original);

    expect(filtered.answer, 'An English summary.');
    expect(filtered.items.single.id, 'abc123');
    expect(filtered.items.single.index, 2);
  });
}
