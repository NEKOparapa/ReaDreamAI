// lib/services/prompt_builder/llm_prompt_builder.dart

import '../../base/config_service.dart';
import '../../models/character_card_model.dart';

class LlmPromptBuilder {
  final ConfigService _configService;

  LlmPromptBuilder(this._configService);

  /// 生成提示词结构
  (String, List<Map<String, String>>) buildForSceneDiscovery({
    required String textContent,
    required int numScenes,
  }) {
    // 加载并筛选激活的角色卡片
    final allCardsJson = _configService.getSetting<List<dynamic>>('drawing_character_cards', []);
    final activeCardIdsJson = _configService.getSetting<List<dynamic>>('active_drawing_character_card_ids', []);
    final activeCardIds = activeCardIdsJson.map((id) => id.toString()).toSet();

    final allCards = allCardsJson.map((json) => CharacterCard.fromJson(json as Map<String, dynamic>)).toList();
    final activeCards = allCards.where((card) => activeCardIds.contains(card.id)).toList();

    // 如果有激活的角色卡片，则构建角色信息提示块
    String characterInfoBlock = '';
    if (activeCards.isNotEmpty) {
      final buffer = StringBuffer();
      buffer.writeln('### 参考角色信息:');
      buffer.writeln('---');
      for (final card in activeCards) {
        final characterNameToUse = card.characterName.isNotEmpty ? card.characterName : card.name;
        buffer.writeln('- 角色名字: $characterNameToUse');
        if (card.identity.isNotEmpty) buffer.writeln('  - 身份: ${card.identity}');
        if (card.appearance.isNotEmpty) buffer.writeln('  - 外貌: ${card.appearance}');
        if (card.clothing.isNotEmpty) buffer.writeln('  - 服装: ${card.clothing}');
        if (card.other.isNotEmpty) buffer.writeln('  - 其他: ${card.other}');
      }
      buffer.writeln('---');
      characterInfoBlock = buffer.toString();
    }

    // 从配置中获取系统提示词
    final systemPrompt = _configService.getActivePromptCardContent();

    // 用户指令
    final userPrompt =  """
    请从小说文本中提取并生成一个包含 $numScenes 个场景的JSON数组。 每个场景应包含:
    - scene_description: 对该场景的中文简要描述
    - prompt: AI绘画提示词
    - insertion_line_number: 该场景插图应插入的具体行号

    ### 小说文本:
    ---
    $textContent
    ---

    $characterInfoBlock

    ### JSON输出格式:
    ```json
    [
      {
        "scene_description": "对该场景的中文简要描述...",
        "prompt": "1man, rugged face, a scar on his left cheek... ",
        "insertion_line_number": 12
      }
    ]
    ```
    """;

    final messages = [
      {'role': 'user', 'content': userPrompt}
    ];

    return (systemPrompt, messages);
  }
  
  /// 为此处生成插图的提示词
  (String, List<Map<String, String>>) buildForSelectedScene({
    required String contextText,
    required String selectedText,
  }) {
    // 加载并筛选激活的角色卡片
    final allCardsJson = _configService.getSetting<List<dynamic>>('drawing_character_cards', []);
    final activeCardIdsJson = _configService.getSetting<List<dynamic>>('active_drawing_character_card_ids', []);
    final activeCardIds = activeCardIdsJson.map((id) => id.toString()).toSet();

    final allCards = allCardsJson.map((json) => CharacterCard.fromJson(json as Map<String, dynamic>)).toList();
    final activeCards = allCards.where((card) => activeCardIds.contains(card.id)).toList();

    // 构建角色相关的指令和信息块
    String characterInfoBlock = '';
    if (activeCards.isNotEmpty) {
      final buffer = StringBuffer();
      buffer.writeln('### 参考角色信息:');
      buffer.writeln('---');
      for (final card in activeCards) {
        final characterNameToUse = card.characterName.isNotEmpty ? card.characterName : card.name;
        buffer.writeln('- 角色名字: $characterNameToUse');
        if (card.identity.isNotEmpty) buffer.writeln('  - 身份: ${card.identity}');
        if (card.appearance.isNotEmpty) buffer.writeln('  - 外貌: ${card.appearance}');
        if (card.clothing.isNotEmpty) buffer.writeln('  - 服装: ${card.clothing}');
        if (card.other.isNotEmpty) buffer.writeln('  - 其他: ${card.other}');
      }
      buffer.writeln('---');
      characterInfoBlock = buffer.toString();
    }

    // 系统提示词
    const String systemPrompt = """你是一个专业的小说插图生成助手，充分理解小说上下文理解情节、人物关系和环境，并为【高亮指定的场景】生成详细的英文的AI绘图提示词。
绘画提示词应该遵守以下要求:
- 从主体、服装与配饰、姿态与情绪、构图与镜头、环境与背景、氛围与光影方面进行详细描绘。
- 如果场景文本中角色的服装、状态或细节与角色参考信息不一致，优先使用场景文本中的描述。
- 尽量使用具体的视觉性语言和AI绘画标签。
- 不要包含任何艺术风格、画质或艺术家名字。""";

    // 用户指令
    final userPrompt = """
    请仔细分析下面提供的这段小说上下文，重点关注【高亮指定的场景】,并为该场景生成:
    - scene_description: 对该场景的简短中文描述。
    - prompt: 用于AI绘画的英文提示词。

    ### 小说上下文:
    ---
    $contextText
    ---

    ### 【高亮指定的场景】:
    ---
    $selectedText
    ---

    $characterInfoBlock

    ### JSON输出格式:
    ```json
    {
      "scene_description": "对该场景的简短中文描述。",
      "prompt": "1man, rugged face, a scar on his left cheek..."
    }
    ```
    """;

    final messages = [
      {'role': 'user', 'content': userPrompt}
    ];

    return (systemPrompt, messages);
  }
  /// 为图生视频生成提示词
  (String, List<Map<String, String>>) buildForVideoPrompt({
    required String sceneDescription,
  }) {
    // 系统提示词
    const String systemPrompt = """你是一位专业的动态视频脚本家。根据提供的静态场景描述，你需要创作一个生动、富有动感的英文视频生成提示词。
提示词应侧重于描绘场景中的动态元素、镜头运动和时间流逝感。
- 描述物体的移动、角色的动作、表情的细微变化。
- 使用 'camera zoom in/out', 'panning shot', 'tilting up/down' 等运镜术语。
- 描绘光影、天气或环境的动态变化，例如 'sunlight filtering through leaves and swaying', 'clouds drifting across the sky'。""";

    // 用户指令
    final userPrompt = """
    请根据以下静态场景描述，生成一个用于AI视频生成的英文提示词。

    ### 静态场景描述:
    ---
    $sceneDescription
    ---

    ### JSON输出格式:
    ```json
    {
      "prompt": "A knight raises his shimmering sword, cinematic shot..."
    }
    ```
    """;

    final messages = [
      {'role': 'user', 'content': userPrompt}
    ];

    return (systemPrompt, messages);
  }
}