// lib/ui/creation/game_world_creation/game_stage_workbench_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart'; // 用于播放音频

import '../../../base/config_service.dart';
import '../../../base/log/log_service.dart';
import '../../../models/bookshelf_entry.dart';
import '../../../services/cache_manager/cache_manager.dart';
// 引入 GameStageGeneratorService 用于统一调用生成逻辑
import '../../../services/task_executor/game_stage_generator_service.dart';

class GameStageWorkbenchPage extends StatefulWidget {
  const GameStageWorkbenchPage({super.key});

  @override
  State<GameStageWorkbenchPage> createState() => _GameStageWorkbenchPageState();
}

class _GameStageWorkbenchPageState extends State<GameStageWorkbenchPage> {
  final _configService = ConfigService();

  late TextEditingController _worldBackgroundController;
  late TextEditingController _destinyAiController;

  // 数据存储
  Map<String, dynamic> _playerCharacter = {};
  List<Map<String, dynamic>> _aiCharacters = [];
  List<Map<String, dynamic>> _gameScenes = [];
  List<Map<String, dynamic>> _firstDayEvents = [];
  
  // 自动保存定时器
  Timer? _autoSaveTimer;

  // 音频播放控制器
  VideoPlayerController? _audioController;
  String? _currentPlayingPath;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadDataFromConfig();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _worldBackgroundController.dispose();
    _destinyAiController.dispose();
    _audioController?.dispose();
    super.dispose();
  }

  // --- 数据加载与保存 ---

  void _loadDataFromConfig() {
    _worldBackgroundController = TextEditingController(
      text: _configService.getSetting('game_stage_world_background', ''),
    );
    _destinyAiController = TextEditingController(
      text: _configService.getSetting('game_stage_destiny_ai', ''),
    );

    _worldBackgroundController.addListener(_triggerDebouncedAutoSave);
    _destinyAiController.addListener(_triggerDebouncedAutoSave);

    _playerCharacter = Map<String, dynamic>.from(
      _configService.getSetting('game_stage_player_character', {}),
    );
    
    final aiList = _configService.getSetting<List>('game_stage_ai_characters', []);
    _aiCharacters = aiList.map((e) => Map<String, dynamic>.from(e)).toList();

    final sceneList = _configService.getSetting<List>('game_stage_game_scenes', []);
    _gameScenes = sceneList.map((e) => Map<String, dynamic>.from(e)).toList();

    final eventsList = _configService.getSetting<List>('game_stage_first_day_events', []);
    _firstDayEvents = eventsList.map((e) {
      final map = Map<String, dynamic>.from(e);
      // 深度拷贝 dialogues 列表，防止引用问题
      if (map['dialogues'] is List) {
        map['dialogues'] = List<Map<String, dynamic>>.from(
          (map['dialogues'] as List).map((d) => Map<String, dynamic>.from(d))
        );
      } else {
        map['dialogues'] = <Map<String, dynamic>>[];
      }
      return map;
    }).toList();

    setState(() {});
  }

  void _triggerDebouncedAutoSave() {
    if (_autoSaveTimer?.isActive ?? false) _autoSaveTimer!.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 1000), () {
      _performSave(silent: true);
    });
  }

  void _triggerImmediateSave() {
    if (_autoSaveTimer?.isActive ?? false) _autoSaveTimer!.cancel();
    _performSave(silent: true);
  }

  Future<void> _performSave({bool silent = true}) async {
    try {
      await _configService.modifySetting('game_stage_world_background', _worldBackgroundController.text);
      await _configService.modifySetting('game_stage_destiny_ai', _destinyAiController.text);
      await _configService.modifySetting('game_stage_player_character', _playerCharacter);
      await _configService.modifySetting('game_stage_ai_characters', _aiCharacters);
      await _configService.modifySetting('game_stage_game_scenes', _gameScenes);
      await _configService.modifySetting('game_stage_first_day_events', _firstDayEvents);
      
      LogService.instance.info("游戏舞台数据已自动保存");
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存成功'), duration: Duration(milliseconds: 800)));
      }
    } catch (e) {
      LogService.instance.error("游戏舞台自动保存失败", e);
    }
  }

  // --- 导出为游戏书 (核心修改部分) ---

  Future<void> _saveAsGameBook() async {
    final titleController = TextEditingController();
    
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存为游戏书'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('将当前设定的世界、角色和场景打包生成一本可游玩的游戏书。'),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '游戏书标题',
                hintText: '例如：艾瑞多冒险记',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (titleController.text.trim().isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (shouldSave != true) return;

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在打包资源生成游戏书...')));
      }

      final bookId = const Uuid().v4();
      final bookTitle = titleController.text.trim();
      
      final appDir = await getApplicationSupportDirectory();
      final booksDir = Directory(p.join(appDir.path, 'BookProjectsCache')); 
      if (!await booksDir.exists()) await booksDir.create(recursive: true);

      final bookFolder = Directory(p.join(booksDir.path, bookId));
      if (!await bookFolder.exists()) await bookFolder.create(recursive: true);

      // 1. 创建资源目录 assets
      final assetsFolder = Directory(p.join(bookFolder.path, 'assets'));
      if (!await assetsFolder.exists()) await assetsFolder.create(recursive: true);

      final initialWorldStateFolder = Directory(p.join(bookFolder.path, 'initial_world_state'));
      if (!await initialWorldStateFolder.exists()) {
        await initialWorldStateFolder.create(recursive: true);
      }

      // --- 辅助函数：复制资源文件并返回新路径 ---
      Future<String?> copyAsset(String? sourcePath, String prefix) async {
        if (sourcePath == null || sourcePath.isEmpty) return null;
        final sourceFile = File(sourcePath);
        if (!await sourceFile.exists()) return null;

        try {
          final extension = p.extension(sourcePath);
          final newFileName = '${prefix}_${const Uuid().v4()}$extension';
          final newPath = p.join(assetsFolder.path, newFileName);
          await sourceFile.copy(newPath);
          return newPath; // 返回新位置的绝对路径
        } catch (e) {
          LogService.instance.error('资源复制失败: $sourcePath', e);
          return null; // 复制失败则字段置空或保留原值(视需求定，这里置空防止死链)
        }
      }

      // --- 准备数据：深度拷贝并处理媒体路径 ---

      // 2. 处理 AI 角色 (复制立绘)
      // 使用 jsonDecode/Encode 做一次简单的深度拷贝，避免修改了 Workbench 的原始数据
      final List<Map<String, dynamic>> exportAiCharacters = 
          List<Map<String, dynamic>>.from(jsonDecode(jsonEncode(_aiCharacters)));

      for (var char in exportAiCharacters) {
        if (char['imagePath'] != null) {
          // 复制图片到 assets 目录，并更新 export 数据中的路径
          char['imagePath'] = await copyAsset(char['imagePath'], 'char_img_${char['id'] ?? 'unknown'}');
        }
      }

      // 3. 处理 场景 (复制图片和音乐)
      final List<Map<String, dynamic>> exportScenes = 
          List<Map<String, dynamic>>.from(jsonDecode(jsonEncode(_gameScenes)));

      for (var scene in exportScenes) {
        if (scene['imagePath'] != null) {
          scene['imagePath'] = await copyAsset(scene['imagePath'], 'scene_img_${scene['id'] ?? 'unknown'}');
        }
        if (scene['musicPath'] != null) {
          scene['musicPath'] = await copyAsset(scene['musicPath'], 'scene_bgm_${scene['id'] ?? 'unknown'}');
        }
      }

      // 4. 处理 待触发事件 (初始化)
      final List<Map<String, dynamic>> pendingEvents = [];
      for (var evt in _firstDayEvents) {
        final newEvt = Map<String, dynamic>.from(evt);
        if (newEvt['id'] == null) {
          newEvt['id'] = 'init_${const Uuid().v4()}';
        }
        newEvt['status'] = 'pending'; 
        pendingEvents.add(newEvt);
      }

      // 5. 组装文件内容
      final Map<String, String> filesContent = {};

      filesContent['config_world.json'] = jsonEncode({
        'world_background': _worldBackgroundController.text,
        'destiny_ai': _destinyAiController.text,
        'total_days': 1, 
      });

      // 使用处理过路径的 export 数据
      filesContent['data_player.json'] = jsonEncode(_playerCharacter);
      filesContent['data_ai_characters.json'] = jsonEncode(exportAiCharacters); 
      filesContent['data_scenes.json'] = jsonEncode(exportScenes);

      filesContent['today_event.json'] = jsonEncode({
        'date': DateTime.now().toIso8601String(),
        'game_time_ref': 'W1D1',
        'events': pendingEvents,
      });

      filesContent['event_logbook.json'] = jsonEncode({
        'history_events': [],
        'logs': [],
      });

      // 6. 写入文件
      for (var entry in filesContent.entries) {
        await File(p.join(bookFolder.path, entry.key)).writeAsString(entry.value);
        await File(p.join(initialWorldStateFolder.path, entry.key)).writeAsString(entry.value);
      }

      // 7. 更新书架
      final entry = BookshelfEntry(
        id: bookId,
        title: bookTitle,
        originalPath: 'Generated from Workbench',
        fileType: 'gameBook',
        subCachePath: bookFolder.path,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final currentEntries = await CacheManager().loadBookshelf();
      currentEntries.insert(0, entry);
      await CacheManager().saveBookshelf(currentEntries);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('游戏书创建成功！资源已打包。')));
      }

    } catch (e, s) {
      LogService.instance.error('创建游戏书失败', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e')));
      }
    }
  }

  // --- 资源生成逻辑 (图片/音乐) ---
  
  Future<void> _regenerateCharacterImage(int index) async {
    final char = _aiCharacters[index];
    // 获取当前保存的 Prompt，如果没有则为空字符串
    final prompt = char['imagePrompt'] as String? ?? '';

    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在生成角色立绘，请稍候...')));
      
      // 调用 Service 的公共方法
      final path = await GameStageGeneratorService.instance.regenerateCharacterImage(
        characterData: char,
        prompt: prompt,
      );

      if (path != null) {
        setState(() {
          _aiCharacters[index]['imagePath'] = path;
        });
        _triggerImmediateSave();
        if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    } catch (e) {
      LogService.instance.error('角色立绘生成失败', e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败: $e')));
    }
  }

  Future<void> _regenerateSceneImage(int index) async {
    final scene = _gameScenes[index];
    final prompt = scene['imagePrompt'] as String? ?? '';

    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在生成场景插图，请稍候...')));
      
      final path = await GameStageGeneratorService.instance.regenerateSceneImage(
        sceneData: scene,
        prompt: prompt,
      );

      if (path != null) {
        setState(() {
          _gameScenes[index]['imagePath'] = path;
        });
        _triggerImmediateSave();
        if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    } catch (e) {
      LogService.instance.error('场景图生成失败', e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败: $e')));
    }
  }

  Future<void> _regenerateSceneMusic(int index) async {
    final scene = _gameScenes[index];
    final prompt = scene['musicPrompt'] as String? ?? '';

    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在生成背景音乐，请稍候...')));
      
      final path = await GameStageGeneratorService.instance.regenerateSceneMusic(
        sceneData: scene,
        prompt: prompt,
      );

      if (path != null) {
        setState(() {
          _gameScenes[index]['musicPath'] = path;
        });
        _triggerImmediateSave();
        if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    } catch (e) {
      LogService.instance.error('场景音乐生成失败', e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败: $e')));
    }
  }

  // --- 新增：提示词编辑对话框 ---

  void _editPrompt({
    required String title,
    required String initialPrompt,
    required Function(String) onSave,
  }) {
    final controller = TextEditingController(text: initialPrompt);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '提示：此处为英文提示词(Prompts)。修改后请点击“重新生成”按钮生效。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 5,
              minLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter prompts here (e.g., Anime style, 1girl, white hair...)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              onSave(controller.text);
              Navigator.pop(context);
            },
            child: const Text('保存提示词'),
          ),
        ],
      ),
    );
  }

  // --- 音频播放逻辑 ---

  Future<void> _playAudio(String path) async {
    // 如果点击的是正在播放的音频
    if (_currentPlayingPath == path && _audioController != null) {
      if (_audioController!.value.isPlaying) {
        await _audioController!.pause();
        setState(() => _isPlaying = false);
      } else {
        await _audioController!.play();
        setState(() => _isPlaying = true);
      }
      return;
    }

    // 停止并释放之前的控制器
    if (_audioController != null) {
      await _audioController!.dispose();
      _audioController = null;
    }

    final file = File(path);
    if (!await file.exists()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('音频文件不存在')));
      return;
    }

    try {
      _audioController = VideoPlayerController.file(file);
      await _audioController!.initialize();
      
      // 监听播放完成
      _audioController!.addListener(() {
        if (_audioController!.value.isCompleted) {
          setState(() {
            _isPlaying = false;
          });
        }
      });

      await _audioController!.play();
      
      setState(() {
        _currentPlayingPath = path;
        _isPlaying = true;
      });
    } catch (e) {
      LogService.instance.error('播放音频失败', e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法播放此音频文件')));
    }
  }

  // --- 数据字段定义 ---
  
  final Map<String, String> _playerFields = {
    'name': '名字',
    'identity': '身份',
    'appearance': '外貌',
    'status': '状态',
    'equipment': '装备',
    'backpack': '背包',
  };
   final Map<String, String> _aiCharFields = {
    'cardName': '卡片名称 (用于显示)',
    'name': '名字',
    'identity': '身份',
    'appearance': '外貌',
    'personality': '性格',
    'motivation': '动机',
    'status': '状态',
    'equipment': '装备',
    'backpack': '背包',
    'other': '其他',
  };

  final Map<String, String> _sceneFields = {
    'name': '场景名称',
    'description': '场景说明',
    'subsidiaryScenes': '附属场景',
    'status': '场景状态',
  };

  // --- 增删改查 UI 逻辑 ---

  void _editPlayerCharacter() {
    _showEditDialog(
      title: '编辑玩家角色',
      fields: _playerFields,
      initialData: _playerCharacter,
      onSave: (newData) {
        setState(() {
          _playerCharacter = newData;
        });
        _triggerImmediateSave();
      },
    );
  }

  void _addAiCharacter() {
    Map<String, dynamic> initial = {'id': const Uuid().v4()};
    _showEditDialog(
      title: '添加 AI 角色',
      fields: _aiCharFields,
      initialData: initial,
      onSave: (newData) {
        setState(() {
          _aiCharacters.add(newData);
        });
        _triggerImmediateSave();
      },
    );
  }

  void _editAiCharacter(int index) {
    _showEditDialog(
      title: '编辑 AI 角色',
      fields: _aiCharFields,
      initialData: _aiCharacters[index],
      onSave: (newData) {
        setState(() {
          _aiCharacters[index] = newData;
        });
        _triggerImmediateSave();
      },
    );
  }

  void _deleteAiCharacter(int index) {
    setState(() {
      _aiCharacters.removeAt(index);
    });
    _triggerImmediateSave();
  }

  void _addGameScene() {
    Map<String, dynamic> initial = {'id': const Uuid().v4()};
    _showEditDialog(
      title: '添加游戏场景',
      fields: _sceneFields,
      initialData: initial,
      onSave: (newData) {
        setState(() {
          _gameScenes.add(newData);
        });
        _triggerImmediateSave();
      },
    );
  }

  void _editGameScene(int index) {
    _showEditDialog(
      title: '编辑游戏场景',
      fields: _sceneFields,
      initialData: _gameScenes[index],
      onSave: (newData) {
        setState(() {
          _gameScenes[index] = newData;
        });
        _triggerImmediateSave();
      },
    );
  }

  void _deleteGameScene(int index) {
    setState(() {
      _gameScenes.removeAt(index);
    });
    _triggerImmediateSave();
  }

  Future<void> _showEditDialog({
    required String title,
    required Map<String, String> fields,
    required Map<String, dynamic> initialData,
    required Function(Map<String, dynamic>) onSave,
  }) async {
    final controllers = <String, TextEditingController>{};
    fields.forEach((key, _) {
      controllers[key] = TextEditingController(text: initialData[key]?.toString() ?? '');
    });

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: fields.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: TextField(
                  controller: controllers[entry.key],
                  decoration: InputDecoration(
                    labelText: entry.value,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: ['appearance', 'description', 'other', 'motivation', 'equipment', 'backpack'].contains(entry.key) ? 3 : 1,
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final Map<String, dynamic> newData = Map.from(initialData);
              controllers.forEach((key, controller) {
                newData[key] = controller.text;
              });
              onSave(newData);
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // --- 事件管理 UI 逻辑 ---

  void _addEventStep() {
    setState(() {
      _firstDayEvents.add({
        'scene_id': '新场景',
        'dialogues': <Map<String, dynamic>>[]
      });
    });
    _triggerImmediateSave();
  }
  
  void _deleteEventStep(int index) {
    setState(() {
      _firstDayEvents.removeAt(index);
    });
    _triggerImmediateSave();
  }

  void _editEventSceneId(int stepIndex) {
    final controller = TextEditingController(text: _firstDayEvents[stepIndex]['scene_id'] ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置发生场景'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '场景名称/ID', hintText: '例如：钢之心城'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              setState(() {
                _firstDayEvents[stepIndex]['scene_id'] = controller.text;
              });
              _triggerImmediateSave();
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _addEventDialogue(int stepIndex) {
    _showDialogueEditDialog(
      title: '添加对话',
      initialName: '',
      initialMessage: '',
      onSave: (name, message) {
        setState(() {
          (_firstDayEvents[stepIndex]['dialogues'] as List).add({'name': name, 'message': message});
        });
        _triggerImmediateSave();
      },
    );
  }

  void _editEventDialogue(int stepIndex, int dialogueIndex) {
    final dialogues = _firstDayEvents[stepIndex]['dialogues'] as List;
    _showDialogueEditDialog(
      title: '编辑对话',
      initialName: dialogues[dialogueIndex]['name'] ?? '',
      initialMessage: dialogues[dialogueIndex]['message'] ?? '',
      onSave: (name, message) {
        setState(() {
          dialogues[dialogueIndex] = {'name': name, 'message': message};
        });
        _triggerImmediateSave();
      },
    );
  }

  void _deleteEventDialogue(int stepIndex, int dialogueIndex) {
    setState(() {
      (_firstDayEvents[stepIndex]['dialogues'] as List).removeAt(dialogueIndex);
    });
    _triggerImmediateSave();
  }

  Future<void> _showDialogueEditDialog({
    required String title,
    required String initialName,
    required String initialMessage,
    required Function(String, String) onSave,
  }) async {
    final nameController = TextEditingController(text: initialName);
    final messageController = TextEditingController(text: initialMessage);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '角色名', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              decoration: const InputDecoration(labelText: '对话内容', border: OutlineInputBorder()),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              onSave(nameController.text, messageController.text);
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // --- 页面构建 ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('游戏舞台'),
        actions: [
          IconButton(
            onPressed: _saveAsGameBook,
            icon: const Icon(Icons.save_as_outlined),
            tooltip: '保存为游戏书',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          _buildEditableSection(
            context,
            icon: Icons.language,
            title: '世界背景',
            controller: _worldBackgroundController,
          ),
          const SizedBox(height: 16),
          _buildEditableSection(
            context,
            icon: Icons.alt_route,
            title: '故事发展',
            controller: _destinyAiController,
          ),
          const SizedBox(height: 16),
          _buildPlayerCharacterSection(context),
          const SizedBox(height: 16),
          _buildAiCharactersSection(context),
          const SizedBox(height: 16),
          _buildGameScenesSection(context),
          const SizedBox(height: 16),
          _buildFirstDayEventsSection(context),
        ],
      ),
    );
  }

  Widget _buildEditableSection(BuildContext context, {required IconData icon, required String title, required TextEditingController controller}) {
      final theme = Theme.of(context);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            TextField(
              controller: controller,
              maxLines: null,
              minLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '请输入内容...',
                filled: true,
              ),
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerCharacterSection(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.person, color: theme.colorScheme.primary, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      '玩家角色',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton.filledTonal(
                  onPressed: _editPlayerCharacter,
                  icon: const Icon(Icons.edit),
                  tooltip: '编辑玩家角色',
                ),
              ],
            ),
            const Divider(height: 24),
            _buildDetailRow(context, '名字', _playerCharacter['name'] ?? ''),
            _buildDetailRow(context, '身份', _playerCharacter['identity'] ?? ''),
            _buildDetailRow(context, '外貌', _playerCharacter['appearance'] ?? ''),
            _buildDetailRow(context, '状态', _playerCharacter['status'] ?? ''),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('背包与装备', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  _buildDetailRow(context, '装备', _playerCharacter['equipment'] ?? ''),
                  _buildDetailRow(context, '背包', _playerCharacter['backpack'] ?? ''),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiCharactersSection(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.people, color: theme.colorScheme.primary, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'AI角色',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton.filledTonal(
                  onPressed: _addAiCharacter,
                  icon: const Icon(Icons.add),
                  tooltip: '添加AI角色',
                ),
              ],
            ),
            const Divider(height: 24),
            ...(_aiCharacters.asMap().entries.map((entry) {
                return _buildAiCharacterCard(context, entry.value, entry.key);
            }).toList().isNotEmpty 
            ? _aiCharacters.asMap().entries.map((entry) => _buildAiCharacterCard(context, entry.value, entry.key)).toList() 
            : [const Center(child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('暂无AI角色，请添加'),
            ))]),
          ],
        ),
      ),
    );
  }

  Widget _buildAiCharacterCard(BuildContext context, Map<String, dynamic> char, int index) {
    final theme = Theme.of(context);
    final imagePath = char['imagePath'] as String?;
    // 读取当前提示词，若无则为空字符串
    final imagePrompt = char['imagePrompt'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.dividerColor.withOpacity(0.5), width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        shape: const Border(),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          backgroundImage: (imagePath != null && File(imagePath).existsSync()) 
              ? FileImage(File(imagePath)) 
              : null,
          child: (imagePath == null || !File(imagePath).existsSync()) 
              ? Icon(Icons.smart_toy_outlined, color: theme.colorScheme.primary) 
              : null,
        ),
        title: Text(
          char['cardName']?.isNotEmpty == true ? char['cardName'] : (char['name'] ?? '未命名角色'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${char['name'] ?? ''} | ${char['identity'] ?? ''}',
          maxLines: 1, 
          overflow: TextOverflow.ellipsis
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                // 角色立绘展示
                if (imagePath != null && File(imagePath).existsSync())
                   Container(
                     height: 200,
                     width: double.infinity,
                     margin: const EdgeInsets.only(bottom: 16),
                     decoration: BoxDecoration(
                       borderRadius: BorderRadius.circular(8),
                       image: DecorationImage(
                         image: FileImage(File(imagePath)),
                         fit: BoxFit.contain, // 立绘完整展示
                       ),
                       color: Colors.black12,
                     ),
                   ),
                
                Row(
                  children: [
                     Expanded(child: _buildDetailRow(context, '外貌', char['appearance'] ?? '')),
                     // 提示词编辑按钮
                     IconButton(
                       icon: const Icon(Icons.text_fields, size: 18),
                       tooltip: '查看/编辑绘图提示词',
                       onPressed: () => _editPrompt(
                         title: '编辑角色提示词',
                         initialPrompt: imagePrompt,
                         onSave: (newPrompt) {
                           setState(() {
                             _aiCharacters[index]['imagePrompt'] = newPrompt;
                           });
                           _triggerImmediateSave();
                         },
                       ),
                     ),
                     // 立绘生成按钮
                     IconButton.filledTonal(
                       onPressed: () => _regenerateCharacterImage(index),
                       icon: const Icon(Icons.refresh, size: 18),
                       tooltip: imagePath == null ? '生成立绘' : '重新生成立绘',
                     )
                  ],
                ),
                
                _buildDetailRow(context, '性格', char['personality'] ?? ''),
                _buildDetailRow(context, '动机', char['motivation'] ?? ''),
                _buildDetailRow(context, '状态', char['status'] ?? ''),
                _buildDetailRow(context, '其他', char['other'] ?? ''),
                const SizedBox(height: 8),
                 _buildDetailRow(context, '装备', char['equipment'] ?? ''),
                _buildDetailRow(context, '背包', char['backpack'] ?? ''),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _deleteAiCharacter(index),
                      icon: const Icon(Icons.delete_outline, size: 20),
                      label: const Text('删除'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => _editAiCharacter(index),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('编辑'),
                    ),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameScenesSection(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.map, color: theme.colorScheme.primary, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      '游戏场景',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton.filledTonal(
                  onPressed: _addGameScene,
                  icon: const Icon(Icons.add),
                  tooltip: '添加场景',
                ),
              ],
            ),
            const Divider(height: 24),
             ...(_gameScenes.asMap().entries.map((entry) {
                return _buildGameSceneCard(context, entry.value, entry.key);
            }).toList().isNotEmpty 
            ? _gameScenes.asMap().entries.map((entry) => _buildGameSceneCard(context, entry.value, entry.key)).toList() 
            : [const Center(child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('暂无场景，请添加'),
            ))]),
          ],
        ),
      ),
    );
  }

  Widget _buildGameSceneCard(BuildContext context, Map<String, dynamic> scene, int index) {
    final theme = Theme.of(context);
    final imagePath = scene['imagePath'] as String?;
    final musicPath = scene['musicPath'] as String?;
    
    final imagePrompt = scene['imagePrompt'] as String? ?? '';
    final musicPrompt = scene['musicPrompt'] as String? ?? '';
    
    // 判断当前是否在播放此场景的音乐
    final isPlayingThis = _currentPlayingPath == musicPath && _isPlaying;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.dividerColor.withOpacity(0.5), width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 场景图
            if (imagePath != null && File(imagePath).existsSync())
              Container(
                height: 150,
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: FileImage(File(imagePath)),
                    fit: BoxFit.cover,
                  ),
                ),
              ),

            Row(
              children: [
                Expanded(
                  child: Text(
                    scene['name'] ?? '未命名场景',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // 场景图提示词按钮
                IconButton(
                  onPressed: () => _editPrompt(
                    title: '编辑场景图提示词',
                    initialPrompt: imagePrompt,
                    onSave: (val) {
                      setState(() => _gameScenes[index]['imagePrompt'] = val);
                      _triggerImmediateSave();
                    },
                  ),
                  icon: const Icon(Icons.text_fields, size: 20),
                  tooltip: '查看/修改提示词',
                ),
                // 场景图生成按钮
                IconButton(
                  onPressed: () => _regenerateSceneImage(index),
                  icon: const Icon(Icons.image_outlined),
                  tooltip: imagePath == null ? '生成场景图' : '重新生成场景图',
                  style: IconButton.styleFrom(foregroundColor: theme.colorScheme.primary),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _editGameScene(index),
                  tooltip: '编辑信息',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _deleteGameScene(index),
                  tooltip: '删除场景',
                  style: IconButton.styleFrom(
                    foregroundColor: theme.colorScheme.error.withOpacity(0.7),
                  ),
                ),
              ],
            ),
            
            const Divider(),

            _buildDetailRow(context, '场景说明', scene['description'] ?? ''),
            _buildDetailRow(context, '附属场景', scene['subsidiaryScenes'] ?? ''),
            _buildDetailRow(context, '场景状态', scene['status'] ?? ''),
            
            const SizedBox(height: 8),
            // 音乐播放条
            Container(
               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
               decoration: BoxDecoration(
                 color: theme.colorScheme.surface,
                 borderRadius: BorderRadius.circular(8),
                 border: Border.all(color: theme.dividerColor.withOpacity(0.2))
               ),
               child: Row(
                 children: [
                    Icon(Icons.music_note, size: 20, color: theme.colorScheme.secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (musicPath == null || !File(musicPath).existsSync()) 
                          ? '暂无背景音乐' 
                          : '场景BGM.wav',
                        style: TextStyle(
                          color: (musicPath == null || !File(musicPath).existsSync()) 
                            ? Colors.grey 
                            : theme.colorScheme.onSurface,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (musicPath != null && File(musicPath).existsSync())
                      IconButton(
                        onPressed: () => _playAudio(musicPath),
                        icon: Icon(isPlayingThis ? Icons.pause_circle_filled : Icons.play_circle_filled),
                        color: theme.colorScheme.secondary,
                        iconSize: 28,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    const SizedBox(width: 8),
                    // 音乐提示词按钮
                    IconButton(
                      onPressed: () => _editPrompt(
                        title: '编辑音乐提示词',
                        initialPrompt: musicPrompt,
                        onSave: (val) {
                          setState(() => _gameScenes[index]['musicPrompt'] = val);
                          _triggerImmediateSave();
                        },
                      ),
                      icon: const Icon(Icons.text_fields, size: 18),
                      tooltip: '音乐提示词',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    // 音乐生成按钮
                    IconButton(
                      onPressed: () => _regenerateSceneMusic(index),
                      icon: const Icon(Icons.refresh),
                      tooltip: musicPath == null ? '生成音乐' : '重新生成音乐',
                      iconSize: 20,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                 ],
               ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFirstDayEventsSection(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.event_note, color: theme.colorScheme.primary, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      '首日事件',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                FilledButton.tonalIcon(
                  onPressed: _addEventStep,
                  icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                  label: const Text("添加新事件"),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_firstDayEvents.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('暂无事件流程，请添加新事件')))
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _firstDayEvents.length,
                itemBuilder: (context, index) {
                  return _buildEventStepCard(context, index);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventStepCard(BuildContext context, int stepIndex) {
    final theme = Theme.of(context);
    final eventData = _firstDayEvents[stepIndex];
    final sceneId = eventData['scene_id'] ?? '未命名场景';
    final dialogues = (eventData['dialogues'] as List?) ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${stepIndex + 1}',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => _editEventSceneId(stepIndex),
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      children: [
                        Icon(Icons.location_on, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            sceneId,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.edit, size: 14, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: theme.colorScheme.error,
                  tooltip: '删除此事件',
                  onPressed: () => _deleteEventStep(stepIndex),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (dialogues.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: TextButton.icon(
                  onPressed: () => _addEventDialogue(stepIndex),
                  icon: const Icon(Icons.add_comment, size: 16),
                  label: const Text('在此场景添加对话'),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: dialogues.length,
              separatorBuilder: (c, i) => Divider(height: 1, indent: 56, color: theme.dividerColor.withOpacity(0.2)),
              itemBuilder: (context, dIndex) {
                final item = dialogues[dIndex];
                return ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -2),
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                    child: Text(
                      (item['name'] ?? '?').isNotEmpty ? (item['name'] ?? '?').substring(0, 1) : '?',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(item['name'] ?? '未知', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  subtitle: Text(item['message'] ?? '', style: const TextStyle(fontSize: 13)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.edit, size: 16),
                        onPressed: () => _editEventDialogue(stepIndex, dIndex),
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => _deleteEventDialogue(stepIndex, dIndex),
                        color: theme.colorScheme.error.withOpacity(0.6),
                      ),
                    ],
                  ),
                );
              },
            ),
          if (dialogues.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withOpacity(0.5),
                border: Border(top: BorderSide(color: theme.dividerColor.withOpacity(0.2))),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12))
              ),
              child: InkWell(
                onTap: () => _addEventDialogue(stepIndex),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text("添加对话", style: TextStyle(fontSize: 12, color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 14, height: 1.4))),
        ],
      ),
    );
  }
}