// lib/services/game/game_manager.dart

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../models/bookshelf_entry.dart';
import '../../base/log/log_service.dart';
import 'game_settlement_service.dart';
import 'game_event_ai_service.dart'; // 引入新服务

class GameManager {
  final BookshelfEntry entry;

  // config_world.json: 存储世界设定 + 时间进度 + 当前场景
  Map<String, dynamic> worldConfig = {};
  
  Map<String, dynamic> player = {};
  List<Map<String, dynamic>> aiCharacters = [];
  List<Map<String, dynamic>> _persistentScenes = [];
  List<Map<String, dynamic>> scenes = [];
  Map<String, dynamic> eventLogbook = {};

  // 服务实例
  final GameEventAiService _aiService = GameEventAiService.instance;

  GameManager(this.entry);

  File get _worldConfigFile => File(p.join(entry.subCachePath, 'config_world.json'));
  File get _playerFile => File(p.join(entry.subCachePath, 'data_player.json'));
  File get _aiCharsFile => File(p.join(entry.subCachePath, 'data_ai_characters.json'));
  File get _scenesFile => File(p.join(entry.subCachePath, 'data_scenes.json'));
  File get _logbookFile => File(p.join(entry.subCachePath, 'event_logbook.json'));
  
  // 当前正在进行的事件暂存文件
  File get _currentEventFile => File(p.join(entry.subCachePath, 'current_event.json'));

  // --- Getters ---
  int get day => worldConfig['day'] ?? 1;
  int get week => worldConfig['week'] ?? 1;
  String? get currentSceneId => worldConfig['current_scene_id'];

