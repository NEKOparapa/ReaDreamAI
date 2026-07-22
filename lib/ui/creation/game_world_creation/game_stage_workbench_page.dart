// lib/ui/creation/game_world_creation/game_stage_workbench_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../../../base/config_service.dart';
import '../../../base/log/log_service.dart';
import '../../../models/bookshelf_entry.dart';
import '../../../services/cache_manager/cache_manager.dart';
import '../../../services/task_executor/game_stage_generator_service.dart';

class GameStageWorkbenchPage extends StatefulWidget {
  const GameStageWorkbenchPage({super.key});

  @override
  State<GameStageWorkbenchPage> createState() => _GameStageWorkbenchPageState();
}

class _GameStageWorkbenchPageState extends State<GameStageWorkbenchPage> {
  final _configService = ConfigService();

  // 控制器
  late TextEditingController _bookTitleController;
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
    _bookTitleController.dispose();
    _worldBackgroundController.dispose();
    _destinyAiController.dispose();
    _audioController?.dispose();
    super.dispose();
  }

  // 辅助方法：安全地将 List 或其他类型转为 String
  String _formatListToText(dynamic value) {
    if (value == null) return '';
    if (value is List) {
      // 如果是列表，用中文逗号拼接
      return value.map((e) => e.toString()).join('，');
    }
    // 如果是其他类型（如 String），直接转字符串
    return value.toString();
  }

  // --- 数据加载与保存 ---

  void _loadDataFromConfig() {
    // 加载标题
    _bookTitleController = TextEditingController(
      text: _configService.getSetting('game_stage_book_title', '未命名世界'),
    );
    // 加载世界背景
    _worldBackgroundController = TextEditingController(
      text: _configService.getSetting('game_stage_world_background', ''),
    );
    // 加载命运AI
    _destinyAiController = TextEditingController(
      text: _configService.getSetting('game_stage_story_direction', ''),
    );

    // 绑定自动保存
    _bookTitleController.addListener(_triggerDebouncedAutoSave);
    _worldBackgroundController.addListener(_triggerDebouncedAutoSave);
    _destinyAiController.addListener(_triggerDebouncedAutoSave);

    // 加载对象数据
    _playerCharacter = Map<String, dynamic>.from(
      _configService.getSetting('game_stage_player_character', {}),
    );

    final aiList = _configService.getSetting<List>(
      'game_stage_ai_characters',
      [],
    );
    _aiCharacters = aiList.map((e) => Map<String, dynamic>.from(e)).toList();

    final sceneList = _configService.getSetting<List>(
      'game_stage_game_scenes',
      [],
    );
    _gameScenes = sceneList.map((e) => Map<String, dynamic>.from(e)).toList();

    final eventsList = _configService.getSetting<List>(
      'game_stage_first_day_events',
      [],
    );
    _firstDayEvents = eventsList.map((e) {
      final map = Map<String, dynamic>.from(e);
      if (!map.containsKey('title')) {
        map['title'] = '未命名事件';
      }
      if (map['dialogues'] is List) {
        map['dialogues'] = List<Map<String, dynamic>>.from(
          (map['dialogues'] as List).map((d) => Map<String, dynamic>.from(d)),
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
      // 保存所有字段，包括标题
      await _configService.modifySetting(
        'game_stage_book_title',
        _bookTitleController.text,
      );
      await _configService.modifySetting(
        'game_stage_world_background',
        _worldBackgroundController.text,
      );
      await _configService.modifySetting(
        'game_stage_story_direction',
        _destinyAiController.text,
      );
      await _configService.modifySetting(
        'game_stage_player_character',
        _playerCharacter,
      );
      await _configService.modifySetting(
        'game_stage_ai_characters',
        _aiCharacters,
      );
      await _configService.modifySetting('game_stage_game_scenes', _gameScenes);
      await _configService.modifySetting(
        'game_stage_first_day_events',
        _firstDayEvents,
      );

      LogService.instance.info("游戏舞台数据已自动保存");
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('保存成功'),
            duration: Duration(milliseconds: 800),
          ),
        );
      }
    } catch (e) {
      LogService.instance.error("游戏舞台自动保存失败", e);
    }
  }

  // --- 导出为游戏书 ---

  Future<void> _saveAsGameBook() async {
    // 使用当前编辑的标题作为默认值
    final titleController = TextEditingController(
      text: _bookTitleController.text,
    );

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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('正在打包资源生成游戏书...')));
      }

      final bookId = const Uuid().v4();
      final bookTitle = titleController.text.trim();

      final appDir = await getApplicationSupportDirectory();
      final booksDir = Directory(p.join(appDir.path, 'BookProjectsCache'));
      if (!await booksDir.exists()) await booksDir.create(recursive: true);

      final bookFolder = Directory(p.join(booksDir.path, bookId));
      if (!await bookFolder.exists()) await bookFolder.create(recursive: true);

      final assetsFolder = Directory(p.join(bookFolder.path, 'assets'));
      if (!await assetsFolder.exists()) {
        await assetsFolder.create(recursive: true);
      }

      final initialWorldStateFolder = Directory(
        p.join(bookFolder.path, 'initial_world_state'),
      );
      if (!await initialWorldStateFolder.exists()) {
        await initialWorldStateFolder.create(recursive: true);
      }

      // 资源复制辅助函数
      Future<String?> copyAsset(String? sourcePath, String prefix) async {
        if (sourcePath == null || sourcePath.isEmpty) return null;
        final sourceFile = File(sourcePath);
        if (!await sourceFile.exists()) return null;

        try {
          final extension = p.extension(sourcePath);
          final newFileName = '${prefix}_${const Uuid().v4()}$extension';
          final newPath = p.join(assetsFolder.path, newFileName);
          await sourceFile.copy(newPath);
          return newPath;
        } catch (e) {
          LogService.instance.error('资源复制失败: $sourcePath', e);
          return null;
        }
      }

      // 处理 AI 角色资源
      final List<Map<String, dynamic>> exportAiCharacters =
          List<Map<String, dynamic>>.from(
            jsonDecode(jsonEncode(_aiCharacters)),
          );

      for (var char in exportAiCharacters) {
        if (char['imagePath'] != null) {
          char['imagePath'] = await copyAsset(
            char['imagePath'],
            'char_img_${char['id'] ?? 'unknown'}',
          );
        }
      }

      // 处理场景资源
      final List<Map<String, dynamic>> exportScenes =
          List<Map<String, dynamic>>.from(jsonDecode(jsonEncode(_gameScenes)));

      for (var scene in exportScenes) {
        if (scene['imagePath'] != null) {
          scene['imagePath'] = await copyAsset(
            scene['imagePath'],
            'scene_img_${scene['id'] ?? 'unknown'}',
          );
        }
        if (scene['musicPath'] != null) {
          scene['musicPath'] = await copyAsset(
            scene['musicPath'],
            'scene_bgm_${scene['id'] ?? 'unknown'}',
          );
        }
      }

      // 处理初日事件状态
      final List<Map<String, dynamic>> pendingEvents = [];
      for (var evt in _firstDayEvents) {
        final newEvt = Map<String, dynamic>.from(evt);
        if (newEvt['id'] == null) {
          newEvt['id'] = 'init_${const Uuid().v4()}';
        }
        newEvt['status'] = 'pending';
        pendingEvents.add(newEvt);
      }

      // 准备 JSON 文件内容
      final Map<String, String> filesContent = {};

      filesContent['config_world.json'] = jsonEncode({
        'world_title': bookTitle,
        'world_background': _worldBackgroundController.text,
        'story_direction': _destinyAiController.text,
        'total_days': 1,
      });

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

      // 写入文件
      for (var entry in filesContent.entries) {
        await File(
          p.join(bookFolder.path, entry.key),
        ).writeAsString(entry.value);
        await File(
          p.join(initialWorldStateFolder.path, entry.key),
        ).writeAsString(entry.value);
      }

      // 创建书架条目
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('游戏书创建成功！资源已打包。')));
      }
    } catch (e, s) {
      LogService.instance.error('创建游戏书失败', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('创建失败: $e')));
      }
    }
  }

  // --- 资源生成逻辑 ---
  Future<void> _regenerateCharacterImage(int index) async {
    final char = _aiCharacters[index];
    final prompt = char['imagePrompt'] as String? ?? '';

    try {
      // 1. 获取当前激活的绘图 API 配置
      final activeApi = _configService.getActiveDrawingApi();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('正在生成角色立绘，请稍候...')));

      // 2. 传入 apiConfig
      final path = await GameStageGeneratorService.instance
          .regenerateCharacterImage(
            characterData: char,
            prompt: prompt,
            apiConfig: activeApi,
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('生成失败: $e')));
      }
    }
  }

  Future<void> _regenerateSceneImage(int index) async {
    final scene = _gameScenes[index];
    final prompt = scene['imagePrompt'] as String? ?? '';

    try {
      // 1. 获取当前激活的绘图 API 配置
      final activeApi = _configService.getActiveDrawingApi();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('正在生成场景插图，请稍候...')));

      // 2. 传入 apiConfig
      final path = await GameStageGeneratorService.instance
          .regenerateSceneImage(
            sceneData: scene,
            prompt: prompt,
            apiConfig: activeApi,
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('生成失败: $e')));
      }
    }
  }

  Future<void> _regenerateSceneMusic(int index) async {
    final scene = _gameScenes[index];
    final prompt = scene['musicPrompt'] as String? ?? '';

    try {
      // 1. 获取当前激活的音乐 API 配置
      final activeApi = _configService.getActiveMusicApi();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('正在生成背景音乐，请稍候...')));

      // 2. 传入 apiConfig
      final path = await GameStageGeneratorService.instance
          .regenerateSceneMusic(
            sceneData: scene,
            prompt: prompt,
            apiConfig: activeApi,
          );

      if (path != null) {
        setState(() {
          _gameScenes[index]['musicPath'] = path;
          _gameScenes[index].remove('lyrics');
        });
        _triggerImmediateSave();
        if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    } catch (e) {
      LogService.instance.error('场景音乐生成失败', e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('生成失败: $e')));
      }
    }
  }

  // --- 提示词编辑对话框 ---

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
                hintText:
                    'Enter prompts here (e.g., Anime style, 1girl, white hair...)',
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

  // --- 新增方法：编辑场景纯音乐提示词 ---
  void _editMusicPrompt({
    required String initialPrompt,
    required Function(String) onSave,
  }) {
    final promptController = TextEditingController(text: initialPrompt);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑场景纯音乐提示词'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '音乐提示词',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: promptController,
                maxLines: 3,
                minLines: 2,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText:
                      '例如: Melancholic piano, ambient forest soundtrack, instrumental only, no vocals, no lyrics',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              onSave(promptController.text);
              Navigator.pop(context);
            },
            child: const Text('保存设定'),
          ),
        ],
      ),
    );
  }

  // --- 音频播放逻辑 ---

  Future<void> _playAudio(String path) async {
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

    if (_audioController != null) {
      await _audioController!.dispose();
      _audioController = null;
    }

    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('音频文件不存在')));
      }
      return;
    }

    try {
      _audioController = VideoPlayerController.file(file);
      await _audioController!.initialize();

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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法播放此音频文件')));
      }
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
      controllers[key] = TextEditingController(
        text: initialData[key]?.toString() ?? '',
      );
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
                  maxLines:
                      [
                        'appearance',
                        'description',
                        'other',
                        'motivation',
                        'equipment',
                        'backpack',
                      ].contains(entry.key)
                      ? 3
                      : 1,
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
        'title': '新事件',
        'scene_id': '', // 初始为空
        'dialogues': <Map<String, dynamic>>[],
      });
    });
    _triggerImmediateSave();
  }

  void _editEventTitle(int stepIndex) {
    final currentTitle = _firstDayEvents[stepIndex]['title'] as String? ?? '';
    final controller = TextEditingController(text: currentTitle);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑事件标题'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '标题',
            hintText: '例如：苏醒、初次遭遇',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                _firstDayEvents[stepIndex]['title'] = controller.text;
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

  void _deleteEventStep(int index) {
    setState(() {
      _firstDayEvents.removeAt(index);
    });
    _triggerImmediateSave();
  }

  // 场景选择弹窗
  void _editEventSceneId(int stepIndex) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                '选择发生场景',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            if (_gameScenes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('暂无可用场景，请先在上方“游戏场景”区域添加。'),
              ),
            ..._gameScenes.map((scene) {
              final isSelected =
                  _firstDayEvents[stepIndex]['scene_id'] == scene['id'];
              return ListTile(
                leading: const Icon(Icons.map_outlined),
                title: Text(scene['name'] ?? '未命名场景'),
                subtitle: Text(
                  scene['description'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: isSelected,
                trailing: isSelected
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
                onTap: () {
                  setState(() {
                    // 保存ID
                    _firstDayEvents[stepIndex]['scene_id'] = scene['id'];
                  });
                  _triggerImmediateSave();
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  void _addEventDialogue(int stepIndex) {
    _showDialogueEditDialog(
      title: '添加对话',
      initialName: '',
      initialMessage: '',
      onSave: (name, message) {
        setState(() {
          (_firstDayEvents[stepIndex]['dialogues'] as List).add({
            'name': name,
            'message': message,
          });
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
              decoration: const InputDecoration(
                labelText: '角色名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              decoration: const InputDecoration(
                labelText: '对话内容',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
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
          TextButton.icon(
            onPressed: _saveAsGameBook,
            icon: const Icon(Icons.library_add_outlined),
            label: const Text('保存为游戏书'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 80),
        children: [
          _buildTitleSection(context),
          const SizedBox(height: 24),
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

  // 改进后的标题卡片组件
  Widget _buildTitleSection(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Container(
        // 限制最大宽度，防止在大屏上太宽
        constraints: const BoxConstraints(maxWidth: 600),
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          // 使用极淡的边框和阴影，保持干净
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. 顶部小标签
            Text(
              'WORLD NAME',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.secondary.withValues(alpha: 0.6),
                letterSpacing: 3.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // 2. 标题输入框
            TextField(
              controller: _bookTitleController,
              textAlign: TextAlign.center, // 居中对齐
              maxLines: null,
              minLines: 1,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600, // 半粗体
                color: theme.colorScheme.onSurface,
                height: 1.3,
              ),
              decoration: InputDecoration(
                hintText: '输入世界名称',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none, // 去除下划线
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),

            const SizedBox(height: 24),

            // 3. 底部极简装饰线
            Container(
              width: 24,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required TextEditingController controller,
  }) {
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
                    Icon(
                      Icons.person,
                      color: theme.colorScheme.primary,
                      size: 28,
                    ),
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
            _buildDetailRow(
              context,
              '外貌',
              _playerCharacter['appearance'] ?? '',
            ),
            _buildDetailRow(context, '状态', _playerCharacter['status'] ?? ''),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('背包与装备', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  // 修改点：使用 _formatListToText 处理装备和背包，防止 List 导致崩溃
                  _buildDetailRow(
                    context,
                    '装备',
                    _formatListToText(_playerCharacter['equipment']),
                  ),
                  _buildDetailRow(
                    context,
                    '背包',
                    _formatListToText(_playerCharacter['backpack']),
                  ),
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
                    Icon(
                      Icons.people,
                      color: theme.colorScheme.primary,
                      size: 28,
                    ),
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
            ...(_aiCharacters
                    .asMap()
                    .entries
                    .map((entry) {
                      return _buildAiCharacterCard(
                        context,
                        entry.value,
                        entry.key,
                      );
                    })
                    .toList()
                    .isNotEmpty
                ? _aiCharacters
                      .asMap()
                      .entries
                      .map(
                        (entry) => _buildAiCharacterCard(
                          context,
                          entry.value,
                          entry.key,
                        ),
                      )
                      .toList()
                : [
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('暂无AI角色，请添加'),
                      ),
                    ),
                  ]),
          ],
        ),
      ),
    );
  }

  Widget _buildImageAreaWithActions(
    BuildContext context, {
    required String? imagePath,
    required bool
    isContainMode, // true for character (contain), false for scene (cover)
    required VoidCallback onEditPrompt,
    required VoidCallback onRegenerate,
    String? regenerateTooltip,
  }) {
    final theme = Theme.of(context);
    final hasImage = imagePath != null && File(imagePath).existsSync();

    return Stack(
      children: [
        Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: hasImage
                ? Colors.black12
                : theme.colorScheme.surfaceContainerHighest,
            image: hasImage
                ? DecorationImage(
                    image: FileImage(File(imagePath)),
                    fit: isContainMode ? BoxFit.contain : BoxFit.cover,
                  )
                : null,
          ),
          child: !hasImage
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.image_not_supported_outlined,
                        size: 40,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "暂无图片",
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
        ),
        // 右上角操作按钮区
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.text_fields,
                    size: 18,
                    color: Colors.white,
                  ),
                  tooltip: '查看/编辑绘图提示词',
                  visualDensity: VisualDensity.compact,
                  onPressed: onEditPrompt,
                ),
                Container(width: 1, height: 16, color: Colors.white24),
                IconButton(
                  icon: const Icon(
                    Icons.refresh,
                    size: 18,
                    color: Colors.white,
                  ),
                  tooltip: regenerateTooltip ?? (hasImage ? '重新生成' : '生成图片'),
                  visualDensity: VisualDensity.compact,
                  onPressed: onRegenerate,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAiCharacterCard(
    BuildContext context,
    Map<String, dynamic> char,
    int index,
  ) {
    final theme = Theme.of(context);
    final imagePath = char['imagePath'] as String?;
    final imagePrompt = char['imagePrompt'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5), width: 1),
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
          char['cardName']?.isNotEmpty == true
              ? char['cardName']
              : (char['name'] ?? '未命名角色'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${char['name'] ?? ''} | ${char['identity'] ?? ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                // 角色立绘展示区域（右上角带按钮）
                _buildImageAreaWithActions(
                  context,
                  imagePath: imagePath,
                  isContainMode: true,
                  onEditPrompt: () => _editPrompt(
                    title: '编辑角色提示词',
                    initialPrompt: imagePrompt,
                    onSave: (newPrompt) {
                      setState(() {
                        _aiCharacters[index]['imagePrompt'] = newPrompt;
                      });
                      _triggerImmediateSave();
                    },
                  ),
                  onRegenerate: () => _regenerateCharacterImage(index),
                  regenerateTooltip: imagePath == null ? '生成立绘' : '重新生成立绘',
                ),

                const SizedBox(height: 12),
                _buildDetailRow(context, '外貌', char['appearance'] ?? ''),
                _buildDetailRow(context, '性格', char['personality'] ?? ''),
                _buildDetailRow(context, '动机', char['motivation'] ?? ''),
                _buildDetailRow(context, '状态', char['status'] ?? ''),
                _buildDetailRow(context, '其他', char['other'] ?? ''),
                const SizedBox(height: 8),
                // 修改点：使用 _formatListToText 处理装备和背包
                _buildDetailRow(
                  context,
                  '装备',
                  _formatListToText(char['equipment']),
                ),
                _buildDetailRow(
                  context,
                  '背包',
                  _formatListToText(char['backpack']),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _deleteAiCharacter(index),
                      icon: const Icon(Icons.delete_outline, size: 20),
                      label: const Text('删除'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => _editAiCharacter(index),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('编辑'),
                    ),
                  ],
                ),
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
            ...(_gameScenes
                    .asMap()
                    .entries
                    .map((entry) {
                      return _buildGameSceneCard(
                        context,
                        entry.value,
                        entry.key,
                      );
                    })
                    .toList()
                    .isNotEmpty
                ? _gameScenes
                      .asMap()
                      .entries
                      .map(
                        (entry) => _buildGameSceneCard(
                          context,
                          entry.value,
                          entry.key,
                        ),
                      )
                      .toList()
                : [
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('暂无场景，请添加'),
                      ),
                    ),
                  ]),
          ],
        ),
      ),
    );
  }

  Widget _buildGameSceneCard(
    BuildContext context,
    Map<String, dynamic> scene,
    int index,
  ) {
    final theme = Theme.of(context);
    final imagePath = scene['imagePath'] as String?;
    final musicPath = scene['musicPath'] as String?;

    final imagePrompt = scene['imagePrompt'] as String? ?? '';
    final musicPrompt = scene['musicPrompt'] as String? ?? '';

    // 判断当前是否在播放此场景的音乐
    final isPlayingThis = _currentPlayingPath == musicPath && _isPlaying;
    final hasMusic = musicPath != null && File(musicPath).existsSync();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5), width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：场景名称（左） + 编辑/删除按钮（右）
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
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _editGameScene(index),
                  tooltip: '编辑场景信息',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _deleteGameScene(index),
                  tooltip: '删除场景',
                  style: IconButton.styleFrom(
                    foregroundColor: theme.colorScheme.error.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 第二行：场景图片（带悬浮按钮）
            _buildImageAreaWithActions(
              context,
              imagePath: imagePath,
              isContainMode: false,
              onEditPrompt: () => _editPrompt(
                title: '编辑场景图提示词',
                initialPrompt: imagePrompt,
                onSave: (val) {
                  setState(() => _gameScenes[index]['imagePrompt'] = val);
                  _triggerImmediateSave();
                },
              ),
              onRegenerate: () => _regenerateSceneImage(index),
              regenerateTooltip: imagePath == null ? '生成场景图' : '重新生成场景图',
            ),

            const SizedBox(height: 12),
            const Divider(),

            _buildDetailRow(context, '场景说明', scene['description'] ?? ''),
            _buildDetailRow(
              context,
              '附属场景',
              _formatListToText(scene['subsidiaryScenes']),
            ),
            _buildDetailRow(context, '场景状态', scene['status'] ?? ''),

            const SizedBox(height: 8),
            // --- 音乐播放条 (更新后) ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.music_note,
                    size: 20,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),

                  // 音乐信息 (占用剩余空间，将后续按钮推向右侧)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          !hasMusic ? '暂无背景音乐' : 'Scene_BGM.wav',
                          style: TextStyle(
                            color: !hasMusic
                                ? Colors.grey
                                : theme.colorScheme.onSurface,
                            fontSize: 13,
                            fontWeight: hasMusic
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 1. 播放按钮
                  if (hasMusic)
                    IconButton(
                      onPressed: () => _playAudio(musicPath),
                      icon: Icon(
                        isPlayingThis
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                      ),
                      color: theme.colorScheme.secondary,
                      iconSize: 28,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: isPlayingThis ? '暂停' : '播放',
                    ),
                  const SizedBox(width: 8),

                  // 2. 编辑纯音乐提示词按钮
                  IconButton(
                    onPressed: () => _editMusicPrompt(
                      initialPrompt: musicPrompt,
                      onSave: (newPrompt) {
                        setState(() {
                          _gameScenes[index]['musicPrompt'] = newPrompt;
                          _gameScenes[index].remove('lyrics');
                        });
                        _triggerImmediateSave();
                      },
                    ),
                    icon: const Icon(Icons.text_fields, size: 18),
                    tooltip: '音乐提示词',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),

                  // 3. 生成/重成按钮
                  IconButton(
                    onPressed: () => _regenerateSceneMusic(index),
                    icon: const Icon(Icons.refresh),
                    tooltip: !hasMusic ? '生成音乐' : '重新生成音乐',
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),

                  // 4. 删除按钮 (放在最右边)
                  if (hasMusic) ...[
                    const SizedBox(width: 12), // 与前面的按钮稍微拉开一点距离
                    IconButton(
                      onPressed: () async {
                        // 如果正在播放这首音乐，先停止
                        if (isPlayingThis) {
                          await _audioController?.pause();
                          setState(() {
                            _isPlaying = false;
                            _currentPlayingPath = null;
                          });
                        }
                        setState(() {
                          _gameScenes[index]['musicPath'] = null;
                        });
                        _triggerImmediateSave();
                      },
                      icon: const Icon(Icons.close, size: 18),
                      color: theme.colorScheme.error.withValues(alpha: 0.6),
                      iconSize: 20,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: '删除音乐',
                    ),
                  ],
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
                    Icon(
                      Icons.event_note,
                      color: theme.colorScheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '首日事件',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton.filledTonal(
                  onPressed: _addEventStep,
                  icon: const Icon(Icons.add),
                  tooltip: '添加新事件',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_firstDayEvents.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('暂无事件流程，请添加新事件'),
                ),
              )
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

    final title = eventData['title'] as String? ?? '未命名事件';
    final sceneId = eventData['scene_id'] as String? ?? '';
    final dialogues = (eventData['dialogues'] as List?) ?? [];

    // --- 查找场景名称逻辑 ---
    String sceneDisplayName = '点击选择场景...';
    bool isSceneValid = false;

    if (sceneId.isNotEmpty) {
      final sceneObj = _gameScenes.firstWhere(
        (s) => s['id'] == sceneId,
        orElse: () => {},
      );
      if (sceneObj.isNotEmpty) {
        sceneDisplayName = sceneObj['name'] ?? '未命名场景';
        isSceneValid = true;
      } else {
        final sceneObjByName = _gameScenes.firstWhere(
          (s) => s['name'] == sceneId,
          orElse: () => {},
        );
        if (sceneObjByName.isNotEmpty) {
          sceneDisplayName = sceneObjByName['name'];
          isSceneValid = true;
        } else {
          sceneDisplayName = '$sceneId (场景已失效)';
        }
      }
    }

    // --- 拖拽排序回调 ---
    void onReorder(int oldIndex, int newIndex) {
      setState(() {
        if (oldIndex < newIndex) {
          newIndex -= 1;
        }
        final item = dialogues.removeAt(oldIndex);
        dialogues.insert(newIndex, item);
      });
      _triggerImmediateSave();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === 1. 顶部标题栏 ===
          InkWell(
            onTap: () => _editEventTitle(stepIndex),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${stepIndex + 1}',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title.isEmpty ? '点击设置标题' : title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: title.isEmpty
                            ? Colors.grey
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: theme.colorScheme.error.withValues(alpha: 0.7),
                    tooltip: '删除此事件',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _deleteEventStep(stepIndex),
                  ),
                ],
              ),
            ),
          ),

          const Divider(height: 1, indent: 52),

          // === 2. 场景位置栏 ===
          InkWell(
            onTap: () => _editEventSceneId(stepIndex),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.3),
              child: Row(
                children: [
                  const SizedBox(width: 38),
                  Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: isSceneValid
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '发生地点:',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      sceneDisplayName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isSceneValid
                            ? theme.colorScheme.primary
                            : (sceneId.isEmpty
                                  ? theme.colorScheme.outline
                                  : theme.colorScheme.error),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),

          const Divider(height: 1),

          // === 3. 对话列表 (支持拖拽) ===
          if (dialogues.isEmpty)
            InkWell(
              onTap: () => _addEventDialogue(stepIndex),
              child: Container(
                height: 60,
                width: double.infinity,
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_comment_outlined,
                      size: 18,
                      color: theme.colorScheme.primary.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '添加对话内容',
                      style: TextStyle(
                        color: theme.colorScheme.primary.withValues(alpha: 0.8),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false, // 关闭默认句柄，使用自定义句柄
              onReorder: onReorder,
              // 拖拽时的样式装饰（让卡片浮起来，去掉透明底带来的视觉干扰）
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (BuildContext context, Widget? child) {
                    return Material(
                      elevation: 4,
                      color: theme.colorScheme.surfaceContainer, // 拖拽时的高亮背景
                      borderRadius: BorderRadius.circular(8),
                      child: child,
                    );
                  },
                  child: child,
                );
              },
              children: [
                for (int i = 0; i < dialogues.length; i++)
                  _buildDraggableDialogueItem(
                    context,
                    item: dialogues[i],
                    index: i,
                    stepIndex: stepIndex,
                    theme: theme,
                  ),
              ],
            ),

          // === 4. 底部添加按钮 ===
          if (dialogues.isNotEmpty)
            InkWell(
              onTap: () => _addEventDialogue(stepIndex),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.5),
                  border: Border(
                    top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                  ),
                ),
                child: Icon(
                  Icons.add,
                  size: 20,
                  color: theme.colorScheme.primary.withValues(alpha: 0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 抽离出来的单个对话项 Widget
  Widget _buildDraggableDialogueItem(
    BuildContext context, {
    required Map<String, dynamic> item,
    required int index,
    required int stepIndex,
    required ThemeData theme,
  }) {
    final charName = item['name'] ?? '未知';

    // 使用 ObjectKey 确保每个 map 对应唯一的 widget key，避免拖拽时的状态丢失
    return Container(
      key: ObjectKey(item),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
      ),
      child: Material(
        // 使用 Material 包裹以支持 InkWell 水波纹
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _editEventDialogue(stepIndex, index), // 点击整行编辑
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 8.0,
              horizontal: 16.0,
            ),
            child: Row(
              children: [
                // 1. 头像
                CircleAvatar(
                  radius: 14,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Text(
                    charName.isNotEmpty ? charName.substring(0, 1) : '?',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // 2. 文本内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        charName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item['message'] ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // 3. 右侧操作区 (拖拽 + 删除)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () => _deleteEventDialogue(stepIndex, index),
                      color: theme.colorScheme.outline.withValues(alpha: 0.5),
                      tooltip: '删除',
                    ),
                    // 拖拽句柄 (ReorderableDragStartListener)
                    ReorderableDragStartListener(
                      index: index,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.transparent, // 扩大触摸区域
                        child: Icon(
                          Icons.drag_indicator,
                          size: 20,
                          color: theme.colorScheme.outline.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
