// lib/services/game/game_event_ai_service.dart

import 'dart:convert';
import '../../base/config_service.dart';
import '../../base/log/log_service.dart';
import '../llm_service/llm_service.dart';

class GameEventAiService {
  GameEventAiService._();
  static final GameEventAiService instance = GameEventAiService._();

  final LlmService _llmService = LlmService.instance;
  final ConfigService _configService = ConfigService();

  /// 生成剧情后续
  Future<Map<String, dynamic>> generateEventContinuation({
    required List<Map<String, dynamic>> recentDialogues,
    required String userInput,
    required String sceneId,
    required Map<String, dynamic> playerInfo,
    required Map<String, dynamic> currentScene,
  }) async {
    final activeApi = _configService.getActiveLanguageApi();

    final systemPrompt = '''
你是一个互动小说（Galgame）的即时剧情生成AI。
你的任务是根据当前剧情上下文和玩家的行动，生成后续的剧情对话。

# 要求
1. 剧情应连贯、生动，符合角色性格和当前场景氛围。
2. 每次生成 3-6 句对话（不要太长，也不要太短）。
3. **生成的剧情必须对玩家的输入（行动或对话）做出逻辑上的反应。**
4. 在对话结束后，提供 2-4 个合逻辑的后续行动选项。

# 输出格式 (JSON)
请严格按照以下JSON格式输出，不要包含Markdown标记：
{
  "new_dialogues": [
    {"name": "角色名", "message": "对话内容..."}
  ],
  "options": ["选项1", "选项2", "选项3"]
}
''';

    final userPrompt = '''
【当前场景】: ${currentScene['name']} 
【场景描述】: ${currentScene['description'] ?? '无'}
【玩家角色】: ${playerInfo['name']} (身份: ${playerInfo['identity'] ?? '未知'})
【近期剧情回顾】:
${jsonEncode(recentDialogues)}

【玩家最新行动/输入】:
$userInput

请生成后续剧情和选项：
''';

    try {
      final response = await _llmService.requestCompletion(
        systemPrompt: systemPrompt,
        messages: [{'role': 'user', 'content': userPrompt}],
        apiConfig: activeApi,
      );

      final result = _extractJson(response);
      
      if (result == null) {
        throw Exception("无法解析AI返回的JSON格式");
      }

      return result;
    } catch (e) {
      LogService.instance.error('AI剧情生成失败', e);
      return {
        'new_dialogues': [
          {'name': '系统', 'message': '（似乎受到干扰，无法看清未来的景象...）'},
          {'name': '系统', 'message': '错误信息: $e'}
        ],
        'options': ['重试', '稍后回来']
      };
    }
  }

  /// 鲁棒的 JSON 提取器
  Map<String, dynamic>? _extractJson(String text) {
    try {
      // 尝试匹配 markdown code block
      final match = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(text);
      String jsonStr;
      if (match != null) {
        jsonStr = match.group(1) ?? text;
      } else {
        // 如果没有代码块，尝试寻找大括号范围
        final start = text.indexOf('{');
        final end = text.lastIndexOf('}');
        if (start != -1 && end != -1) {
          jsonStr = text.substring(start, end + 1);
        } else {
          jsonStr = text;
        }
      }
      return jsonDecode(jsonStr);
    } catch (e) {
      return null;
    }
  }
}