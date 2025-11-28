// lib/services/task_executor/game_stage_generator_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:pool/pool.dart';
import 'package:uuid/uuid.dart';
import '../../base/config_service.dart';
import '../../base/log/log_service.dart';
import '../../ui/creation/game_world_creation/generate_game_stage_page.dart';
import '../llm_service/llm_service.dart';

class GameStageGeneratorService {
  GameStageGeneratorService._();
  static final GameStageGeneratorService instance = GameStageGeneratorService._();

  final LlmService _llmService = LlmService.instance;
  final ConfigService _configService = ConfigService();

  // --- JSON 提取与修复工具方法 (保持原样) ---
  String _extractJsonString(String response) {
    final codeBlockMatch = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(response);
    if (codeBlockMatch != null && codeBlockMatch.group(1) != null) {
      return codeBlockMatch.group(1)!.trim();
    }
    final braceMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
    if (braceMatch != null) return braceMatch.group(0)!;
    final bracketMatch = RegExp(r'\[[\s\S]*\]').firstMatch(response);
    if (bracketMatch != null) return bracketMatch.group(0)!;
    return response;
  }

  String _attemptJsonRepair(String brokenJson) {
    String repaired = brokenJson.trim();
    if (repaired.endsWith(',')) {
      repaired = repaired.substring(0, repaired.length - 1);
    }
    repaired = repaired.replaceAll(RegExp(r',\s*([}\]])'), r'$1');
    return repaired;
  }

  dynamic _parseJsonWithRepair(String jsonString) {
    try {
      return jsonDecode(jsonString);
    } catch (e) {
      LogService.instance.warn('JSON常规解析失败，尝试简单修复...');
      try {
        final repaired = _attemptJsonRepair(jsonString);
        return jsonDecode(repaired);
      } catch (e2) {
        LogService.instance.error('JSON修复失败', e2);
        rethrow;
      }
    }
  }

  // --- 主入口方法 ---

  /// 生成完整的游戏舞台设定（分两步执行）
  Future<Map<String, dynamic>> generateGameStage({
    required String worldRequirements,
    required String destinyAiRequirements,
    required String firstDayRequirements,
    required CharacterSourceOption characterSource,
    required bool useAiCharacterCount,
    required int aiCharacterCount,
    required List<Map<String, dynamic>>? selectedCharacters,
    required bool useAiScenes,
    required int sceneCount,
  }) async {
    LogService.instance.info('🚀 [游戏舞台生成] 任务开始...');

    // 获取当前 API 配置，用于并发控制
    final activeApi = _configService.getActiveLanguageApi();
    // 如果 API 没有设置并发限制，默认保守设置为 2
    final int concurrency = activeApi.concurrencyLimit ?? 2;
    final rateLimiter = _configService.getRateLimiterForApi(activeApi);

    LogService.instance.info('ℹ️ [配置] 并发数: $concurrency, API: ${activeApi.name}');

    // ==========================================
    // 步骤 1: 生成基础世界信息 (世界观、角色、场景)
    // ==========================================
    LogService.instance.info('🔄 [步骤 1/2] 生成世界背景、角色与场景...');
    
    Map<String, dynamic> baseStageData;
    try {
      baseStageData = await _generateBaseStage(
        worldRequirements: worldRequirements,
        destinyAiRequirements: destinyAiRequirements,
        characterSource: characterSource,
        useAiCharacterCount: useAiCharacterCount,
        aiCharacterCount: aiCharacterCount,
        selectedCharacters: selectedCharacters,
        useAiScenes: useAiScenes,
        sceneCount: sceneCount,
        apiConfig: activeApi,
      );
      
      // [关键] 必须确保所有对象都有 ID，因为步骤 2 需要引用这些 ID
      _ensureIds(baseStageData);
      
      LogService.instance.success('✅ [步骤 1/2] 基础数据生成完毕。');
    } catch (e, s) {
      LogService.instance.error('❌ [步骤 1/2] 基础数据生成失败，终止任务。', e, s);
      rethrow;
    }

    // ==========================================
    // 步骤 2: 并行生成初日事件
    // ==========================================
    final List<dynamic> aiCharacters = baseStageData['ai_characters'] ?? [];
    
    if (aiCharacters.isEmpty) {
      LogService.instance.warn('⚠️ 未生成任何 AI 角色，跳过事件生成。');
      baseStageData['first_day_events'] = [];
      return baseStageData;
    }

    LogService.instance.info('🔄 [步骤 2/2] 并行生成 ${aiCharacters.length} 个角色的初日事件...');

    final List<Map<String, dynamic>> firstDayEvents = [];
    final pool = Pool(concurrency); // 创建线程池控制并发
    final List<Future> futures = [];

    // 遍历每一个生成的角色
    for (var charData in aiCharacters) {
      final character = Map<String, dynamic>.from(charData);
      
      // 将任务加入线程池
      final future = pool.withResource(() async {
        // [关键] 在进入实际请求前，先获取 RateLimiter 令牌，防止 RPM 超限
        await rateLimiter.acquire();

        LogService.instance.info('  -> ⚡️ 正在生成角色 [${character['name']}] 的剧情...');
        
        try {
          final event = await _generateSingleFirstDayEvent(
            baseData: baseStageData,
            targetCharacter: character,
            firstDayRequirements: firstDayRequirements,
            apiConfig: activeApi,
          );

          if (event != null) {
            firstDayEvents.add(event);
            LogService.instance.info('  -> ✅ 角色 [${character['name']}] 剧情生成成功 (场景: ${event['scene_id']})。');
          }
        } catch (e) {
          LogService.instance.error('  -> ❌ 角色 [${character['name']}] 剧情生成失败', e);
          // 单个失败不影响整体流程
        }
      });
      futures.add(future);
    }

    // 等待所有并发任务完成
    await Future.wait(futures);
    
    // 将生成的事件列表合并回主数据
    baseStageData['first_day_events'] = firstDayEvents;

    LogService.instance.success('🎉 [游戏舞台生成] 所有任务完成！');
    return baseStageData;
  }

