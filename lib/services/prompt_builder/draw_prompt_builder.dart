// lib/services/prompt_builder/draw_prompt_builder.dart

import '../../base/config_service.dart';
import '../../models/character_card_model.dart';

class DrawPromptBuilder {
  final ConfigService _configService;

  DrawPromptBuilder(this._configService);
  
  /// 构建最终的绘图提示词（正面和负面）。
  (String, String) build({
    required String llmGeneratedPrompt
  }) {
    // 从配置服务获取用户可设置的标签
    final stylePrompt = _configService.getActiveTagContent('drawing_style_tags', 'active_drawing_style_tag_id');
    final otherPrompt = _configService.getActiveTagContent('drawing_other_tags', 'active_drawing_other_tag_id');

    // 硬编码的通用标签
    const qualityPrompt = 'masterpiece, best quality, absurdres';
    const negativePrompt = 'worst quality, bad quality, worst detail, bad anatomy, bad hands, extra digits, fewer, extra, missing, error, watermark, unfinished, displeasing, chromatic aberration, signature, artistic error, username, scan';
    // 组合正面提示词
    final positiveParts = [
      llmGeneratedPrompt, // LLM生成的核心内容
      qualityPrompt,      // 质量词 (硬编码)
      stylePrompt,        // 画面风格 (用户设置)
      otherPrompt,        // 其他 (用户设置)
    ];
    
    // 过滤掉空值并用逗号连接
    final positivePrompt = positiveParts
      .where((p) => p.isNotEmpty)
      .join(', ');

    return (positivePrompt, negativePrompt);
  }

  /// 根据登场角色列表查找对应的参考图路径。
  /// 返回找到的第一个匹配的激活角色的参考图。
  String? findReferenceImageForCharacters(List<String> characterNames) {
    if (characterNames.isEmpty) {
      return null;
    }

    // 加载并筛选出已激活的角色卡片
    final allCardsJson = _configService.getSetting<List<dynamic>>('drawing_character_cards', []);
    final activeCardIdsJson = _configService.getSetting<List<dynamic>>('active_drawing_character_card_ids', []);
    final activeCardIds = activeCardIdsJson.map((id) => id.toString()).toSet();
    final allCards = allCardsJson.map((json) => CharacterCard.fromJson(json as Map<String, dynamic>)).toList();
    final activeCards = allCards.where((card) => activeCardIds.contains(card.id)).toList();

    if (activeCards.isEmpty) {
      return null;
    }

    // 遍历LLM返回的登场角色名
    for (final name in characterNames) {
      // 遍历所有激活的角色卡片
      for (final card in activeCards) {
        // 【新逻辑】将卡片的 characterName 按逗号分割成多个触发词
        final triggerWords = card.characterName.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
        
        // 如果登场角色名匹配卡片的任何一个触发词
        if (triggerWords.contains(name)) {
          final imagePath = card.referenceImagePath;
          final imageUrl = card.referenceImageUrl;

          // 只要本地路径或URL有一个不为空，就采纳并返回
          if ((imagePath != null && imagePath.isNotEmpty) || (imageUrl != null && imageUrl.isNotEmpty)) {
            // 优先使用本地路径
            return imagePath ?? imageUrl;
          }
        }
      }
    }
    
    // 如果遍历完所有登场角色都未找到匹配的参考图，则返回null
    return null;
  }
}