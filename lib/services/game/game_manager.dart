// lib/services/game/game_manager.dart

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../models/bookshelf_entry.dart';
import '../../base/log/log_service.dart';
import 'game_settlement_service.dart'; // 引入 Context 定义
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

  /// 计算当前周数
  int get currentWeek => ((totalDays - 1) ~/ 7) + 1;

  /// 计算当前是周几
  int get currentDayOfWeek => ((totalDays - 1) % 7) + 1;

  /// 获取历史事件列表 (按触发时间倒序)
  List<Map<String, dynamic>> get historyEvents {
    final list = List<Map<String, dynamic>>.from(eventLogbook['history_events'] ?? []);
    return list.reversed.toList();
  }

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
        eventLogbook = {'history_events': [], 'logs': []};
      }
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

  // === 更新世界配置项 ===
  Future<void> updateWorldSetting(String key, String value) async {
    worldConfig[key] = value;
    await _worldConfigFile.writeAsString(jsonEncode(worldConfig));
    LogService.instance.info('配置项 [$key] 已更新');
  }

  // === 更新玩家档案 ===
  Future<void> updatePlayerProfile(Map<String, dynamic> newPlayerData) async {
    player.addAll(newPlayerData);
    await _playerFile.writeAsString(jsonEncode(player));
    LogService.instance.info('玩家档案已更新');
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
    }
  }

  Future<void> startEvent(Map<String, dynamic> event) async {
    if (event['id'] == null) {
      event['id'] = '${event['scene_id']}_${DateTime.now().millisecondsSinceEpoch}';
    }
    final index = todayEvents.indexWhere((e) => e['id'] == event['id']);
    if (index != -1) {
      todayEvents[index]['status'] = 'playing';
      await _saveTodayEvents();
    }
  }

  Future<void> reactivateEvent(String eventId) async {
    final index = todayEvents.indexWhere((e) => e['id'] == eventId);
    if (index != -1) {
      todayEvents[index]['status'] = 'pending';
      todayEvents[index]['breakpoint_index'] = 0;
      todayEvents[index].remove('completed_at');
      await _saveTodayEvents();
      _refreshScenesList();
    }
  }

  Future<void> completeEvent(Map<String, dynamic> finalEventData, {int? breakpointIndex}) async {
    final eventId = finalEventData['id'];
    List<dynamic> finalDialogues = List.from(finalEventData['dialogues'] ?? []);

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

  Map<String, int> getEventStats() {
    final pending = todayEvents.where((e) => e['status'] == 'pending' || e['status'] == 'playing').length;
    return {'total': pending};
  }

  // --- 新增: 支持分步结算的接口 ---

  /// 获取所有已完成的事件（用于结算归档）
  List<Map<String, dynamic>> getCompletedEvents() {
    return todayEvents.where((e) => e['status'] == 'completed').toList();
  }

  /// 获取结算显示用的时间字符串
  String getSettlementGameTimeStr() {
     final week = ((totalDays - 1) ~/ 7) + 1;
     final day = ((totalDays - 1) % 7) + 1;
     return '第$week周第$day天';
  }

  /// 应用结算结果 (在 UI 流程全部成功后调用)
  Future<void> applySettlementResult(SettlementContext ctx, bool isNextWeek) async {
    // 1. 更新内存数据
    player = ctx.updatedPlayer;
    aiCharacters = ctx.updatedAiCharacters;
    _persistentScenes = ctx.updatedScenes;
    
    // 2. 归档历史
    final historyEvents = List<Map<String, dynamic>>.from(eventLogbook['history_events'] ?? []);
    historyEvents.addAll(ctx.historyEvents);
    eventLogbook['history_events'] = historyEvents;
    
    // 3. 记录 Log
    final logEntry = {
      'time': DateTime.now().toIso8601String(),
      'game_time': ctx.gameTimeStr,
      'completed_events': ctx.triggeredEvents.length,
      'new_events': ctx.newEvents.length,
    };
    (eventLogbook['logs'] as List).add(logEntry);

    // 4. 应用新事件
    for (var newEvent in ctx.newEvents) {
      if (newEvent['id'] == null) {
        newEvent['id'] = 'evt_${DateTime.now().millisecondsSinceEpoch}_${ctx.newEvents.indexOf(newEvent)}';
      }
      newEvent['status'] = 'pending';
    }
    todayEvents = ctx.newEvents;

    // 5. 推进时间
    if (isNextWeek) {
      int daysToSkip = 8 - currentDayOfWeek;
      worldConfig['total_days'] = totalDays + daysToSkip;
    } else {
      worldConfig['total_days'] = totalDays + 1;
    }

    // 6. 保存并刷新
    _refreshScenesList();
    await saveGameData();
    LogService.instance.info("结算数据已应用并保存。");
  }
}