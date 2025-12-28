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

  // config_world.json: 存储世界设定 + 时间进度 + 当前场景
  Map<String, dynamic> worldConfig = {};
  
  Map<String, dynamic> player = {};
  List<Map<String, dynamic>> aiCharacters = [];
  List<Map<String, dynamic>> _persistentScenes = [];
  List<Map<String, dynamic>> scenes = [];
  
  // event_logbook.json: 仅用于存储历史归档 (history_events, logs)
  Map<String, dynamic> eventLogbook = {};
  
  // 新增：今日事件列表 (完全接管 pending_events 和 current_event 的功能)
  // 对应文件: today_event.json
  List<Map<String, dynamic>> todayEvents = [];

  // 服务实例
  final GameEventAiService _aiService = GameEventAiService.instance;

  GameManager(this.entry);

  File get _worldConfigFile => File(p.join(entry.subCachePath, 'config_world.json'));
  File get _playerFile => File(p.join(entry.subCachePath, 'data_player.json'));
  File get _aiCharsFile => File(p.join(entry.subCachePath, 'data_ai_characters.json'));
  File get _scenesFile => File(p.join(entry.subCachePath, 'data_scenes.json'));
  
  // 变更：不再混合存储在 logbook 中，历史归档单独存放
  File get _logbookFile => File(p.join(entry.subCachePath, 'event_logbook.json'));
  
  // 变更：不再使用 current_event.json，改用 today_event.json 管理今日所有动态
  File get _todayEventFile => File(p.join(entry.subCachePath, 'today_event.json'));

  // --- Getters ---
  int get day => worldConfig['day'] ?? 1;
  int get week => worldConfig['week'] ?? 1;
  String? get currentSceneId => worldConfig['current_scene_id'];

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
    // 只提取状态为 pending 或 playing 的事件的场景，completed 的不再显示临时场景
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
      'game_time_ref': 'W${week}D$day',
      'events': todayEvents,
    };
    await _todayEventFile.writeAsString(jsonEncode(data));
  }

  /// 获取某场景下的待触发/进行中事件
  List<Map<String, dynamic>> getEventsForScene(Map<String, dynamic> scene) {
    final sceneName = scene['name'];
    final sceneId = scene['id'];

    // 只返回 pending 或 playing 状态的事件
    return todayEvents.where((e) {
      final target = e['scene_id'];
      final isMatch = target == sceneName || target == sceneId;
      final status = e['status'] ?? 'pending';
      return isMatch && (status == 'pending' || status == 'playing');
    }).toList();
  }

  /// 实时保存当前事件进度到 today_event.json
  /// 将进度直接更新到 list 中的对应项
  Future<void> saveCurrentEventProgress(Map<String, dynamic> eventData, int currentIndex) async {
    final index = todayEvents.indexWhere((e) => e['id'] == eventData['id']);
    if (index != -1) {
      // 更新内存中的事件数据
      todayEvents[index]['dialogues'] = eventData['dialogues']; // 包含AI生成的新对话
      todayEvents[index]['breakpoint_index'] = currentIndex;  // 记录读到的位置
      todayEvents[index]['status'] = 'playing';               // 确保状态为进行中
      todayEvents[index]['last_updated'] = DateTime.now().toIso8601String();
      
      // 持久化到 today_event.json
      await _saveTodayEvents();
      LogService.instance.info('✅ 事件进度已保存: ${eventData['id']} (Idx: $currentIndex)');
    } else {
      LogService.instance.warn('⚠️ 尝试保存不存在的事件: ${eventData['id']}');
    }
  }

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

    // 标记状态为 playing 并保存
    final index = todayEvents.indexWhere((e) => e['id'] == event['id']);
    if (index != -1) {
      todayEvents[index]['status'] = 'playing';
      await _saveTodayEvents();
    }
  }

  /// 结束并结算事件
  Future<void> completeEvent(Map<String, dynamic> finalEventData, {int? breakpointIndex}) async {
    final eventId = finalEventData['id'];

    // 1. 处理对话截取 (Commit 最终发生的剧情)
    List<dynamic> finalDialogues = List.from(finalEventData['dialogues'] ?? []);
    if (breakpointIndex != null && breakpointIndex >= 0 && breakpointIndex < finalDialogues.length) {
      finalDialogues = finalDialogues.sublist(0, breakpointIndex + 1);
    }

    final completedEvent = Map<String, dynamic>.from(finalEventData);
    completedEvent['dialogues'] = finalDialogues;
    completedEvent['completed_at'] = DateTime.now().toIso8601String();
    completedEvent['status'] = 'completed'; // 标记为完成

    // 2. 更新 todayEvents 列表中的该事件
    final index = todayEvents.indexWhere((e) => e['id'] == eventId);
    if (index != -1) {
      todayEvents[index] = completedEvent;
    } else {
      // 理论上不应该走到这，除非是无来源事件
      todayEvents.add(completedEvent);
    }

    // 3. 刷新场景列表（完成的临时事件对应的场景可能不再需要显示）与保存
    _refreshScenesList();
    await saveGameData(); // 包含保存 _todayEventFile
  }

  /// 调用 AI 生成后续 (保持不变)
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
    
    // 1. 收集今日已完成的事件，准备归档到历史
    final completedEvents = todayEvents.where((e) => e['status'] == 'completed').toList();

    try {
      final result = await GameSettlementService.instance.processSettlement(
        worldConfig: worldConfig,
        player: player,
        aiCharacters: aiCharacters,
        scenes: _persistentScenes, 
        triggeredEvents: completedEvents,
        currentDay: day,
        currentWeek: week,
      );

      // 更新状态
      player = result.updatedPlayer;
      aiCharacters = result.updatedAiCharacters;
      _persistentScenes = result.updatedScenes;

      // 归档历史 (将今日完成的事件存入总历史)
      final historyEvents = List<Map<String, dynamic>>.from(eventLogbook['history_events'] ?? []);
      historyEvents.addAll(result.historyEvents);
      eventLogbook['history_events'] = historyEvents;
      
      // 添加日志
      final logEntry = {
        'time': DateTime.now().toIso8601String(),
        'game_time': '第$week周 第$day天',
        'completed_events': completedEvents.length,
        'new_events': result.newEvents.length,
      };
      (eventLogbook['logs'] as List).add(logEntry);

      // --- 关键修改：重置今日事件 ---
      // 将结算生成的 newEvents 放入 todayEvents，覆盖旧数据 (旧数据已归档到 history)
      for (var newEvent in result.newEvents) {
        if (newEvent['id'] == null) {
          newEvent['id'] = 'evt_${DateTime.now().millisecondsSinceEpoch}_${result.newEvents.indexOf(newEvent)}';
        }
        newEvent['status'] = 'pending';
      }
      todayEvents = result.newEvents;

      // 时间推进
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

      _refreshScenesList();
      await saveGameData(); // 统一保存所有文件

      return result.summary;
    } catch (e, s) {
      LogService.instance.error('❌ 回合结算失败', e, s);
      await saveGameData(); // 即使失败也尝试保存当前状态
      rethrow;
    }
  }

  Map<String, int> getEventStats() {
    final pending = todayEvents.where((e) => e['status'] == 'pending' || e['status'] == 'playing').length;
    return {'total': pending};
  }
}