import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orvia/core/services/search/providers/orvia_search_service.dart';
import 'package:orvia/core/services/search/search_service.dart';

void main() {
  test('Orvia requests English web results', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.host, 'search.psycheas.top');
      expect(request.url.path, '/v1/search');
      expect(request.url.queryParameters['q'], 'youtube videos');
      expect(request.url.queryParameters['count'], '2');
      expect(request.url.queryParameters['language'], 'en-US');
      expect(request.headers['Accept-Language'], 'en-US,en;q=0.9');

      return http.Response(
        jsonEncode({
          'results': [
            {
              'title': 'YouTube',
              'url': 'https://www.youtube.com',
              'content': 'Watch videos in English.',
            },
          ],
        }),
        200,
      );
    });

    final results = await OrviaSearchService(client: client).search(
      query: 'youtube videos',
      commonOptions: const SearchCommonOptions(resultSize: 2),
      serviceOptions: OrviaOptions(id: 'orvia'),
    );

    expect(results.items, hasLength(1));
    expect(results.items.single.title, 'YouTube');
    expect(results.items.single.text, 'Watch videos in English.');
  });
}
