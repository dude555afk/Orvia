/// Shared display-only model recognition for icons and fetched-model groups.
/// These name heuristics must not be used to infer API capabilities.
class ModelBrand {
  ModelBrand(this.group, String icon, String pattern)
    : asset = 'assets/icons/$icon',
      _pattern = RegExp('(^|[^a-z0-9])(?:$pattern)', caseSensitive: false);

  final String group;
  final String asset;
  final RegExp _pattern;

  static ModelBrand? match(String name) {
    final key = name.trim();
    // Prefer the model over its hosting namespace (e.g. google/gemma-4).
    final model = key.split('/').last;
    for (final candidate in model == key ? [key] : [model, key]) {
      for (final brand in _brands) {
        if (brand._pattern.hasMatch(candidate)) return brand;
      }
    }
    return null;
  }

  static final List<ModelBrand> _brands = [
    ModelBrand('GPT', 'openai.svg', r'(?:chat)?gpt|o[134](?=$|[^a-z0-9])'),
    ModelBrand('GPT', 'codex.svg', r'codex'),
    ModelBrand('Gemini', 'gemini-color.svg', r'gemini'),
    ModelBrand(
      'Gemma',
      'gemma-color.svg',
      r'(?:code|recurrent|shield|pali)?gemma',
    ),
    ModelBrand('Claude', 'claude-color.svg', r'claude'),
    ModelBrand('DeepSeek', 'deepseek-color.svg', r'deepseek'),
    ModelBrand(
      'Kimi',
      'kimi-color.svg',
      r'kimi|moonshot|'
          '\u6708'
          '\u4E4B'
          '\u6697'
          '\u9762'
          r'|k3(?=$|[^a-z0-9])',
    ),
    ModelBrand('Qwen', 'qwen-color.svg', r'(?:code)?qwen|qwq|qvq|dashscope'),
    ModelBrand(
      'Doubao',
      'doubao-color.svg',
      r'doubao|'
          '\u8C46'
          '\u5305'
          r'|seed(?:ance|ream|uplex|asr|tts)?(?=$|[^a-z0-9]|\d)',
    ),
    ModelBrand(
      'GLM',
      'zhipu-color.svg',
      r'(?:chat)?glm|zhipu|'
          '\u667A'
          '\u8C31',
    ),
    ModelBrand(
      'Hunyuan',
      'hunyuan-color.svg',
      r'hunyuan|'
          '\u6DF7'
          '\u5143'
          r'|hy[34](?=$|[^a-z0-9])',
    ),
    ModelBrand(
      'MiMo',
      'mimo.svg',
      r'mimo|xiaomi|'
          '\u5C0F'
          '\u7C73',
    ),
    ModelBrand('MiniMax', 'minimax-color.svg', r'minimax'),
    ModelBrand('Grok', 'grok.svg', r'grok'),
    ModelBrand(
      'Mistral',
      'mistral-color.svg',
      r'mistral|mixtral|magistral|ministral|devstral|codestral|pixtral|voxtral',
    ),
    ModelBrand('Llama', 'meta-color.svg', r'(?:code|tiny)?llama'),
    ModelBrand('Muse', 'meta-color.svg', r'muse[-_ ](?:spark|image)'),
    ModelBrand(
      'StepFun',
      'stepfun.svg',
      r'stepfun|step(?=$|[^a-z0-9]|\d)|'
          '\u9636'
          '\u8DC3',
    ),
    ModelBrand(
      'InternLM',
      'internlm-color.svg',
      r'internlm|intern-s1|'
          '\u4E66'
          '\u751F',
    ),
    ModelBrand('LongCat', 'longcat.png', r'longcat'),
    ModelBrand(
      'SenseNova',
      'sensenova-color.svg',
      r'sensenova|sensetime|'
          '\u5546'
          '\u6C64'
          r'|'
          '\u65E5'
          '\u65E5'
          '\u65B0',
    ),
    ModelBrand(
      'InclusionAI',
      'ling.png',
      r'inclusionai|(?:ling|ring)(?=$|[-_ .]\d|[-_ ](?:mini|lite|flash|plus))',
    ),
    ModelBrand('Cohere', 'cohere-color.svg', r'cohere|command(?=$|[-_ ])'),
    ModelBrand('Perplexity', 'perplexity-color.svg', r'perplexity|sonar'),
    ModelBrand(
      'KAT',
      'katkwaipilot-color.svg',
      r'kat(?=$|[^a-z0-9])|kwaipilot',
    ),
    ModelBrand('Sora', 'sora-color.svg', r'sora'),
  ];
}
