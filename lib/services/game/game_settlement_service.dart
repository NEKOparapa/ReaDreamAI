// lib/services/game/game_settlement_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:pool/pool.dart';

import '../../base/config_service.dart';
import '../../services/llm_service/llm_service.dart';
import '../../base/log/log_service.dart';

/// 结算上下文：用于在分步结算过程中传递数据
class SettlementContext {
  List<Map<String, dynamic>> triggeredEvents = [];
  List<Map<String, dynamic>> historyEvents = [];
  List<Map<String, dynamic>> updatedAiCharacters = [];
  List<Map<String, dynamic>> updatedScenes = [];
  Map<String, dynamic> updatedPlayer = {};
  List<Map<String, dynamic>> newEvents = [];
  String summary = "";
  int currentTotalDays = 0;
  String gameTimeStr = "";
}

class GameSettlementService {
  GameSettlementService._();
  static final GameSettlementService instance = GameSettlementService._();

  final LlmService _llmService = LlmService.instance;
  final ConfigService _configService = ConfigService();

  // ---------------------------------------------------------------------------
  // 分步执行接口
  // ---------------------------------------------------------------------------

  /// 步骤 1: 归档历史事件
  List<Map<String, dynamic>> step1_archiveEvents({
    required List<Map<String, dynamic>> triggeredEvents,
    required List<Map<String, dynamic>> scenes,
    required int totalDays,
  }) {
    LogService.instance.info('Step 1: 归档事件...');
    return _recordTriggeredEvents(triggeredEvents, totalDays, scenes);
  }

  /// 步骤 2: 更新 AI 记忆 (最耗时/易失败)
  Future<List<Map<String, dynamic>>> step2_updateAiMemories({
    required Map<String, dynamic> worldConfig,
    required Map<String, dynamic> player,
    required List<Map<String, dynamic>> aiCharacters,
    required List<Map<String, dynamic>> triggeredEvents,
    required String gameTimeStr,
    required int totalDays,
  }) async {
    LogService.instance.info('Step 2: 更新AI记忆...');
    return await _updateAiCharactersMemoryParallel(
      worldConfig: worldConfig,
      player: player,
      aiCharacters: aiCharacters,
      scenes: [], // 记忆更新暂时不需要场景详情，传空优化性能
      triggeredEvents: triggeredEvents,
      gameTimeStr: gameTimeStr,
      totalDays: totalDays,
    );
  }

  /// 步骤 3: 世界状态演化 (场景+玩家)
  Future<Map<String, dynamic>> step3_updateWorldState({
    required List<Map<String, dynamic>> scenes,
    required Map<String, dynamic> player,
    required List<Map<String, dynamic>> triggeredEvents,
    required Map<String, dynamic> worldConfig,
  }) async {
    LogService.instance.info('Step 3: 更新世界状态...');
    // 这里可以是并行任务
    final newScenes = await _updateScenesWithEvents(scenes, triggeredEvents, worldConfig);
    final newPlayer = await _updatePlayerWithEvents(player, triggeredEvents, worldConfig);
    
    return {
      'scenes': newScenes,
      'player': newPlayer,
    };
  }

  /// 步骤 4: 生成新事件
  Future<List<Map<String, dynamic>>> step4_generateNewEvents({
    required Map<String, dynamic> worldConfig,
    required Map<String, dynamic> player, // 使用更新后的
    required List<Map<String, dynamic>> aiCharacters, // 使用更新后的
    required List<Map<String, dynamic>> scenes, // 使用更新后的
    required List<Map<String, dynamic>> recentHistory,
    required String gameTimeStr,
  }) async {
    LogService.instance.info('Step 4: 生成新事件...');
    return await _generateNewEventsForAllCharacters(
      worldConfig: worldConfig,
      player: player,
      aiCharacters: aiCharacters,
      scenes: scenes,
      recentHistory: recentHistory,
      gameTime: gameTimeStr,
    );
  }

  /// 辅助方法: 生成总结文本
  String generateSummary(String gameTime, List<Map<String, dynamic>> triggered, List<Map<String, dynamic>> newEvents) {
    return _generateSettlementSummary(gameTime, triggered, newEvents, []);
  }

