// lib/services/prompt_builder/draw_prompt_builder.dart

import '../../base/config_service.dart';

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
}