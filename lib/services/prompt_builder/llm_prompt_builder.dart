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
        // 使用逗号分隔的第一个名字作为主要参考名
        final mainCharacterName = card.characterName.split(',').first.trim();
        if (mainCharacterName.isNotEmpty) {
          buffer.writeln('- 角色名字: $mainCharacterName (在文本中可能以 ${card.characterName} 中任一名字出现)');
          if (card.identity.isNotEmpty) buffer.writeln('  - 身份: ${card.identity}');
          if (card.appearance.isNotEmpty) buffer.writeln('  - 外貌: ${card.appearance}');
          if (card.clothing.isNotEmpty) buffer.writeln('  - 服装: ${card.clothing}');
          if (card.other.isNotEmpty) buffer.writeln('  - 其他: ${card.other}');
        }
      }
      buffer.writeln('---');
      characterInfoBlock = buffer.toString();
    }

    // 从配置中获取系统提示词
    final systemPrompt = _configService.getActivePromptCardContent();

    // 用户指令
    final userPrompt = """
    请从小说文本中提取并生成一个包含 $numScenes 个场景的JSON数组。 每个场景应包含:
    - scene_description: 对该场景的中文简要描述
    - prompt: 用于AI绘画的详细英文提示词
    - insertion_line_number: 该场景插图应插入的具体行号
    - appearing_characters: 该场景中出现的角色名字数组（与原文一致），如果没有角色则返回空数组[]
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
        "prompt": "1boy, rugged face, a scar on his left cheek... ",
        "insertion_line_number": 12,
        "appearing_characters": ["角色名1", "角色名2"]
      },
      {
        "scene_description": "一个空旷的街道场景...",
        "prompt": "empty street, cobblestone, medieval town...",
        "insertion_line_number": 25,
        "appearing_characters": []
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
         final mainCharacterName = card.characterName.split(',').first.trim();
         if (mainCharacterName.isNotEmpty) {
            buffer.writeln('- 角色名字: $mainCharacterName (在文本中可能以 ${card.characterName} 中任一名字出现)');
            if (card.identity.isNotEmpty) buffer.writeln('  - 身份: ${card.identity}');
            if (card.appearance.isNotEmpty) buffer.writeln('  - 外貌: ${card.appearance}');
            if (card.clothing.isNotEmpty) buffer.writeln('  - 服装: ${card.clothing}');
            if (card.other.isNotEmpty) buffer.writeln('  - 其他: ${card.other}');
         }
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
    请仔细分析下面提供的这段小说上下文，重点关注【高亮指定的场景】,并为该场景生成一个JSON对象，包含:
    - scene_description: 对该场景的简短中文描述
    - prompt: 用于AI绘画的英文提示词
    - appearing_characters: 该场景中出现的角色名字数组（与原文一致），如果没有角色则返回空数组[]

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
      "prompt": "1boy, rugged face, a scar on his left cheek...",
      "appearing_characters": ["男孩"]
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
    required String contextText, // 传递上下文
  }) {
    // 系统提示词
    const String systemPrompt = """你是一位专业的动态视频脚本家。根据提供的静态场景描述和小说上下文，你需要创作一个生动、富有动感的英文视频生成提示词。
# 核心原则

忠于原图与上下文：提示词内容必须与输入图片的内容保持一致，同时要反映小说上下文中的情绪、氛围和情节走向。
运动优先：图片已经提供了静态的场景、主体和构图。你的核心任务是描述运动，而不是重复描述图片中已有的静止信息。
简洁直接：使用简单、清晰的词语和短句。
强化关键：对于动作的强度、速度和镜头运动，使用明确的程度副词来强调。

# 提示词构建指南
1. 基础结构
遵循以下结构来组织你的提示词：
[主体] + [运动] + [背景/环境] + [运动] + [镜头] + [运动]

主体 + 运动：首先明确图片中的主要主体，并描述它将要执行的动作。如果主体有显著特征（如“戴墨镜的女人”、“白胡子老人”），请加入特征描述以帮助模型精确定位。
背景/环境 + 运动：描述背景元素的变化或运动，如“树叶缓缓飘落”、“背景的灯光闪烁”。
镜头 + 运动：描述镜头的运动方式。

2. 高级技巧
(1)单主体多动作：使用 主体 + 动作1 + 动作2 + ... 的格式，按时间顺序依次列出。
示例：“女孩转过脸对着镜头向前走，然后停下，脸上露出愤怒的表情，然后叉腰。”
(2)多主体多动作：使用 主体1 + 动作1 + 主体2 + 动作2 + ... 的格式。
示例：“女人一边哭泣一边喝酒，一个男人走进来安慰她。”

# 镜头语言（运镜）：
运镜术语：环绕、航拍、变焦（推近/拉远）、平移（上/下/左/右）、跟随、手持（可带“微微抖动”）等等。
镜头切换：当需要切换镜头时，明确使用“镜头切换”作为连接词。切换后如果场景或焦点变化，需要对新内容进行描述。
示例：“小猫和小狗吃猫粮，镜头切换到特写猫粮颗颗分明。”

# 程度副词：
推荐词汇：快速、缓慢、剧烈、大幅度、高频率、强力、疯狂、突然、微微。
可适度夸张：为了增强表现力，可以适当夸大程度。例如，用“疯狂咆哮”代替“咆哮”，用“翅膀大幅度扇动”代替“翅膀扇动”。
。""";

    // 用户指令
    final userPrompt = """
    请仔细分析下面的【小说上下文】和【静态场景描述】，为该场景生成一个用于AI视频生成的、富有故事性的英文提示词。

    ### 小说上下文:
    ---
    $contextText
    ---

    ### 静态场景描述 (图片内容):
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