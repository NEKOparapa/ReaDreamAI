// lib/services/task_executor/game_stage_generator_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:pool/pool.dart';
import 'package:uuid/uuid.dart';

import '../../base/config_service.dart';
import '../../base/log/log_service.dart';
import '../../ui/creation/game_world_creation/generate_game_stage_page.dart'; // 为了使用 CharacterSourceOption 枚举
import '../llm_service/llm_service.dart';
import '../drawing_service/drawing_service.dart';
import '../music_service/music_service.dart';

class GameStageGeneratorService {
  GameStageGeneratorService._();
  static final GameStageGeneratorService instance = GameStageGeneratorService._();

  final LlmService _llmService = LlmService.instance;
  final DrawingService _drawingService = DrawingService.instance;
  final MusicService _musicService = MusicService.instance;
  final ConfigService _configService = ConfigService();

  // --- JSON 提取与修复工具方法 ---
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
    // 移除末尾多余逗号
    if (repaired.endsWith(',')) {
      repaired = repaired.substring(0, repaired.length - 1);
    }
    // 移除列表或对象末尾的逗号 (e.g. ", }")
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

  /// 生成完整的游戏舞台设定（分四步执行：世界基础 -> 初日事件 -> 媒体提示词 -> 媒体资源）
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
    required bool generateCharImages,
    required bool generateSceneImages,
    required bool generateSceneMusic,
  }) async {
    LogService.instance.info('🚀 [游戏舞台生成] 任务开始...');

    // 获取当前 API 配置，用于并发控制
    final activeApi = _configService.getActiveLanguageApi();
    final int concurrency = activeApi.concurrencyLimit ?? 2;
    final rateLimiter = _configService.getRateLimiterForApi(activeApi);

    LogService.instance.info('ℹ️ [配置] 并发数: $concurrency, API: ${activeApi.name}');

    // ==========================================
    // 步骤 1: 生成基础世界信息 (世界观、角色、场景)
    // ==========================================
    LogService.instance.info('🔄 [步骤 1/4] 生成世界背景、角色与场景...');
    
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
      
      // 必须确保所有对象都有 ID，因为后续步骤需要引用这些 ID
      _ensureIds(baseStageData);
      
      LogService.instance.success('✅ [步骤 1/4] 基础数据生成完毕。');
    } catch (e, s) {
      LogService.instance.error('❌ [步骤 1/4] 基础数据生成失败，终止任务。', e, s);
      rethrow;
    }

    // ==========================================
    // 步骤 2: 并行生成初日事件
    // ==========================================
    final List<dynamic> aiCharacters = baseStageData['ai_characters'] ?? [];
    
    if (aiCharacters.isEmpty) {
      LogService.instance.warn('⚠️ 未生成任何 AI 角色，跳过事件生成。');
      baseStageData['first_day_events'] = [];
    } else {
      LogService.instance.info('🔄 [步骤 2/4] 并行生成 ${aiCharacters.length} 个角色的初日事件...');

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
      LogService.instance.success('✅ [步骤 2/4] 初日事件生成完毕。');
    }

    // ==========================================
    // 步骤 3: 生成媒体提示词 (包括歌词)
    // ==========================================
    if (generateCharImages || generateSceneImages || generateSceneMusic) {
       LogService.instance.info('🔄 [步骤 3/4] 正在根据设定生成媒体提示词(Prompts)及歌词...');
       try {
         // 调用 LLM 生成具体的英文提示词
         final promptsData = await _generateMediaPrompts(
           baseData: baseStageData,
           genCharImg: generateCharImages,
           genSceneImg: generateSceneImages,
           genSceneMusic: generateSceneMusic,
           apiConfig: activeApi,
         );
         
         // 将生成的提示词回填到 baseStageData 中
         _mergePromptsToData(baseStageData, promptsData);
         
         LogService.instance.success('✅ [步骤 3/4] 媒体提示词生成完毕。');
       } catch (e, s) {
         LogService.instance.warn('⚠️ [步骤 3/4] 提示词生成失败，后续将使用默认模板兜底。');
       }
    } else {
       LogService.instance.info('⏭️ [步骤 3/4] 媒体提示词生成已跳过。');
    }

    // ==========================================
    // 步骤 4: 媒体资源生成
    // ==========================================
    if (generateCharImages || generateSceneImages || generateSceneMusic) {
       LogService.instance.info('🔄 [步骤 4/4] 开始调用绘画/音乐接口生成资源...');
       try {
         await _generateMediaAssets(
           baseStageData: baseStageData,
           genCharImg: generateCharImages,
           genSceneImg: generateSceneImages,
           genSceneMusic: generateSceneMusic,
         );
         LogService.instance.success('✅ [步骤 4/4] 媒体资源生成完毕。');
       } catch (e, s) {
         // 媒体生成失败不应该阻塞流程，只记录错误
         LogService.instance.error('❌ [步骤 4/4] 媒体资源生成过程中发生错误', e, s);
       }
    } else {
       LogService.instance.info('⏭️ [步骤 4/4] 媒体生成已跳过。');
    }

    LogService.instance.success('🎉 [游戏舞台生成] 所有任务完成！');
    return baseStageData;
  }

  // --- 公共资源生成方法 (供 Workbench 和 内部流程 共用) ---

  /// 重新生成单个角色立绘
  Future<String?> regenerateCharacterImage({
    required Map<String, dynamic> characterData,
    required String prompt,
  }) async {
    final dirs = await _configService.getOrCreateGameWorkbenchDirs();
    final activeDrawingApi = _configService.getActiveDrawingApi();
    
    // 如果没有传入具体 Prompt (为空)，则使用默认模板
    final finalPrompt = (prompt.isNotEmpty) 
        ? prompt 
        : "Anime style, character sheet, masterpiece, best quality, solo, ${characterData['appearance']}, ${characterData['identity']}";

    LogService.instance.info('🎨 正在为角色 [${characterData['name']}] 生成立绘, Prompt: ${finalPrompt.substring(0, finalPrompt.length > 50 ? 50 : finalPrompt.length)}...');

    final paths = await _drawingService.generateImages(
      positivePrompt: finalPrompt,
      negativePrompt: "ugly, blurry, low quality, deformed, bad anatomy, text, watermark, extra limbs",
      saveDir: dirs['character']!.path,
      count: 1,
      width: 768, // 立绘常用竖构图，这里使用节省Token/时间的尺寸
      height: 1344,
      apiConfig: activeDrawingApi,
    );

    if (paths != null && paths.isNotEmpty) {
      return paths.first;
    }
    return null;
  }

  /// 重新生成单个场景图
  Future<String?> regenerateSceneImage({
    required Map<String, dynamic> sceneData,
    required String prompt,
  }) async {
    final dirs = await _configService.getOrCreateGameWorkbenchDirs();
    final activeDrawingApi = _configService.getActiveDrawingApi();

    final finalPrompt = (prompt.isNotEmpty)
        ? prompt
        : "Scenery, environment concept art, masterpiece, high quality, no humans, ${sceneData['name']}, ${sceneData['description']}";

    LogService.instance.info('🖼️ 正在为场景 [${sceneData['name']}] 生成插图, Prompt: ${finalPrompt.substring(0, finalPrompt.length > 50 ? 50 : finalPrompt.length)}...');

    final paths = await _drawingService.generateImages(
      positivePrompt: finalPrompt,
      negativePrompt: "text, watermark, blurry, ugly, humans, people, low quality, deformed, bad anatomy, extra limbs",
      saveDir: dirs['scene_image']!.path,
      count: 1,
      width: 1024, // 场景常用横构图
      height: 1024,
      apiConfig: activeDrawingApi,
    );

    if (paths != null && paths.isNotEmpty) {
      return paths.first;
    }
    return null;
  }

  /// 重新生成单个场景音乐 (增加 lyrics 参数)
  Future<String?> regenerateSceneMusic({
    required Map<String, dynamic> sceneData,
    required String prompt,
    String? lyrics, 
  }) async {
    final dirs = await _configService.getOrCreateGameWorkbenchDirs();
    
    // 获取音乐 API
    dynamic activeMusicApi;
    try {
      activeMusicApi = _configService.getActiveMusicApi();
    } catch (e) {
      LogService.instance.warn('未找到有效的音乐API配置');
      return null;
    }

    final finalPrompt = (prompt.isNotEmpty)
        ? prompt
        : "Background music, instrumental, game soundtrack, ${sceneData['description']}";

    final finalLyrics = lyrics ?? "";

    LogService.instance.info('🎵 正在为场景 [${sceneData['name']}] 生成音乐, Prompt: ${finalPrompt.substring(0, finalPrompt.length > 50 ? 50 : finalPrompt.length)}, Lyrics: ${finalLyrics.isNotEmpty ? "Yes" : "No"}...');

    return await _musicService.generateMusic(
      prompt: finalPrompt,
      lyrics: finalLyrics, // 传递歌词
      apiConfig: activeMusicApi,
      saveDir: dirs['scene_music']!.path,
      outputFormat: 'wav',
    );
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

  /// Step 3 具体实现：生成媒体提示词 (增加歌词生成)
  Future<Map<String, dynamic>> _generateMediaPrompts({
    required Map<String, dynamic> baseData,
    required bool genCharImg,
    required bool genSceneImg,
    required bool genSceneMusic,
    required dynamic apiConfig,
  }) async {
    // 提取关键信息给LLM，减少Token消耗
    final characters = (baseData['ai_characters'] as List).map((c) => {
      'id': c['id'], 
      'name': c['name'], 
      'appearance': c['appearance'], 
      'identity': c['identity']
    }).toList();
    
    final scenes = (baseData['game_scenes'] as List).map((s) => {
      'id': s['id'], 
      'name': s['name'], 
      'description': s['description']
    }).toList();

    final inputData = {
      'characters': genCharImg ? characters : [],
      'scenes': (genSceneImg || genSceneMusic) ? scenes : [],
    };

    const systemPrompt = """你是一个专业的AI艺术提示词(Prompt)生成专家。
你的任务是根据提供的角色和场景描述，生成用于 Stable Diffusion (SDXL) 的英文绘图提示词，以及用于 MusicGen 或 Suno 的英文音乐提示词和歌词。

### 要求
1. **绘图提示词(Prompts)**: 使用英文标签(Tags)格式，逗号分隔。包含质量词(masterpiece, best quality)和具体的视觉描述(appearance, clothing, setting)。
   - 角色图: Anime style, full body shot...
   - 场景图: Scenery, environment concept art, no humans...
2. **音乐提示词**: 使用英文描述音乐风格、乐器和氛围。
3. **歌词 (Lyrics)**: 
   - 配合场景以及音乐提示词，生成符合意境的歌词。
4. **对应关系**: 必须使用输入的 `id` 来对应生成的提示词。

### 输出格式 (JSON)
```json
{
  "character_prompts": [
    {"id": "输入中的角色ID", "imagePrompt": "Anime style, 1girl, ..."}
  ],
  "scene_prompts": [
    {
      "id": "输入中的场景ID", 
      "imagePrompt": "Scenery, ...", 
      "musicPrompt": "Epic orchestral, ...",
      "lyrics": "Short English lyrics here..." // 如果无需歌词，此处可为空字符串
    }
  ]
}
```
""";

    final userPrompt = "请为以下数据生成提示词：\n${jsonEncode(inputData)}\n"
        "生成开关: 角色图=$genCharImg, 场景图=$genSceneImg, 场景音乐=$genSceneMusic";

    final response = await _llmService.requestCompletion(
      systemPrompt: systemPrompt,
      messages: [{'role': 'user', 'content': userPrompt}],
      apiConfig: apiConfig,
    );

    final jsonStr = _extractJsonString(response);
    return _parseJsonWithRepair(jsonStr);
  }

  /// 辅助方法：将生成的提示词合并回主数据 (合并歌词)
  void _mergePromptsToData(Map<String, dynamic> baseData, Map<String, dynamic> promptsData) {
    // 1. 合并角色提示词
    if (promptsData['character_prompts'] is List) {
      for (var p in promptsData['character_prompts']) {
        final target = (baseData['ai_characters'] as List).firstWhere(
            (c) => c['id'] == p['id'], orElse: () => null);
        if (target != null && target is Map) {
          target['imagePrompt'] = p['imagePrompt'];
        }
      }
    }
    // 2. 合并场景提示词
    if (promptsData['scene_prompts'] is List) {
      for (var p in promptsData['scene_prompts']) {
        final target = (baseData['game_scenes'] as List).firstWhere(
            (s) => s['id'] == p['id'], orElse: () => null);
        if (target != null && target is Map) {
          if (p['imagePrompt'] != null) target['imagePrompt'] = p['imagePrompt'];
          if (p['musicPrompt'] != null) target['musicPrompt'] = p['musicPrompt'];
          if (p['lyrics'] != null) target['lyrics'] = p['lyrics']; // 合并歌词
        }
      }
    }
  }

  /// Step 4 具体实现：生成媒体资源 (调用公共方法)
  Future<void> _generateMediaAssets({
    required Map<String, dynamic> baseStageData,
    required bool genCharImg,
    required bool genSceneImg,
    required bool genSceneMusic,
  }) async {
    // 媒体生成的并发限制，设为2以避免过多占用资源或触发API限制
    final pool = Pool(2); 
    final List<Future> tasks = [];
    
    // 1. 生成角色立绘
    if (genCharImg) {
      final characters = baseStageData['ai_characters'] as List? ?? [];
      
      for (var char in characters) {
        if (char is! Map<String, dynamic>) continue;
        
        tasks.add(pool.withResource(() async {
          try {
            // 使用前面步骤生成的提示词，如果没有则 fallback 为空字符串(内部会使用默认模板)
            final prompt = char['imagePrompt']?.toString() ?? "";
            
            final path = await regenerateCharacterImage(characterData: char, prompt: prompt);
            
            if (path != null) {
              char['imagePath'] = path; // 回写路径
              LogService.instance.info('  -> ✅ 角色 [${char['name']}] 立绘生成成功。');
            }
          } catch (e) {
            LogService.instance.error('  -> ❌ 角色 [${char['name']}] 立绘生成失败', e);
          }
        }));
      }
    }

    // 2. 生成场景相关 (图 & 音乐)
    if (genSceneImg || genSceneMusic) {
      final scenes = baseStageData['game_scenes'] as List? ?? [];

      for (var scene in scenes) {
        if (scene is! Map<String, dynamic>) continue;

        // --- 场景插图 ---
        if (genSceneImg) {
          tasks.add(pool.withResource(() async {
            try {
              final prompt = scene['imagePrompt']?.toString() ?? "";
              
              final path = await regenerateSceneImage(sceneData: scene, prompt: prompt);
              
              if (path != null) {
                scene['imagePath'] = path;
                LogService.instance.info('  -> ✅ 场景 [${scene['name']}] 插图生成成功。');
              }
            } catch (e) {
               LogService.instance.error('  -> ❌ 场景 [${scene['name']}] 插图生成失败', e);
            }
          }));
        }

        // --- 场景音乐 ---
        if (genSceneMusic) {
          tasks.add(pool.withResource(() async {
             try {
               final prompt = scene['musicPrompt']?.toString() ?? "";
               final lyrics = scene['lyrics']?.toString(); // 获取歌词
               
               final path = await regenerateSceneMusic(sceneData: scene, prompt: prompt, lyrics: lyrics);
               
               if (path != null) {
                 scene['musicPath'] = path;
                 LogService.instance.info('  -> ✅ 场景 [${scene['name']}] 音乐生成成功。');
               }
             } catch (e) {
               LogService.instance.error('  -> ❌ 场景 [${scene['name']}] 音乐生成失败', e);
             }
          }));
        }
      }
    }

    // 等待所有媒体生成任务完成
    await Future.wait(tasks);
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