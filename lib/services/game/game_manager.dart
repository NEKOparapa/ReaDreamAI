// lib/services/game/game_manager.dart

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../models/bookshelf_entry.dart';
import '../../base/log/log_service.dart';
import 'game_settlement_service.dart';
import 'game_event_ai_service.dart';

class GameManager {
  final BookshelfEntry entry;

  // config_world.json: 存储世界设定 + 时间进度
  Map<String, dynamic> worldConfig = {};
  
  Map<String, dynamic> player = {};
  List<Map<String, dynamic>> aiCharacters = [];
  List<Map<String, dynamic>> _persistentScenes = [];
  List<Map<String, dynamic>> scenes = [];
  
  // event_logbook.json: 仅用于存储历史归档 (history_events, logs)
  Map<String, dynamic> eventLogbook = {};
  
  // today_event.json: 管理今日所有动态
  List<Map<String, dynamic>> todayEvents = [];

  // 服务实例
  final GameEventAiService _aiService = GameEventAiService.instance;

  GameManager(this.entry);

  File get _worldConfigFile => File(p.join(entry.subCachePath, 'config_world.json'));
  File get _playerFile => File(p.join(entry.subCachePath, 'data_player.json'));
  File get _aiCharsFile => File(p.join(entry.subCachePath, 'data_ai_characters.json'));
  File get _scenesFile => File(p.join(entry.subCachePath, 'data_scenes.json'));
  File get _logbookFile => File(p.join(entry.subCachePath, 'event_logbook.json'));
  File get _todayEventFile => File(p.join(entry.subCachePath, 'today_event.json'));

  // --- Getters: 时间换算逻辑 ---
  
  /// 获取游戏总天数 (默认为1)
  int get totalDays => worldConfig['total_days'] ?? 1;

  /// 计算当前周数: (总天数-1) / 7 + 1
  int get currentWeek => ((totalDays - 1) ~/ 7) + 1;

  /// 计算当前是周几: (总天数-1) % 7 + 1
  int get currentDayOfWeek => ((totalDays - 1) % 7) + 1;

  // [删除] currentSceneId 及其 getter