  // --- 内部逻辑方法 ---

  /// Step 1的具体实现：生成基础数据
  Future<Map<String, dynamic>> _generateBaseStage({
    required String worldRequirements,
    required String destinyAiRequirements,
    required CharacterSourceOption characterSource,
    required bool useAiCharacterCount,
    required int aiCharacterCount,
    required List<Map<String, dynamic>>? selectedCharacters,
    required bool useAiScenes,
    required int sceneCount,
    required dynamic apiConfig,
  }) async {
    // 提示词：专注于世界构建，不包含事件
    final systemPrompt = """你是一位顶级的游戏世界设计师。你的任务是根据要求设计一个完整的游戏舞台。
    
### 输出格式 (JSON)
请严格按照以下JSON格式输出，确保逻辑自洽：
```json
{
  "world_background": "详细的世界观描述...",
  "destiny_ai": "基于'命运AI要求'的故事走向或核心矛盾...",
  "player_character": {
    "name": "...", "identity": "...", "appearance": "...", 
    "status": "...", "equipment": "...", "backpack": "..."
  },
  "ai_characters": [
    {
      "id": "char_uuid", // 请务必生成唯一ID
      "cardName": "卡片名", "name": "...", "identity": "...", "appearance": "...", 
      "personality": "...", "motivation": "...", "status": "...", 
      "other": "...", "equipment": "...", "backpack": "..."
    }
  ],
  "game_scenes": [
    {
      "id": "scene_uuid", // 请务必生成唯一ID
      "name": "...", "description": "...", "subsidiaryScenes": "...", "status": "..."
    }
  ]
}
```
""";

    final userPromptBuffer = StringBuffer();
    userPromptBuffer.writeln('### 游戏世界要求\n$worldRequirements');
    if (destinyAiRequirements.isNotEmpty) {
      userPromptBuffer.writeln('\n### 命运AI要求\n$destinyAiRequirements');
    }
    
    userPromptBuffer.writeln('\n### 角色设定');
    if (characterSource == CharacterSourceOption.manual) {
      userPromptBuffer.writeln('- 请直接整合以下角色信息:');
      userPromptBuffer.writeln(jsonEncode(selectedCharacters));
    } else {
      userPromptBuffer.writeln('- 由AI自动生成');
      userPromptBuffer.writeln(useAiCharacterCount 
          ? '- 数量: 由AI根据世界观决定(建议3-6个)' 
          : '- 数量: $aiCharacterCount个');
    }

    userPromptBuffer.writeln('\n### 游戏场景');
    userPromptBuffer.writeln(useAiScenes ? '- 数量: 由AI决定(建议3-5个)' : '- 数量: $sceneCount个');

    final response = await _llmService.requestCompletion(
      systemPrompt: systemPrompt,
      messages: [{'role': 'user', 'content': userPromptBuffer.toString()}],
      apiConfig: apiConfig,
    );

    final jsonStr = _extractJsonString(response);
    return _parseJsonWithRepair(jsonStr);
  }