  // ---------------------------------------------------------------------------
  // 内部逻辑实现 (保持原有逻辑)
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> _recordTriggeredEvents(
    List<Map<String, dynamic>> triggeredEvents,
    int totalDays,
    List<Map<String, dynamic>> scenes,
  ) {
    return triggeredEvents.map((event) {
      final dialogues = (event['dialogues'] as List?) ?? [];
      final participants = dialogues
          .map((d) => d['name']?.toString())
          .where((name) => name != null && name.isNotEmpty)
          .toSet()
          .toList();

      final sceneId = event['scene_id'];
      final scene = scenes.firstWhere(
        (s) => s['id'] == sceneId || s['name'] == sceneId,
        orElse: () => {'name': sceneId ?? '未知场景'},
      );

      return {
        'id': event['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        'title': event['title'] ?? event['summary'], // 保存标题
        'game_time': totalDays,
        'scene_id': sceneId,
        'scene_name': scene['name'],
        'participants': participants,
        'summary': event['summary'],
        'dialogues': List<Map<String, dynamic>>.from(dialogues),
        'triggered_at': DateTime.now().toIso8601String(),
        'status': 'completed',
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _updateAiCharactersMemoryParallel({
    required Map<String, dynamic> worldConfig,
    required Map<String, dynamic> player,
    required List<Map<String, dynamic>> aiCharacters,
    required List<Map<String, dynamic>> scenes,
    required List<Map<String, dynamic>> triggeredEvents,
    required String gameTimeStr,
    required int totalDays,
  }) async {
    final activeApi = _configService.getActiveLanguageApi();
    final concurrency = activeApi.concurrencyLimit ?? 1;
    final pool = Pool(concurrency);
    final rateLimiter = _configService.getRateLimiterForApi(activeApi);

    final List<Map<String, dynamic>> updatedCharacters = [];
    final List<Future<void>> futures = [];

    for (int i = 0; i < aiCharacters.length; i++) {
      final char = Map<String, dynamic>.from(aiCharacters[i]);
      
      final future = pool.withResource(() async {
        try {
          await rateLimiter.acquire();
          
          final relatedEvents = triggeredEvents.where((e) {
            final dialogues = (e['dialogues'] as List?) ?? [];
            return dialogues.any((d) => d['name'] == char['name']);
          }).toList();

          final updatedChar = await _updateSingleCharacterMemory(
            worldConfig: worldConfig,
            character: char,
            relatedEvents: relatedEvents,
            gameTimeStr: gameTimeStr,
            totalDays: totalDays,
          );

          updatedCharacters.add(updatedChar ?? char);
        } catch (e) {
          LogService.instance.error('  ❌ AI角色 [${char['name']}] 记忆更新失败: $e');
          // 失败时不中断，保留旧状态
          updatedCharacters.add(char);
        }
      });
      futures.add(future);
    }
    await Future.wait(futures);
    await pool.close();
    return updatedCharacters;
  }

  Future<Map<String, dynamic>?> _updateSingleCharacterMemory({
    required Map<String, dynamic> worldConfig,
    required Map<String, dynamic> character,
    required List<Map<String, dynamic>> relatedEvents,
    required String gameTimeStr,
    required int totalDays,
  }) async {
    if (relatedEvents.isEmpty) return character;

    final systemPrompt = '''你是一个游戏世界的记忆管理AI。根据已发生的事件，更新NPC角色的记忆。
记忆应简洁、反映角色视角，并保留对未来有影响的细节。
输出JSON:
{
  "memory_update": "更新后的记忆摘要",
  "status_update": "更新后的状态（如有变化，否则null）"
}''';

    final userPrompt = '''
当前时间: $gameTimeStr
角色信息: ${jsonEncode(character)}
经历事件: ${jsonEncode(relatedEvents)}
''';

    try {
      final response = await _llmService.requestCompletion(
        systemPrompt: systemPrompt,
        messages: [{'role': 'user', 'content': userPrompt}],
        apiConfig: _configService.getActiveLanguageApi(),
      );
      final jsonData = _extractJsonFromResponse(response);
      if (jsonData == null) return character;

      final updatedChar = Map<String, dynamic>.from(character);
      final existingMemory = List<Map<String, dynamic>>.from(updatedChar['memory'] ?? []);
      
      if (jsonData['memory_update'] != null) {
        existingMemory.add({
          'time': totalDays, 
          'content': jsonData['memory_update']
        });
        if (existingMemory.length > 10) existingMemory.removeAt(0);
        updatedChar['memory'] = existingMemory;
      }
      if (jsonData['status_update'] != null) {
        updatedChar['status'] = jsonData['status_update'];
      }
      return updatedChar;
    } catch (e) {
      return character;
    }
  }

  Future<List<Map<String, dynamic>>> _updateScenesWithEvents(
    List<Map<String, dynamic>> scenes,
    List<Map<String, dynamic>> triggeredEvents,
    Map<String, dynamic> worldConfig,
  ) async {
    // 暂时不做场景变化，保留原样
    if (triggeredEvents.isEmpty) return scenes;
    return scenes; 
  }

  Future<Map<String, dynamic>> _updatePlayerWithEvents(
    Map<String, dynamic> player,
    List<Map<String, dynamic>> triggeredEvents,
    Map<String, dynamic> worldConfig,
  ) async {
    // 暂时不做玩家自动变化，保留原样
    if (triggeredEvents.isEmpty) return player;
    return player;
  }

  Future<List<Map<String, dynamic>>> _generateNewEventsForAllCharacters({
    required Map<String, dynamic> worldConfig,
    required Map<String, dynamic> player,
    required List<Map<String, dynamic>> aiCharacters,
    required List<Map<String, dynamic>> scenes,
    required List<Map<String, dynamic>> recentHistory,
    required String gameTime,
  }) async {
    final activeApi = _configService.getActiveLanguageApi();
    final rateLimiter = _configService.getRateLimiterForApi(activeApi);
    await rateLimiter.acquire();

    final worldState = {
      'player': _stripSensitivePlayerInfo(player),
      'ai_characters': aiCharacters.map((c) => _stripMemoryFromCharacter(c)).toList(),
      'scenes': scenes.map((s) => {'name': s['name'], 'status': s['status']}).toList(),
      'recent_history': recentHistory,
    };

    final systemPrompt = '''你是一个游戏世界的命运AI。根据世界状态生成即将发生的事件。
输出JSON数组:
[
  {
    "title": "事件标题",
    "scene_id": "发生场景名称",
    "event_type": "事件类型",
    "generated_by": "主要触发角色名",
    "priority": 1-5,
    "summary": "一句话概要",
    "dialogues": [{"name": "...", "message": "..."}]
  }
]
确保每个事件包含8-15轮详细对话。''';

    final userPrompt = '''
时间: $gameTime
世界状态: ${jsonEncode(worldState)}
AI角色: ${jsonEncode(aiCharacters)}
''';

    try {
      final response = await _llmService.requestCompletion(
        systemPrompt: systemPrompt,
        messages: [{'role': 'user', 'content': userPrompt}],
        apiConfig: activeApi,
      );
      final jsonData = _extractJsonFromResponse(response);
      if (jsonData == null || jsonData is! List) return [];

      final List<Map<String, dynamic>> validEvents = [];
      for (var eventData in jsonData) {
        if (eventData is! Map) continue;
        validEvents.add({
          'id': '${eventData['generated_by'] ?? 'event'}_${DateTime.now().millisecondsSinceEpoch}_${validEvents.length}',
          'title': eventData['title'] ?? eventData['summary'], // 如果AI没生成title，兜底用summary
          'scene_id': eventData['scene_id'],
          'event_type': eventData['event_type'],
          'generated_by': eventData['generated_by'],
          'priority': eventData['priority'] ?? 3,
          'summary': eventData['summary'],
          'status': 'pending',
          'dialogues': List<Map<String, dynamic>>.from(eventData['dialogues'] ?? []),
        });
      }
      validEvents.sort((a, b) => (b['priority'] ?? 0).compareTo(a['priority'] ?? 0));
      return validEvents;
    } catch (e) {
      LogService.instance.error('生成新事件失败: $e');
      throw e; // 抛出异常以便UI捕获
    }
  }

  String _generateSettlementSummary(String gameTime, List<Map<String, dynamic>> triggered, List<Map<String, dynamic>> newEvents, List updatedChars) {
    final buffer = StringBuffer();
    buffer.writeln('═══ $gameTime 结算完成 ═══\n');
    if (triggered.isNotEmpty) buffer.writeln('📖 已归档 ${triggered.length} 个历史事件。');
    if (newEvents.isNotEmpty) {
      buffer.writeln('✨ 产生了 ${newEvents.length} 个新事件：');
      for (final event in newEvents) {
        final title = event['title'] ?? event['summary'];
        buffer.writeln('  • [${event['scene_id']}] $title');
      }
    } else {
      buffer.writeln('🌙 暂时风平浪静。');
    }
    return buffer.toString();
  }

  // Helpers
  Map<String, dynamic> _stripMemoryFromCharacter(Map<String, dynamic> char) {
    final stripped = Map<String, dynamic>.from(char);
    stripped.remove('memory');
    return stripped;
  }
  Map<String, dynamic> _stripSensitivePlayerInfo(Map<String, dynamic> player) {
    return {'name': player['name'], 'identity': player['identity'], 'status': player['status']};
  }
  dynamic _extractJsonFromResponse(String response) {
    try {
      final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(response);
      final jsonString = jsonMatch?.group(1) ?? response;
      return jsonDecode(jsonString.trim());
    } catch (e) {
      return null;
    }
  }
}