// lib/services/prompt_builder/llm_prompt_builder.dart

import '../../base/config_service.dart';
import '../../models/character_card_model.dart';

class LlmPromptBuilder {
  final ConfigService _configService;

  LlmPromptBuilder(this._configService);

  /// 构建用于生成插图场景的LLM提示词。
  (String, List<Map<String, String>>) build({
    required String textContent,
    required int numScenes,
  }) {
    // 加载并筛选激活的角色卡片
    final allCardsJson = _configService.getSetting<List<dynamic>>('drawing_character_cards', []);
    final activeCardIdsJson = _configService.getSetting<List<dynamic>>('active_drawing_character_card_ids', []);
    final activeCardIds = activeCardIdsJson.map((id) => id.toString()).toSet();

    final allCards = allCardsJson.map((json) => CharacterCard.fromJson(json as Map<String, dynamic>)).toList();
    final activeCards = allCards.where((card) => activeCardIds.contains(card.id)).toList();

    // 如果有激活的角色卡片，则构建角色信息提示块和对应的指令
    String characterInstruction = '';
    String characterInfoBlock = '';
    if (activeCards.isNotEmpty) {
      characterInstruction = '5. 如果小说文本中出现以下角色，请参考给定的角色信息，以确保角色形象的统一性。';
      
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


    // 系统角色提示，定义AI的行为和目标
    final systemPrompt = """
    你是一个专业的小说插图生成助手，专注于从小说文本中提取最具画面感的场景，并为每个场景生成详细的绘图提示词。""";

    // 用户指令，包含具体要求、输入文本和输出格式
    final userPrompt =  """
    仔细分析小说文本，捕捉关键的角色、动作、环境和氛围，选择情感冲击力最强的时刻，挑选出 $numScenes 个最具画面感的场景。

    对于每个场景的要求:
    1.  生成对该场景的中文简要描述(scene_description)。
    2.  生成英文的AI绘画提示词 (prompt)。
        - 从主体、服装与配饰、姿态与情绪、构图与镜头、环境与背景、氛围与光影方面进行详细描绘。
        - 如果场景文本中角色的服装、状态或细节与角色参考信息不一致，优先使用场景文本中的描述。。
        - 尽量使用具体的视觉性语言，尽量使用AI绘画相关的标签语言。
        - 不要包含任何艺术风格、画质或艺术家名字
    3.  场景插图应插入的具体行号 (insertion_line_number)。
    4.  严格按照下面的JSON格式返回，直接返回一个JSON数组，不要包含任何JSON格式之外的额外说明或注释。
    $characterInstruction

    $characterInfoBlock
    ### 小说文本:
    ---
    $textContent
    ---

    ### JSON输出格式:
    ```json
    [
      {
        "scene_description": "对该场景的简短中文描述。",
        "prompt": "1man, rugged face, a scar on his left cheek...",
        "insertion_line_number": 123
      }
    ]
    ```
    """;

    final messages = [
      {'role': 'user', 'content': userPrompt}
    ];

    return (systemPrompt , messages );
  }
}