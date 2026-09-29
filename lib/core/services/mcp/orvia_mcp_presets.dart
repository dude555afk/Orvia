/// Curated optional MCP starter catalogue adapted from Kai's PopularMcpServers.
/// These are discovery presets, not connected services. Endpoints may change and
/// each service's terms, authentication, and availability must be checked at use.
class OrviaMcpPreset {
  const OrviaMcpPreset({
    required this.name,
    required this.url,
    required this.description,
    this.requiresAuth = false,
  });

  final String name;
  final String url;
  final String description;
  final bool requiresAuth;
}

const orviaMcpPresets = <OrviaMcpPreset>[
  OrviaMcpPreset(
    name: 'Context7',
    url: 'https://mcp.context7.com/mcp',
    description: 'Library and framework documentation',
  ),
  OrviaMcpPreset(
    name: 'MDN',
    url: 'https://mcp.mdn.mozilla.net',
    description: 'Web development documentation',
  ),
  OrviaMcpPreset(
    name: 'DeepWiki',
    url: 'https://mcp.deepwiki.com/mcp',
    description: 'Repository documentation',
  ),
  OrviaMcpPreset(
    name: 'Parallel Search',
    url: 'https://search.parallel.ai/mcp',
    description: 'Web search and extraction',
  ),
  OrviaMcpPreset(
    name: 'Yahoo Finance',
    url: 'https://gateway.mcpservers.org/yahoo-finance/mcp',
    description: 'Market information',
  ),
  OrviaMcpPreset(
    name: 'CoinGecko',
    url: 'https://mcp.api.coingecko.com/mcp',
    description: 'Cryptocurrency market information',
  ),
  OrviaMcpPreset(
    name: 'Jina AI',
    url: 'https://mcp.jina.ai/v1',
    description: 'Web reading and search',
    requiresAuth: true,
  ),
  OrviaMcpPreset(
    name: 'Open-Meteo Weather',
    url: 'https://mcp.open-mcp.org/api/server/open-weather@latest/mcp',
    description: 'Weather and air quality',
  ),
  OrviaMcpPreset(
    name: 'Kiwi.com',
    url: 'https://mcp.kiwi.com',
    description: 'Flight search',
  ),
  OrviaMcpPreset(
    name: 'Malwarebytes',
    url: 'https://scamguard.malwarebytes.com/claude/mcp',
    description: 'Scam and link checks',
  ),
  OrviaMcpPreset(
    name: 'tldraw',
    url: 'https://tldraw-mcp-app.tldraw.workers.dev/mcp',
    description: 'Diagrams and whiteboards',
  ),
  OrviaMcpPreset(
    name: 'Find-A-Domain',
    url: 'https://api.findadomain.dev/mcp',
    description: 'Domain availability',
  ),
  OrviaMcpPreset(
    name: 'SubwayInfo NYC',
    url: 'https://subwayinfo.nyc/mcp',
    description: 'Transit information',
  ),
];