  /// Step 2的具体实现：单个角色的事件生成
  Future<Map<String, dynamic>?> _generateSingleFirstDayEvent({
    required Map<String, dynamic> baseData,
    required Map<String, dynamic> targetCharacter,
    required String firstDayRequirements,
    required dynamic apiConfig,
  }) async {
    // 构建精简的上下文，避免 Token 消耗过大
    // 只提取必要的：世界背景、玩家基础信息、所有可选场景
    final contextData = {
      "world_background": baseData['world_background'],
      "player_summary": {
        "name": baseData['player_character']['name'],
        "identity": baseData['player_character']['identity'],
      },
      "available_scenes": (baseData['game_scenes'] as List).map((s) => {
        "id": s['id'],
        "name": s['name'],
        "description": s['description']
      }).toList(),
    };

    final systemPrompt = """你是一名游戏剧情策划。请基于提供的世界背景和场景，设计一段“初日事件”。

### 任务目标
设计玩家(Player)与目标角色 [${targetCharacter['name']}] 的初次相遇或互动剧情。

### 核心要求
1. **场景绑定**: 必须从 `available_scenes` 中选择一个最合适的 `id` 填入 `scene_id`。
2. **角色一致性**: 剧情必须符合 [${targetCharacter['name']}] 的性格(${targetCharacter['personality']})和身份。
3. **响应用户需求**: 结合用户的“首日事件要求”：$firstDayRequirements

### 输出格式 (JSON)
```json
{
  "scene_id": "必须对应 available_scenes 中的某个 id",
  "dialogues": [
    {"name": "...", "message": "..."},
    {"name": "...", "message": "..."}
  ]
}
```
""";

    final userPrompt = """
### 背景资料
${jsonEncode(contextData)}

### 目标角色详情
${jsonEncode(targetCharacter)}

### 请生成该角色的初日事件
""";

    final response = await _llmService.requestCompletion(
      systemPrompt: systemPrompt,
      messages: [{'role': 'user', 'content': userPrompt}],
      apiConfig: apiConfig,
    );

    final jsonStr = _extractJsonString(response);
    final eventData = _parseJsonWithRepair(jsonStr);

    // 简单校验
    if (eventData is Map<String, dynamic>) {
       // 确保 scene_id 有效，如果无效或AI瞎编了一个，修正为第一个场景
       final scenes = baseData['game_scenes'] as List;
       final hasScene = scenes.any((s) => s['id'] == eventData['scene_id']);
       if (!hasScene && scenes.isNotEmpty) {
         eventData['scene_id'] = scenes.first['id'];
       }
       return eventData;
    }
    return null;
  }

  /// 辅助方法：确保 ID 存在
  void _ensureIds(Map<String, dynamic> data) {
    final uuid = const Uuid();
    
    // 补全角色 ID
    if (data['ai_characters'] is List) {
      for (var char in data['ai_characters']) {
        if (char is Map && (char['id'] == null || char['id'].toString().isEmpty)) {
          char['id'] = uuid.v4();
        }
      }
    }
    
    // 补全场景 ID
    if (data['game_scenes'] is List) {
      for (var scene in data['game_scenes']) {
        if (scene is Map && (scene['id'] == null || scene['id'].toString().isEmpty)) {
          scene['id'] = uuid.v4();
        }
      }
    }
  }
}