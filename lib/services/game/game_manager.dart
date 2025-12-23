// lib/services/game/game_manager.dart

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../models/bookshelf_entry.dart';
import '../../base/log/log_service.dart';
import 'game_settlement_service.dart';

class GameManager {
  final BookshelfEntry entry;

  // config_world.json: 存储世界设定 + 时间进度 + 当前场景
  Map<String, dynamic> worldConfig = {};
  
  Map<String, dynamic> player = {};
  List<Map<String, dynamic>> aiCharacters = [];
  List<Map<String, dynamic>> _persistentScenes = [];
  List<Map<String, dynamic>> scenes = [];
  Map<String, dynamic> eventLogbook = {};

  GameManager(this.entry);

  File get _worldConfigFile => File(p.join(entry.subCachePath, 'config_world.json'));
  File get _playerFile => File(p.join(entry.subCachePath, 'data_player.json'));
  File get _aiCharsFile => File(p.join(entry.subCachePath, 'data_ai_characters.json'));
  File get _scenesFile => File(p.join(entry.subCachePath, 'data_scenes.json'));
  File get _logbookFile => File(p.join(entry.subCachePath, 'event_logbook.json'));

  // --- Getters for Time & State from config_world ---
  int get day => worldConfig['day'] ?? 1;
  int get week => worldConfig['week'] ?? 1;
  String? get currentSceneId => worldConfig['current_scene_id'];

  Future<void> loadGameData() async {
    try {
      if (await _worldConfigFile.exists()) {
        worldConfig = jsonDecode(await _worldConfigFile.readAsString());
        // 清理可能存在的旧 resume_state 数据，保持干净
        if (worldConfig.containsKey('resume_state')) {
          worldConfig.remove('resume_state');
        }
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

        LogService.instance.info('🛠️ 生成临时场景: $sceneId');
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

  /// 开始事件：只更新 current_scene_id
  Future<void> startEvent(Map<String, dynamic> event) async {
    // 确保事件有 ID
    if (event['id'] == null) {
      event['id'] = '${event['scene_id']}_${DateTime.now().millisecondsSinceEpoch}';
    }
    
    // 更新当前场景
    if (event['scene_id'] != null) {
      worldConfig['current_scene_id'] = event['scene_id'];
      await _worldConfigFile.writeAsString(jsonEncode(worldConfig));
    }
  }

  /// 完成事件：从 Pending 移至 Triggered
  Future<void> completeEvent(Map<String, dynamic> event) async {
    final pendingEvents = List<Map<String, dynamic>>.from(eventLogbook['pending_events'] ?? []);
    final triggeredEvents = List<Map<String, dynamic>>.from(eventLogbook['triggered_events'] ?? []);

    final index = pendingEvents.indexWhere((e) => e['id'] == event['id']);
    if (index != -1) {
      final completedEvent = pendingEvents.removeAt(index);
      completedEvent['completed_at'] = DateTime.now().toIso8601String();
      triggeredEvents.add(completedEvent);
      
      LogService.instance.info('✅ 事件完成: ${event['scene_id']} - 移入 triggered_events');
    }

    eventLogbook['pending_events'] = pendingEvents;
    eventLogbook['triggered_events'] = triggeredEvents;

    _refreshScenesList();
    await saveGameData();
  }

  Future<String> processTurnSettlement({required bool isNextWeek}) async {
    LogService.instance.info('🌅 开始回合结算...');

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

      LogService.instance.success('✅ 回合结算完成');
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