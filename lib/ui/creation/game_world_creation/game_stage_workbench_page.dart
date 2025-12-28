// lib/ui/creation/game_world_creation/game_stage_workbench_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../base/config_service.dart';
import '../../../base/log/log_service.dart';
import '../../../models/bookshelf_entry.dart';
import '../../../services/cache_manager/cache_manager.dart';

class GameStageWorkbenchPage extends StatefulWidget {
  const GameStageWorkbenchPage({super.key});

  @override
  State<GameStageWorkbenchPage> createState() => _GameStageWorkbenchPageState();
}

class _GameStageWorkbenchPageState extends State<GameStageWorkbenchPage> {
  // ... (省略变量声明和 initState/dispose，保持不变)
  final _configService = ConfigService();

  late TextEditingController _worldBackgroundController;
  late TextEditingController _destinyAiController;

  Map<String, dynamic> _playerCharacter = {};
  List<Map<String, dynamic>> _aiCharacters = [];
  List<Map<String, dynamic>> _gameScenes = [];
  List<Map<String, dynamic>> _firstDayEvents = [];
  Timer? _autoSaveTimer;

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
    super.dispose();
  }

  // ... (省略 _loadDataFromConfig 和 自动保存逻辑，保持不变)
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

  // --- 保存为游戏书功能 ---

  Future<void> _saveAsGameBook() async {
    final titleController = TextEditingController();
    
    // 1. 弹出对话框获取书籍标题
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
      // 2. 准备基础数据
      final bookId = const Uuid().v4();
      final bookTitle = titleController.text.trim();
      
      // 3. 获取缓存目录并创建书籍专属文件夹
      final appDir = await getApplicationSupportDirectory();
      final booksDir = Directory(p.join(appDir.path, 'BookProjectsCache')); 
      if (!await booksDir.exists()) await booksDir.create(recursive: true);

      final bookFolder = Directory(p.join(booksDir.path, bookId));
      if (!await bookFolder.exists()) await bookFolder.create(recursive: true);

      // 创建“初始世界状态”文件夹
      final initialWorldStateFolder = Directory(p.join(bookFolder.path, 'initial_world_state'));
      if (!await initialWorldStateFolder.exists()) {
        await initialWorldStateFolder.create(recursive: true);
      }

      // 4. 处理待触发事件
      final List<Map<String, dynamic>> pendingEvents = [];
      for (var evt in _firstDayEvents) {
        final newEvt = Map<String, dynamic>.from(evt);
        if (newEvt['id'] == null) {
          newEvt['id'] = 'init_${const Uuid().v4()}';
        }
        newEvt['status'] = 'pending'; 
        pendingEvents.add(newEvt);
      }

      // 5. 准备要写入的文件内容
      final Map<String, String> filesContent = {};

      filesContent['config_world.json'] = jsonEncode({
        'world_background': _worldBackgroundController.text,
        'destiny_ai': _destinyAiController.text,
        'total_days': 1, 
        // [删除] current_scene_id
      });

      filesContent['data_player.json'] = jsonEncode(_playerCharacter);
      filesContent['data_ai_characters.json'] = jsonEncode(_aiCharacters);
      filesContent['data_scenes.json'] = jsonEncode(_gameScenes);

      filesContent['today_event.json'] = jsonEncode({
        'date': DateTime.now().toIso8601String(),
        'game_time_ref': 'W1D1',
        'events': pendingEvents,
      });

      filesContent['event_logbook.json'] = jsonEncode({
        'history_events': [],
        'logs': [],
      });

      // 6. 执行写入操作
      for (var entry in filesContent.entries) {
        await File(p.join(bookFolder.path, entry.key)).writeAsString(entry.value);
        await File(p.join(initialWorldStateFolder.path, entry.key)).writeAsString(entry.value);
      }

      // 7. 创建书架条目
      final entry = BookshelfEntry(
        id: bookId,
        title: bookTitle,
        originalPath: 'Generated from Workbench',
        fileType: 'gameBook',
        subCachePath: bookFolder.path,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // 8. 更新书架缓存
      final currentEntries = await CacheManager().loadBookshelf();
      currentEntries.insert(0, entry);
      await CacheManager().saveBookshelf(currentEntries);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('游戏书创建成功！请前往书架查看。')));
      }

    } catch (e, s) {
      LogService.instance.error('创建游戏书失败', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e')));
      }
    }
  }
  
  // ... (省略编辑和 UI 构建代码，这些不需要修改) ...
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('游戏舞台工作台'),
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
            title: '命运AI',
            controller: _destinyAiController,
          ),
          const SizedBox(height: 16),
          _buildFirstDayEventsSection(context),
          const SizedBox(height: 16),
          _buildPlayerCharacterSection(context),
          const SizedBox(height: 16),
          _buildAiCharactersSection(context),
          const SizedBox(height: 16),
          _buildGameScenesSection(context),
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
                      '第一天事件',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                FilledButton.tonalIcon(
                  onPressed: _addEventStep,
                  icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                  label: const Text("添加场景流"),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_firstDayEvents.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('暂无事件流程，请添加场景流')))
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
                  tooltip: '删除此场景流',
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
        leading: Icon(Icons.smart_toy_outlined, color: theme.colorScheme.primary),
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
                _buildDetailRow(context, '外貌', char['appearance'] ?? ''),
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
                  tooltip: '编辑',
                  style: IconButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _deleteGameScene(index),
                  tooltip: '删除',
                  style: IconButton.styleFrom(
                    foregroundColor: theme.colorScheme.error.withOpacity(0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildDetailRow(context, '场景说明', scene['description'] ?? ''),
            _buildDetailRow(context, '附属场景', scene['subsidiaryScenes'] ?? ''),
            _buildDetailRow(context, '场景状态', scene['status'] ?? ''),
          ],
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
          Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 14, height: 1.4))),
        ],
      ),
    );
  }
}