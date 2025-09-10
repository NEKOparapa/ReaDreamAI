// lib/services/prompt_builder/draw_prompt_builder.dart

import '../../base/config_service.dart';

class DrawPromptBuilder {
  final ConfigService _configService;

  DrawPromptBuilder(this._configService);
  
  /// 构建最终的绘图提示词（正面和负面）。
  (String, String) build({
    required String llmGeneratedPrompt
  }) {
    final qualityPrompt = _configService.getActiveTagContent('drawing_quality_tags', 'active_drawing_quality_tag_id');
    final artistPrompt = _configService.getActiveTagContent('drawing_artist_tags', 'active_drawing_artist_tag_id');
    final stylePrompt = _configService.getActiveTagContent('drawing_style_tags', 'active_drawing_style_tag_id');
    final otherPrompt = _configService.getActiveTagContent('drawing_other_tags', 'active_drawing_other_tag_id');
    final negativePrompt = _configService.getActiveTagContent('drawing_negative_tags', 'active_drawing_negative_tag_id');

    // 组合正面提示词
    final positiveParts = [
      llmGeneratedPrompt, // LLM生成的核心内容
      qualityPrompt,      // 质量词
      artistPrompt,       // 艺术家
      stylePrompt,        // 画面风格
      otherPrompt,        // 其他
    ];
    
    // 过滤掉空值并用逗号连接
    final positivePrompt = positiveParts
      .where((p) => p.isNotEmpty)
      .join(', ');

    return (positivePrompt, negativePrompt);
  }
}