  Future<void> loadGameData() async {
    try {
      if (await _worldConfigFile.exists()) {
        worldConfig = jsonDecode(await _worldConfigFile.readAsString());
        // 清理旧数据
        worldConfig.remove('resume_state');
      }
      if (await _playerFile.exists()) {
        player = jsonDecode(await _playerFile.readAsString());
      }
      if (await _aiCharsFile.exists()) {
        final List list = jsonDecode(await _aiCharsFile.readAsString());
        aiCharacters = list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      if (await _scenesFile.exists()) {
        final List list = jsonDecode(await _scenesFile.readAsString());
        _persistentScenes = list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      
      if (await _logbookFile.exists()) {
        eventLogbook = jsonDecode(await _logbookFile.readAsString());
      } else {
        eventLogbook = {
          'pending_events': [],   
          'triggered_events': [], 
          'history_events': [],   
          'logs': [],
        };
      }

      // 初始化必要的键值
      eventLogbook.putIfAbsent('pending_events', () => []);
      eventLogbook.putIfAbsent('triggered_events', () => []);
      eventLogbook.putIfAbsent('history_events', () => []);
      eventLogbook.putIfAbsent('logs', () => []);

      _migrateEventIds();
      _refreshScenesList();
    } catch (e, s) {
      LogService.instance.error('GameManager: 加载数据失败', e, s);
      rethrow;
    }
  }

  void _migrateEventIds() {
    final pending = List<Map<String, dynamic>>.from(eventLogbook['pending_events'] ?? []);
    bool changed = false;
    for (var i = 0; i < pending.length; i++) {
      if (pending[i]['id'] == null) {
        pending[i]['id'] = 'evt_${DateTime.now().millisecondsSinceEpoch}_$i';
        changed = true;
      }
    }
    if (changed) {
      eventLogbook['pending_events'] = pending;
    }
  }

  void _refreshScenesList() {
    final combinedScenes = List<Map<String, dynamic>>.from(_persistentScenes);
    final existingIds = combinedScenes.map((s) => s['id']).toSet();
    final existingNames = combinedScenes.map((s) => s['name']).toSet();

    final pendingEvents = List<Map<String, dynamic>>.from(eventLogbook['pending_events'] ?? []);
    
    for (var event in pendingEvents) {
      final sceneId = event['scene_id'] as String?;
      if (sceneId == null || sceneId.isEmpty) continue;
      
      if (!existingIds.contains(sceneId) && !existingNames.contains(sceneId)) {
        final alreadyAdded = combinedScenes.any((s) => s['id'] == sceneId || s['name'] == sceneId);
        if (alreadyAdded) continue;

        combinedScenes.add({
          'id': sceneId,
          'name': sceneId,
          'description': '（临时场景）由此地发生的突发事件产生。',
          'status': '未知',
          'is_temporary': true,
        });
      }
    }
    scenes = combinedScenes;
  }

  Future<void> saveGameData() async {
    await _worldConfigFile.writeAsString(jsonEncode(worldConfig));
    await _playerFile.writeAsString(jsonEncode(player));
    await _aiCharsFile.writeAsString(jsonEncode(aiCharacters));
    await _scenesFile.writeAsString(jsonEncode(_persistentScenes));
    await _logbookFile.writeAsString(jsonEncode(eventLogbook));
  }

  List<Map<String, dynamic>> getEventsForScene(Map<String, dynamic> scene) {
    final pendingEvents = List<Map<String, dynamic>>.from(eventLogbook['pending_events'] ?? []);
    final sceneName = scene['name'];
    final sceneId = scene['id'];

    return pendingEvents.where((e) {
      final target = e['scene_id'];
      return target == sceneName || target == sceneId;
    }).toList();
  }

  // --- 事件实时记录管理 ---

  /// 实时保存当前事件进度到 current_event.json
  Future<void> saveCurrentEventProgress(Map<String, dynamic> eventData, int currentIndex) async {
    try {
      final progress = {
        'event_id': eventData['id'],
        'scene_id': eventData['scene_id'],
        'breakpoint_index': currentIndex,
        'dialogues': eventData['dialogues'], // 保存包含AI生成内容的完整对话
        'last_updated': DateTime.now().toIso8601String(),
      };
      await _currentEventFile.writeAsString(jsonEncode(progress));
    } catch (e) {
      LogService.instance.error('保存事件进度失败', e);
    }
  }

  /// 清除事件进度文件
  Future<void> clearCurrentEventProgress() async {
    if (await _currentEventFile.exists()) {
      await _currentEventFile.delete();
    }
  }

  // --- 核心事件逻辑 ---

  /// 开始事件
  Future<void> startEvent(Map<String, dynamic> event) async {
    if (event['id'] == null) {
      event['id'] = '${event['scene_id']}_${DateTime.now().millisecondsSinceEpoch}';
    }
    
    // 更新当前位置
    if (event['scene_id'] != null) {
      worldConfig['current_scene_id'] = event['scene_id'];
      await _worldConfigFile.writeAsString(jsonEncode(worldConfig));
    }

    // 初始记录
    await saveCurrentEventProgress(event, 0);
  }

  /// 结束并结算事件
  /// [finalEventData]: 最终的事件数据
  /// [breakpointIndex]: 如果提供，将截取到此处作为最终发生的剧情
  Future<void> completeEvent(Map<String, dynamic> finalEventData, {int? breakpointIndex}) async {
    final pendingEvents = List<Map<String, dynamic>>.from(eventLogbook['pending_events'] ?? []);
    final triggeredEvents = List<Map<String, dynamic>>.from(eventLogbook['triggered_events'] ?? []);
    final eventId = finalEventData['id'];

    // 1. 处理对话截取：根据断点截取实际发生的剧情
    List<dynamic> finalDialogues = List.from(finalEventData['dialogues'] ?? []);
    if (breakpointIndex != null && breakpointIndex >= 0 && breakpointIndex < finalDialogues.length) {
      // 保留 0 到 breakpointIndex 的内容 (包含 breakpointIndex)
      finalDialogues = finalDialogues.sublist(0, breakpointIndex + 1);
    }

    // 2. 准备要保存的数据对象
    final completedEvent = Map<String, dynamic>.from(finalEventData);
    completedEvent['dialogues'] = finalDialogues;
    completedEvent['completed_at'] = DateTime.now().toIso8601String(); // 更新完成时间
    completedEvent['status'] = 'completed'; // 确保存储状态为已完成

    // 3. 从待触发列表中移除
    pendingEvents.removeWhere((e) => e['id'] == eventId);

    // --- 覆盖保存逻辑 ---
    final existingIndex = triggeredEvents.indexWhere((e) => e['id'] == eventId);
    
    if (existingIndex != -1) {
      // A. 如果已存在：覆盖旧数据
      triggeredEvents[existingIndex] = completedEvent;
      LogService.instance.info('🔄 事件已更新 (覆盖保存): $eventId');
    } else {
      // B. 如果不存在：追加新数据
      triggeredEvents.add(completedEvent);
      LogService.instance.info('✅ 事件已归档 (新增): $eventId');
    }

    // 4. 更新内存中的 Logbook
    eventLogbook['pending_events'] = pendingEvents;
    eventLogbook['triggered_events'] = triggeredEvents;

    // 5. 清理与持久化
    _refreshScenesList();
    await saveGameData();
    await clearCurrentEventProgress();
  }

  /// 调用 AI 生成后续
  Future<Map<String, dynamic>> generateEventContinuation({
    required List<Map<String, dynamic>> currentDialogues,
    required String userInput,
    required String sceneId,
  }) async {
    // 准备上下文：为了节省 Token，建议只取最近的 10-15 条对话记录
    final recentHistory = currentDialogues.length > 15 
        ? currentDialogues.sublist(currentDialogues.length - 15) 
        : currentDialogues;

    // 查找场景对象
    final sceneObj = scenes.firstWhere(
      (s) => s['name'] == sceneId || s['id'] == sceneId, 
      orElse: () => {'name': sceneId}
    );

    return await _aiService.generateEventContinuation(
      recentDialogues: recentHistory,
      userInput: userInput,
      sceneId: sceneId,
      playerInfo: player,
      currentScene: sceneObj,
    );
  }

  // --- 回合结算 ---

  Future<String> processTurnSettlement({required bool isNextWeek}) async {
    
    final triggeredEvents = List<Map<String, dynamic>>.from(eventLogbook['triggered_events'] ?? []);

    try {
      final result = await GameSettlementService.instance.processSettlement(
        worldConfig: worldConfig,
        player: player,
        aiCharacters: aiCharacters,
        scenes: _persistentScenes, 
        triggeredEvents: triggeredEvents,
        currentDay: day,
        currentWeek: week,
      );

      player = result.updatedPlayer;
      aiCharacters = result.updatedAiCharacters;
      _persistentScenes = result.updatedScenes;

      final historyEvents = List<Map<String, dynamic>>.from(eventLogbook['history_events'] ?? []);
      historyEvents.addAll(result.historyEvents);
      eventLogbook['history_events'] = historyEvents;
      
      eventLogbook['pending_events'] = []; 
      eventLogbook['triggered_events'] = [];

      for (var newEvent in result.newEvents) {
        if (newEvent['id'] == null) {
          newEvent['id'] = 'evt_${DateTime.now().millisecondsSinceEpoch}_${result.newEvents.indexOf(newEvent)}';
        }
        newEvent['status'] = 'pending';
      }
      eventLogbook['pending_events'] = result.newEvents;

      if (isNextWeek) {
        worldConfig['week'] = (worldConfig['week'] ?? 1) + 1;
        worldConfig['day'] = 1;
      } else {
        int currentDay = worldConfig['day'] ?? 1;
        currentDay++;
        if (currentDay > 7) {
          worldConfig['week'] = (worldConfig['week'] ?? 1) + 1;
          worldConfig['day'] = 1;
        } else {
          worldConfig['day'] = currentDay;
        }
      }

      final logEntry = {
        'time': DateTime.now().toIso8601String(),
        'game_time': '第$week周 第$day天',
        'triggered_count': triggeredEvents.length,
        'new_events_count': result.newEvents.length,
      };
      (eventLogbook['logs'] as List).add(logEntry);

      _refreshScenesList();
      await saveGameData();

      return result.summary;
    } catch (e, s) {
      LogService.instance.error('❌ 回合结算失败', e, s);
      await saveGameData();
      rethrow;
    }
  }

  Map<String, int> getEventStats() {
    final pending = (eventLogbook['pending_events'] as List?)?.length ?? 0;
    return {'total': pending};
  }
}