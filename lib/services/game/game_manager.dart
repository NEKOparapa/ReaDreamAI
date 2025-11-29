// lib/game_system/game_manager.dart

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../models/bookshelf_entry.dart';
import '../../base/log/log_service.dart';

/// 管理游戏书的核心逻辑：IO操作、状态管理、AI调度
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

  /// 加载所有数据
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
        // 默认状态
        gameState = {'day': 1, 'week': 1, 'logs': [], 'pending_events': []};
      }
    } catch (e, s) {
      LogService.instance.error('GameManager: 加载数据失败', e, s);
      rethrow;
    }
  }

  /// 保存所有数据（通常在回合结算后调用）
  Future<void> saveGameData() async {
    await _playerFile.writeAsString(jsonEncode(player));
    await _aiCharsFile.writeAsString(jsonEncode(aiCharacters));
    await _scenesFile.writeAsString(jsonEncode(scenes));
    await _gameStateFile.writeAsString(jsonEncode(gameState));
  }

  /// 获取当前场景对象
  Map<String, dynamic>? getCurrentScene() {
    final currentId = gameState['current_scene_id'];
    if (currentId == null && scenes.isNotEmpty) return scenes.first;
    try {
      return scenes.firstWhere((s) => s['name'] == currentId || s['id'] == currentId);
    } catch (e) {
      return scenes.isNotEmpty ? scenes.first : null;
    }
  }

  /// 获取当前场景待触发的事件
  List<Map<String, dynamic>> getCurrentSceneEvents() {
    final currentScene = getCurrentScene();
    if (currentScene == null) return [];
    
    final pendingEvents = List<Map<String, dynamic>>.from(gameState['pending_events'] ?? []);
    final sceneName = currentScene['name'];
    final sceneId = currentScene['id'];

    // 筛选出 location 匹配当前场景的事件
    // 注意：事件结构可以是 {'scene_id': 'xxx', 'dialogues': ...}
    return pendingEvents.where((e) {
      final target = e['scene_id'];
      return target == sceneName || target == sceneId;
    }).toList();
  }

  /// 移除已触发的事件
  Future<void> removeEvent(Map<String, dynamic> event) async {
    final pendingEvents = List<Map<String, dynamic>>.from(gameState['pending_events'] ?? []);
    pendingEvents.removeWhere((e) => e['scene_id'] == event['scene_id'] && jsonEncode(e['dialogues']) == jsonEncode(event['dialogues']));
    gameState['pending_events'] = pendingEvents;
    await saveGameData();
  }

  /// 进入下一天/下一周的核心逻辑
  /// [isNextWeek]: true表示下一周，false表示下一天
  /// 返回生成的总结报告文本
  Future<String> processTurnSettlement({required bool isNextWeek}) async {
    // 1. 更新时间
    if (isNextWeek) {
      gameState['week'] = (gameState['week'] ?? 1) + 1;
      gameState['day'] = 1; // 重置为周一
    } else {
      gameState['day'] = (gameState['day'] ?? 1) + 1;
      if (gameState['day'] > 7) {
        gameState['week'] = (gameState['week'] ?? 1) + 1;
        gameState['day'] = 1;
      }
    }

    // 2. 模拟AI处理过程 (此处应接入实际的LLM API)
    // 逻辑：
    // - 收集：世界背景、当前玩家状态、所有AI角色状态、最近发生的日志
    // - Prompt：根据命运AI设定，决定世界发生了什么，每个AI角色做了什么。
    // - 输出：更新后的角色状态、新生成的事件列表、本回合总结文本。
    
    await Future.delayed(const Duration(seconds: 3)); // 模拟AI思考时间

    // --- Mock 模拟生成的新内容 ---
    
    // 模拟：随机更新一个AI角色的状态
    if (aiCharacters.isNotEmpty) {
      final randomAi = (aiCharacters..shuffle()).first;
      randomAi['status'] = '状态更新于第${gameState['week']}周第${gameState['day']}天';
      randomAi['backpack'] = '${randomAi['backpack']} (AI获得了一个新物品)';
    }

    // 模拟：生成一个新的随机事件
    final currentScene = getCurrentScene();
    final newEvent = {
      'scene_id': currentScene?['name'] ?? '未命名场景',
      'dialogues': [
        {'name': '系统', 'message': '这是一个由AI在第${gameState['week']}周自动生成的随机事件。'},
        {'name': '路人', 'message': '听说最近世界上发生了一些大事...'}
      ]
    };
    
    // 更新 Pending Events
    List<dynamic> currentPending = gameState['pending_events'] ?? [];
    currentPending.add(newEvent);
    gameState['pending_events'] = currentPending;

    // 记录日志
    final summary = "第${gameState['week']}周第${gameState['day']}天结算完成。\n世界按部就班地运转着，某个AI角色似乎有了新的动向。";
    List<dynamic> logs = gameState['logs'] ?? [];
    logs.add({'time': DateTime.now().toIso8601String(), 'content': summary});
    gameState['logs'] = logs;

    // 3. 保存更新后的状态
    await saveGameData();
    
    return summary;
  }
}