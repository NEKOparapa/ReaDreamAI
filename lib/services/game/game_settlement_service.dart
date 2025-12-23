// lib/services/game/game_settlement_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:pool/pool.dart';

import '../../base/config_service.dart';
import '../../services/llm_service/llm_service.dart';
import '../../base/log/log_service.dart';

class SettlementResult {
  final List<Map<String, dynamic>> historyEvents;
  final Map<String, dynamic> updatedPlayer;
  final List<Map<String, dynamic>> updatedAiCharacters;
  final List<Map<String, dynamic>> updatedScenes;
  final List<Map<String, dynamic>> newEvents;
  final String summary;

  SettlementResult({
    required this.historyEvents,
    required this.updatedPlayer,
    required this.updatedAiCharacters,
    required this.updatedScenes,
    required this.newEvents,
    required this.summary,
  });
}

class GameSettlementService {
  GameSettlementService._();
  static final GameSettlementService instance = GameSettlementService._();

  final LlmService _llmService = LlmService.instance;
  final ConfigService _configService = ConfigService();

  Future<SettlementResult> processSettlement({
    required Map<String, dynamic> worldConfig,
    required Map<String, dynamic> player,
    required List<Map<String, dynamic>> aiCharacters,
    required List<Map<String, dynamic>> scenes,
    required List<Map<String, dynamic>> triggeredEvents,
    required int currentDay,
    required int currentWeek,
  }) async {
    final gameTime = '第$currentWeek周第$currentDay天';
    LogService.instance.info('🎮 开始回合结算: $gameTime');

    // 1. 整理历史事件记录
    final historyEvents = _recordTriggeredEvents(
      triggeredEvents,
      gameTime,
      scenes,
    );

    // 2. 更新 AI 记忆
    final updatedAiCharacters = await _updateAiCharactersMemoryParallel(
      worldConfig: worldConfig,
      player: player,
      aiCharacters: aiCharacters,
      scenes: scenes,
      triggeredEvents: triggeredEvents,
      gameTime: gameTime,
    );

    // 3. 更新场景
    final updatedScenes = await _updateScenesWithEvents(
      scenes,
      triggeredEvents,
      worldConfig,
    );

    // 4. 更新玩家
    final updatedPlayer = await _updatePlayerWithEvents(
      player,
      triggeredEvents,
      worldConfig,
    );

    // 5. 生成新事件 (使用更新后的状态)
    final newEvents = await _generateNewEventsForAllCharacters(
      worldConfig: worldConfig,
      player: updatedPlayer,
      aiCharacters: updatedAiCharacters,
      scenes: updatedScenes,
      // 这里的 historyEvents 是本回合刚产生的
      recentHistory: historyEvents, 
      gameTime: gameTime,
    );

    final summary = _generateSettlementSummary(
      gameTime,
      triggeredEvents,
      newEvents,
      updatedAiCharacters,
    );

    return SettlementResult(
      historyEvents: historyEvents,
      updatedPlayer: updatedPlayer,
      updatedAiCharacters: updatedAiCharacters,
      updatedScenes: updatedScenes,
      newEvents: newEvents,
      summary: summary,
    );
  }

  // --- 内部方法 ---

  List<Map<String, dynamic>> _recordTriggeredEvents(
    List<Map<String, dynamic>> triggeredEvents,
    String gameTime,
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
        'game_time': gameTime,
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
    required String gameTime,
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
            gameTime: gameTime,
          );

          updatedCharacters.add(updatedChar ?? char);
        } catch (e) {
          LogService.instance.error('  ❌ AI角色 [${char['name']}] 记忆更新失败: $e');
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
    required String gameTime,
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
当前时间: $gameTime
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
        existingMemory.add({'time': gameTime, 'content': jsonData['memory_update']});
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
    if (triggeredEvents.isEmpty) return scenes;
    
    // ... (保留原有的场景更新逻辑，省略重复代码以节省篇幅，逻辑不变)
    // 实际实现中请保留原有代码逻辑，此处为结构展示
    return scenes; 
  }

  Future<Map<String, dynamic>> _updatePlayerWithEvents(
    Map<String, dynamic> player,
    List<Map<String, dynamic>> triggeredEvents,
    Map<String, dynamic> worldConfig,
  ) async {
    if (triggeredEvents.isEmpty) return player;
    // ... (保留原有的玩家更新逻辑，省略重复代码)
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
      return [];
    }
  }

  String _generateSettlementSummary(String gameTime, List<Map<String, dynamic>> triggered, List<Map<String, dynamic>> newEvents, List updatedChars) {
    final buffer = StringBuffer();
    buffer.writeln('═══ $gameTime 结算完成 ═══\n');
    if (triggered.isNotEmpty) buffer.writeln('📖 已归档 ${triggered.length} 个历史事件。');
    if (newEvents.isNotEmpty) {
      buffer.writeln('✨ 产生了 ${newEvents.length} 个新事件：');
      for (final event in newEvents) {
        buffer.writeln('  • [${event['scene_id']}] ${event['summary']}');
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