// lib/game_system/game_manager.dart

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../models/bookshelf_entry.dart';
import '../../base/log/log_service.dart';

class GameManager {
  final BookshelfEntry entry;
  
  Map<String, dynamic> worldConfig = {};
  Map<String, dynamic> player = {};
  List<Map<String, dynamic>> aiCharacters = [];
  List<Map<String, dynamic>> scenes = [];
  Map<String, dynamic> gameState = {};

  GameManager(this.entry);

  File get _worldConfigFile => File(p.join(entry.subCachePath, 'config_world.json'));
  File get _playerFile => File(p.join(entry.subCachePath, 'data_player.json'));
  File get _aiCharsFile => File(p.join(entry.subCachePath, 'data_ai_characters.json'));
  File get _scenesFile => File(p.join(entry.subCachePath, 'data_scenes.json'));
  File get _gameStateFile => File(p.join(entry.subCachePath, 'game_state.json'));
  
  Future<void> loadGameData() async {
    try {
      if (await _worldConfigFile.exists()) {
        worldConfig = jsonDecode(await _worldConfigFile.readAsString());
      }
      if (await _playerFile.exists()) {
        player = jsonDecode(await _playerFile.readAsString());
      }
      if (await _aiCharsFile.exists()) {
        final List list = jsonDecode(await _aiCharsFile.readAsString());
        aiCharacters = list.map((e) => e as Map<String, dynamic>).toList();
      }
      if (await _scenesFile.exists()) {
        final List list = jsonDecode(await _scenesFile.readAsString());
        scenes = list.map((e) => e as Map<String, dynamic>).toList();
      }
      if (await _gameStateFile.exists()) {
        gameState = jsonDecode(await _gameStateFile.readAsString());
      } else {
        gameState = {'day': 1, 'week': 1, 'logs': [], 'pending_events': []};
      }
    } catch (e, s) {
      LogService.instance.error('GameManager: 加载数据失败', e, s);
      rethrow;
    }
  }

  Future<void> saveGameData() async {
    await _playerFile.writeAsString(jsonEncode(player));
    await _aiCharsFile.writeAsString(jsonEncode(aiCharacters));
    await _scenesFile.writeAsString(jsonEncode(scenes));
    await _gameStateFile.writeAsString(jsonEncode(gameState));
  }

  /// 获取指定场景的所有待触发事件
  List<Map<String, dynamic>> getEventsForScene(Map<String, dynamic> scene) {
    final pendingEvents = List<Map<String, dynamic>>.from(gameState['pending_events'] ?? []);
    final sceneName = scene['name'];
    final sceneId = scene['id'];

    return pendingEvents.where((e) {
      final target = e['scene_id'];
      // 匹配 ID 或 名字
      return target == sceneName || target == sceneId;
    }).toList();
  }

  /// 移除已触发的事件
  Future<void> removeEvent(Map<String, dynamic> event) async {
    final pendingEvents = List<Map<String, dynamic>>.from(gameState['pending_events'] ?? []);
    
    // 简单的移除逻辑，实际项目中可能需要更唯一的 ID
    pendingEvents.removeWhere((e) => 
      e['scene_id'] == event['scene_id'] && 
      jsonEncode(e['dialogues']) == jsonEncode(event['dialogues'])
    );
    
    gameState['pending_events'] = pendingEvents;
    await saveGameData();
  }

  /// 处理回合结算
  Future<String> processTurnSettlement({required bool isNextWeek}) async {
    if (isNextWeek) {
      gameState['week'] = (gameState['week'] ?? 1) + 1;
      gameState['day'] = 1; 
    } else {
      gameState['day'] = (gameState['day'] ?? 1) + 1;
      if (gameState['day'] > 7) {
        gameState['week'] = (gameState['week'] ?? 1) + 1;
        gameState['day'] = 1;
      }
    }

    await Future.delayed(const Duration(seconds: 2)); // 模拟等待

    // --- Mock 数据生成 ---
    // 随机给某个场景生成事件，用于测试 UI
    if (scenes.isNotEmpty) {
      final randomScene = (scenes..shuffle()).first;
      final newEvent = {
        'scene_id': randomScene['name'],
        'dialogues': [
          {'name': '系统', 'message': '这是一个新生成的随机事件，发生在 ${randomScene['name']}。'},
          {'name': '神秘人', 'message': '既然你来到了这里，就必须要接受命运的考验...'},
          {'name': '玩家', 'message': '你是谁？'},
          {'name': '神秘人', 'message': '呵呵，无可奉告。'}
        ]
      };
      
      List<dynamic> currentPending = gameState['pending_events'] ?? [];
      currentPending.add(newEvent);
      gameState['pending_events'] = currentPending;
    }

    final summary = "第${gameState['week']}周第${gameState['day']}天结算完成。\n世界发生了变化，请查看地图上的标记。";
    await saveGameData();
    return summary;
  }
}