  Future<void> loadGameData() async {
    try {
      if (await _worldConfigFile.exists()) {
        worldConfig = jsonDecode(await _worldConfigFile.readAsString());
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
      
      // 加载历史归档
      if (await _logbookFile.exists()) {
        eventLogbook = jsonDecode(await _logbookFile.readAsString());
      } else {
        eventLogbook = {
          'history_events': [],   
          'logs': [],
        };
      }
      // 确保 key 存在
      eventLogbook.putIfAbsent('history_events', () => []);
      eventLogbook.putIfAbsent('logs', () => []);

      // 加载今日事件
      if (await _todayEventFile.exists()) {
        try {
          final Map<String, dynamic> todayData = jsonDecode(await _todayEventFile.readAsString());
          todayEvents = List<Map<String, dynamic>>.from(todayData['events'] ?? []);
        } catch (e) {
          LogService.instance.error('加载 today_event.json 异常', e);
          todayEvents = [];
        }
      } else {
        todayEvents = [];
      }

      _migrateEventIds();
      _refreshScenesList();
    } catch (e, s) {
      LogService.instance.error('GameManager: 加载数据失败', e, s);
      rethrow;
    }
  }

  void _migrateEventIds() {
    bool changed = false;
    for (var i = 0; i < todayEvents.length; i++) {
      if (todayEvents[i]['id'] == null) {
        todayEvents[i]['id'] = 'evt_${DateTime.now().millisecondsSinceEpoch}_$i';
        changed = true;
      }
    }
    if (changed) {
      _saveTodayEvents();
    }
  }

  void _refreshScenesList() {
    final combinedScenes = List<Map<String, dynamic>>.from(_persistentScenes);
    final existingIds = combinedScenes.map((s) => s['id']).toSet();
    final existingNames = combinedScenes.map((s) => s['name']).toSet();

    // 从 todayEvents 中提取临时场景
    final activeEvents = todayEvents.where((e) => e['status'] != 'completed');
    
    for (var event in activeEvents) {
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
    await _saveTodayEvents();
  }

  Future<void> _saveTodayEvents() async {
    final data = {
      'date': DateTime.now().toIso8601String(),
      'game_time_ref': 'W${currentWeek}D$currentDayOfWeek',
      'events': todayEvents,
    };
    await _todayEventFile.writeAsString(jsonEncode(data));
  }

  List<Map<String, dynamic>> getEventsForScene(Map<String, dynamic> scene) {
    final sceneName = scene['name'];
    final sceneId = scene['id'];

    return todayEvents.where((e) {
      final target = e['scene_id'];
      final isMatch = target == sceneName || target == sceneId;
      final status = e['status'] ?? 'pending';
      return isMatch && (status == 'pending' || status == 'playing');
    }).toList();
  }

  Future<void> saveCurrentEventProgress(Map<String, dynamic> eventData, int currentIndex) async {
    final index = todayEvents.indexWhere((e) => e['id'] == eventData['id']);
    if (index != -1) {
      todayEvents[index]['dialogues'] = eventData['dialogues']; 
      todayEvents[index]['breakpoint_index'] = currentIndex;  
      todayEvents[index]['status'] = 'playing';               
      todayEvents[index]['last_updated'] = DateTime.now().toIso8601String();
      
      await _saveTodayEvents();
      LogService.instance.info('✅ 事件进度已保存: ${eventData['id']} (Idx: $currentIndex)');
    } else {
      LogService.instance.warn('⚠️ 尝试保存不存在的事件: ${eventData['id']}');
    }
  }

  Future<void> startEvent(Map<String, dynamic> event) async {
    if (event['id'] == null) {
      event['id'] = '${event['scene_id']}_${DateTime.now().millisecondsSinceEpoch}';
    }
    
    // [删除] 更新 current_scene_id 的逻辑

    // 标记状态为 playing 并保存
    final index = todayEvents.indexWhere((e) => e['id'] == event['id']);
    if (index != -1) {
      todayEvents[index]['status'] = 'playing';
      await _saveTodayEvents();
    }
  }

  Future<void> completeEvent(Map<String, dynamic> finalEventData, {int? breakpointIndex}) async {
    final eventId = finalEventData['id'];

    List<dynamic> finalDialogues = List.from(finalEventData['dialogues'] ?? []);
    if (breakpointIndex != null && breakpointIndex >= 0 && breakpointIndex < finalDialogues.length) {
      finalDialogues = finalDialogues.sublist(0, breakpointIndex + 1);
    }

    final completedEvent = Map<String, dynamic>.from(finalEventData);
    completedEvent['dialogues'] = finalDialogues;
    completedEvent['completed_at'] = DateTime.now().toIso8601String();
    completedEvent['status'] = 'completed'; 

    final index = todayEvents.indexWhere((e) => e['id'] == eventId);
    if (index != -1) {
      todayEvents[index] = completedEvent;
    } else {
      todayEvents.add(completedEvent);
    }

    _refreshScenesList();
    await saveGameData(); 
  }

  Future<Map<String, dynamic>> generateEventContinuation({
    required List<Map<String, dynamic>> currentDialogues,
    required String userInput,
    required String sceneId,
  }) async {
    final recentHistory = currentDialogues.length > 15 
        ? currentDialogues.sublist(currentDialogues.length - 15) 
        : currentDialogues;

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
    final completedEvents = todayEvents.where((e) => e['status'] == 'completed').toList();

    try {
      final result = await GameSettlementService.instance.processSettlement(
        worldConfig: worldConfig,
        player: player,
        aiCharacters: aiCharacters,
        scenes: _persistentScenes, 
        triggeredEvents: completedEvents,
        totalDays: totalDays, 
      );

      player = result.updatedPlayer;
      aiCharacters = result.updatedAiCharacters;
      _persistentScenes = result.updatedScenes;

      final historyEvents = List<Map<String, dynamic>>.from(eventLogbook['history_events'] ?? []);
      historyEvents.addAll(result.historyEvents);
      eventLogbook['history_events'] = historyEvents;
      
      final logEntry = {
        'time': DateTime.now().toIso8601String(),
        'game_time': '第$totalDays天 (W${currentWeek}D$currentDayOfWeek)',
        'completed_events': completedEvents.length,
        'new_events': result.newEvents.length,
      };
      (eventLogbook['logs'] as List).add(logEntry);

      for (var newEvent in result.newEvents) {
        if (newEvent['id'] == null) {
          newEvent['id'] = 'evt_${DateTime.now().millisecondsSinceEpoch}_${result.newEvents.indexOf(newEvent)}';
        }
        newEvent['status'] = 'pending';
      }
      todayEvents = result.newEvents;

      if (isNextWeek) {
        int daysToSkip = 8 - currentDayOfWeek;
        worldConfig['total_days'] = totalDays + daysToSkip;
      } else {
        worldConfig['total_days'] = totalDays + 1;
      }

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
    final pending = todayEvents.where((e) => e['status'] == 'pending' || e['status'] == 'playing').length;
    return {'total': pending};
  }
}