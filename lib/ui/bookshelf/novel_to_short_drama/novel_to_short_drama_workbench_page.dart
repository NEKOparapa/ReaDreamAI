// lib/ui/bookshelf/novel_to_short_drama/novel_to_short_drama_workbench_page.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as p;

import '../../../base/config_service.dart';
import '../../../models/book.dart';
import '../../../models/character_card_model.dart';
import '../../../services/task_executor/storyboard_generator_executor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

// Shot 模型定义
class Shot {
  int shotNumber;
  TextEditingController shotTypeController;
  TextEditingController cameraMoveController;
  TextEditingController charactersController;
  TextEditingController contentController;
  TextEditingController soundController;
  TextEditingController durationController;
  TextEditingController firstFramePromptController = TextEditingController();
  TextEditingController mainCharacterController = TextEditingController();
  List<String> firstFrameImagePaths = [];
  TextEditingController videoPromptController = TextEditingController();
  List<String> videoPaths = [];

  Shot({
    required this.shotNumber,
    String shotType = '全景',
    String cameraMove = '固定',
    String characters = '',
    String content = '',
    String sound = '',
    String duration = '3s',
  })  : shotTypeController = TextEditingController(text: shotType),
        cameraMoveController = TextEditingController(text: cameraMove),
        charactersController = TextEditingController(text: characters),
        contentController = TextEditingController(text: content),
        soundController = TextEditingController(text: sound),
        durationController = TextEditingController(text: duration);

  void dispose() {
    shotTypeController.dispose();
    cameraMoveController.dispose();
    charactersController.dispose();
    contentController.dispose();
    soundController.dispose();
    durationController.dispose();
    firstFramePromptController.dispose();
    mainCharacterController.dispose();
    videoPromptController.dispose();
  }

  Map<String, dynamic> toJson() => {
        'shotNumber': shotNumber,
        'shotType': shotTypeController.text,
        'cameraMove': cameraMoveController.text,
        'characters': charactersController.text,
        'content': contentController.text,
        'sound': soundController.text,
        'duration': durationController.text,
        'firstFramePrompt': firstFramePromptController.text,
        'mainCharacter': mainCharacterController.text,
        'firstFrameImagePaths': firstFrameImagePaths,
        'videoPrompt': videoPromptController.text,
        'videoPaths': videoPaths,
      };

  factory Shot.fromJson(Map<String, dynamic> json) {
    String parseField(dynamic fieldValue) {
      if (fieldValue == null) return '';
      if (fieldValue is List) return fieldValue.join(', ');
      return fieldValue.toString();
    }

    final shot = Shot(
      shotNumber: json['shotNumber'] as int? ?? 1,
      shotType: parseField(json['shotType']),
      cameraMove: parseField(json['cameraMove']),
      characters: parseField(json['characters']),
      content: parseField(json['content']),
      sound: parseField(json['sound']),
      duration: parseField(json['duration']),
    );

    shot.firstFramePromptController.text =
        json['firstFramePrompt'] as String? ?? '';
    shot.mainCharacterController.text = json['mainCharacter'] as String? ?? '';
    shot.firstFrameImagePaths =
        List<String>.from(json['firstFrameImagePaths'] ?? []);
    shot.videoPromptController.text = json['videoPrompt'] as String? ?? '';
    shot.videoPaths = List<String>.from(json['videoPaths'] ?? []);
    return shot;
  }
}

class Scene {
  TextEditingController titleController = TextEditingController(text: '场景');
  List<Shot> shots;

  Scene({List<Shot>? shots}) : shots = shots ?? [Shot(shotNumber: 1)];

  void dispose() {
    titleController.dispose();
    for (final shot in shots) {
      shot.dispose();
    }
  }

  Map<String, dynamic> toJson() => {
        'title': titleController.text,
        'shots': shots.map((s) => s.toJson()).toList(),
      };

  factory Scene.fromJson(Map<String, dynamic> json) {
    final shotsList = json['shots'] as List<dynamic>? ?? [];
    final scene = Scene(
      shots: shotsList
          .map((s) => Shot.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
    scene.titleController.text = json['title'] as String? ?? '场景';
    return scene;
  }
}

class ChapterScript {
  final String originalChapterTitle;
  List<Scene> scenes;

  ChapterScript({required this.originalChapterTitle, List<Scene>? scenes})
      : scenes = scenes ?? [Scene()];

  void dispose() {
    for (final scene in scenes) {
      scene.dispose();
    }
  }

  Map<String, dynamic> toJson() => {
        'originalChapterTitle': originalChapterTitle,
        'scenes': scenes.map((s) => s.toJson()).toList(),
      };

  factory ChapterScript.fromJson(Map<String, dynamic> json) {
    final scenesList = json['scenes'] as List<dynamic>? ?? [];
    return ChapterScript(
      originalChapterTitle: json['originalChapterTitle'] as String? ?? '未知章节',
      scenes: scenesList
          .map((s) => Scene.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}

class NovelToShortDramaWorkbenchPage extends StatefulWidget {
  final Book book;
  final List<ChapterScript> initialScript;
  final List<CharacterCard> initialCharacters;
  final bool isFromGeneration;

  const NovelToShortDramaWorkbenchPage({
    super.key,
    required this.book,
    this.initialScript = const [],
    this.initialCharacters = const [],
    this.isFromGeneration = false,
  });

  @override
  State<NovelToShortDramaWorkbenchPage> createState() =>
      _NovelToShortDramaWorkbenchPageState();
}

class _NovelToShortDramaWorkbenchPageState
    extends State<NovelToShortDramaWorkbenchPage> {
  late List<ChapterScript> _script;
  late List<Map<String, dynamic>> _charactersData;

  bool _isLoading = true;
  final _configService = ConfigService();
  Timer? _debounce;

  bool _isGenerating = false;
  String _generationStatus = '';
  double _generationProgress = 0.0;

  final Set<String> _generatingTasks = {};

  @override
  void initState() {
    super.initState();
    _loadWorkbenchData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _saveWorkbenchData(showSnackbar: false);
    for (final chapter in _script) {
      chapter.dispose();
    }
    super.dispose();
  }

  void _debounceSaveWorkbenchData() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      _saveWorkbenchData(showSnackbar: false);
    });
  }

  Future<void> _loadWorkbenchData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (widget.isFromGeneration) {
        _script = widget.initialScript;
        _charactersData =
            widget.initialCharacters.map((c) => c.toJson()).toList();
        await _saveWorkbenchData(showSnackbar: false);
      } else {
        final savedBookId = _configService.getSetting<String?>(
            'workbench_last_active_book_id', null);
        if (savedBookId == widget.book.id) {
          _charactersData = List<Map<String, dynamic>>.from(
              _configService.getSetting('workbench_active_characters', []));
          final savedScriptJson = List<Map<String, dynamic>>.from(
              _configService.getSetting('workbench_active_script', []));
          if (savedScriptJson.isNotEmpty) {
            _script = savedScriptJson
                .map((json) => ChapterScript.fromJson(json))
                .toList();
          } else {
            _initializeDefaultScript();
          }
        } else {
          _initializeDefaultScript();
          _charactersData = List<Map<String, dynamic>>.from(
              _configService.getSetting('workbench_active_characters', []));
        }
      }
    } catch (e) {
      debugPrint('[工作台] 加载数据失败: $e');
      _initializeDefaultScript();
      _charactersData = [];
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _initializeDefaultScript() {
    final defaultScriptJson = List<Map<String, dynamic>>.from(
        _configService.getSetting('workbench_active_script', []));

    if (defaultScriptJson.isNotEmpty && widget.book.chapters.isNotEmpty) {
      _script = widget.book.chapters.map((chapter) {
        final templateChapter = defaultScriptJson.first;
        return ChapterScript.fromJson({
          ...templateChapter,
          'originalChapterTitle': chapter.title,
        });
      }).toList();
    } else {
      _script = [
        ChapterScript(
            originalChapterTitle: widget.book.chapters.isNotEmpty
                ? widget.book.chapters.first.title
                : "默认章节")
      ];
    }
  }

  Future<void> _saveWorkbenchData(
      {bool showSnackbar = true, String message = '工作台已保存'}) async {
    _debounce?.cancel();
    try {
      await _configService.modifySetting(
          'workbench_active_characters', _charactersData);
      final scriptJson = _script.map((cs) => cs.toJson()).toList();
      await _configService.modifySetting('workbench_active_script', scriptJson);
      await _configService.modifySetting(
          'workbench_last_active_book_id', widget.book.id);
      if (mounted && showSnackbar) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(message), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      debugPrint('[工作台] 保存数据失败: $e');
      if (mounted && showSnackbar) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败'), duration: Duration(seconds: 2)),
        );
      }
    }
  }

  Future<void> _generateAllPrompts() async {
    setState(() {
      _isGenerating = true;
      _generationStatus = '准备中...';
      _generationProgress = 0.0;
    });

    try {
      final characters =
          _charactersData.map((data) => CharacterCard.fromJson(data)).toList();

      await StoryboardGeneratorExecutor.instance.generateAllPromptsForScript(
        novelTitle: widget.book.title,
        characters: characters,
        script: _script,
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _generationProgress = progress;
              _generationStatus = status;
            });
          }
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 提示词生成完毕!')),
        );
      }
    } catch (e, s) {
      debugPrint('[提示词生成] 失败: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 提示词生成失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _generateAllMedia() async {
    setState(() {
      _isGenerating = true;
      _generationStatus = '准备中...';
      _generationProgress = 0.0;
    });

    try {
      final characters =
          _charactersData.map((data) => CharacterCard.fromJson(data)).toList();

      await StoryboardGeneratorExecutor.instance.generateAllMediaForScript(
        book: widget.book,
        script: _script,
        characters: characters,
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _generationProgress = progress;
              _generationStatus = status;
            });
          }
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 媒体生成完毕!')),
        );
      }
    } catch (e, s) {
      debugPrint('[媒体生成] 失败: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 媒体生成失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<bool> _showDeleteConfirmationDialog(
      {required String title, required String content}) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(title),
              content: Text(content),
              actions: <Widget>[
                TextButton(
                  child: const Text('取消'),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error),
                  child: const Text('删除'),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  void _deleteCharacter(int index) async {
    final confirmed = await _showDeleteConfirmationDialog(
        title: '确认删除角色',
        content: '确定要删除角色"${_charactersData[index]['name']}"吗?此操作无法撤销。');
    if (confirmed) {
      setState(() {
        _charactersData.removeAt(index);
      });
      _debounceSaveWorkbenchData();
    }
  }

  void _deleteScene(ChapterScript chapter, Scene scene) async {
    final confirmed = await _showDeleteConfirmationDialog(
        title: '确认删除场景', content: '确定要删除这个场景及其包含的所有分镜吗?此操作无法撤销。');
    if (confirmed) {
      setState(() {
        chapter.scenes.remove(scene);
      });
      _debounceSaveWorkbenchData();
    }
  }

  void _deleteShot(Scene scene, Shot shot) async {
    final confirmed = await _showDeleteConfirmationDialog(
        title: '确认删除分镜', content: '确定要删除这个分镜吗?此操作无法撤销。');
    if (confirmed) {
      setState(() {
        scene.shots.remove(shot);
        _updateShotNumbers(scene);
      });
      _debounceSaveWorkbenchData();
    }
  }

  void _updateShotNumbers(Scene scene) {
    for (int i = 0; i < scene.shots.length; i++) {
      scene.shots[i].shotNumber = i + 1;
    }
  }

  Future<void> _generateFirstFramePromptForShot(Shot shot, Scene scene) async {
    final taskKey = '${shot.hashCode}_prompt';
    if (_generatingTasks.contains(taskKey)) return;

    setState(() => _generatingTasks.add(taskKey));
    try {
      final chapter = _script.firstWhere((c) => c.scenes.contains(scene));
      final characters =
          _charactersData.map((data) => CharacterCard.fromJson(data)).toList();

      final result = await StoryboardGeneratorExecutor.instance
          .generatePromptsForSingleShot(
        novelTitle: widget.book.title,
        characters: characters,
        chapterTitle: chapter.originalChapterTitle,
        sceneTitle: scene.titleController.text,
        shot: shot,
      );

      setState(() {
        shot.firstFramePromptController.text = result.imagePrompt;
        shot.videoPromptController.text = result.videoPrompt;
        shot.mainCharacterController.text = result.mainCharacter;
      });
      _debounceSaveWorkbenchData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ 提示词已生成'), duration: Duration(seconds: 2)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('❌ 提示词生成失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _generatingTasks.remove(taskKey));
      }
    }
  }

  Future<void> _generateImageForShot(Shot shot) async {
    final taskKey = '${shot.hashCode}_image';
    if (_generatingTasks.contains(taskKey)) return;

    setState(() => _generatingTasks.add(taskKey));
    try {
      final characters =
          _charactersData.map((data) => CharacterCard.fromJson(data)).toList();
      final newImagePath =
          await StoryboardGeneratorExecutor.instance.generateImageForShot(
        shot: shot,
        characters: characters,
      );

      for (final oldPath in shot.firstFrameImagePaths) {
        final oldFile = File(oldPath);
        if (await oldFile.exists()) await oldFile.delete();
      }

      setState(() {
        shot.firstFrameImagePaths.clear();
        shot.firstFrameImagePaths.add(newImagePath);
      });
      _debounceSaveWorkbenchData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('❌ 图片生成失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _generatingTasks.remove(taskKey));
      }
    }
  }

  Future<void> _generateVideoForShot(Shot shot) async {
    final taskKey = '${shot.hashCode}_video';
    if (_generatingTasks.contains(taskKey)) return;

    setState(() => _generatingTasks.add(taskKey));
    try {
      final newVideoPath = await StoryboardGeneratorExecutor.instance
          .generateVideoForShot(shot: shot);

      for (final oldPath in shot.videoPaths) {
        final oldFile = File(oldPath);
        if (await oldFile.exists()) await oldFile.delete();
      }

      setState(() {
        shot.videoPaths.clear();
        shot.videoPaths.add(newVideoPath);
      });
      _debounceSaveWorkbenchData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('❌ 视频生成失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _generatingTasks.remove(taskKey));
      }
    }
  }

  Future<void> _deleteMediaItem(Shot shot, String path, String mediaType) async {
    final confirmed = await _showDeleteConfirmationDialog(
      title: '确认删除',
      content:
          '确定要删除这个${mediaType == 'image' ? '图片' : '视频'}吗?此操作会从磁盘删除文件。',
    );

    if (!confirmed) return;

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      setState(() {
        if (mediaType == 'image') {
          shot.firstFrameImagePaths.remove(path);
        } else {
          shot.videoPaths.remove(path);
        }
      });
      _debounceSaveWorkbenchData();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('✅ 已删除')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('❌ 删除失败: $e')));
      }
    }
  }

  void _showEnlargedMediaDialog({
    required BuildContext context,
    required Shot shot,
    required String path,
    required String mediaType,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (context) {
        return _MediaViewerDialog(
          mediaPath: path,
          mediaType: mediaType,
          onDelete: () {
            Navigator.of(context).pop();
            _deleteMediaItem(shot, path, mediaType);
          },
          onRegenerate: () {
            Navigator.of(context).pop();
            if (mediaType == 'image') {
              _generateImageForShot(shot);
            } else {
              _generateVideoForShot(shot);
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('短剧工作台 - 《${widget.book.title}》'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: '保存工作台',
            onPressed: _isGenerating
                ? null
                : () => _saveWorkbenchData(showSnackbar: true),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // 主要内容
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20.0, vertical: 16.0),
                  child: ListView(
                    children: [
                      _buildNovelInfoSection(),
                      if (_isGenerating) _buildTaskProgressPanel(),
                      const SizedBox(height: 24),
                      _buildSectionHeader('主要角色', Icons.people_outline),
                      _buildCharactersSection(),
                      const SizedBox(height: 24),
                      _buildSectionHeader('分镜脚本', Icons.movie_filter_outlined),
                      _buildScriptSection(),
                      const SizedBox(height: 100), // 底部留白,避免被悬浮按钮遮挡
                    ],
                  ),
                ),
                // [新增] 右下角悬浮按钮
                _buildFloatingActionButtons(),
              ],
            ),
    );
  }

  /// [新增] 右下角悬浮生成按钮
  Widget _buildFloatingActionButtons() {
    return Positioned(
      right: 24,
      bottom: 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 生成提示词按钮
          FloatingActionButton.extended(
            onPressed: _isGenerating ? null : _generateAllPrompts,
            heroTag: 'generate_prompts',
            backgroundColor: _isGenerating
                ? Theme.of(context).colorScheme.surfaceVariant
                : Theme.of(context).colorScheme.primaryContainer,
            icon: Icon(
              Icons.auto_awesome,
              color: _isGenerating
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            label: Text(
              '生成提示词',
              style: TextStyle(
                color: _isGenerating
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 生成图片和视频按钮
          FloatingActionButton.extended(
            onPressed: _isGenerating ? null : _generateAllMedia,
            heroTag: 'generate_media',
            backgroundColor: _isGenerating
                ? Theme.of(context).colorScheme.surfaceVariant
                : Theme.of(context).colorScheme.secondaryContainer,
            icon: Icon(
              Icons.movie_creation_outlined,
              color: _isGenerating
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.onSecondaryContainer,
            ),
            label: Text(
              '生成图片和视频',
              style: TextStyle(
                color: _isGenerating
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 8),
          Text(title,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildNovelInfoSection() {
    final theme = Theme.of(context);
    final int chapterCount = _script.length;
    final int sceneCount =
        _script.fold(0, (sum, chapter) => sum + chapter.scenes.length);
    final int shotCount = _script.fold(
        0,
        (sum, chapter) =>
            sum + chapter.scenes.fold(0, (s, scene) => s + scene.shots.length));

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前项目',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.book.title,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            _buildStatItem('章节', chapterCount),
            _buildStatItem('场景', sceneCount),
            _buildStatItem('分镜', shotCount, isLast: true),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int count, {bool isLast = false}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(right: BorderSide(color: theme.dividerColor)),
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count.toString(),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildTaskProgressPanel() {
    return Card(
      margin: const EdgeInsets.only(top: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5)),
                const SizedBox(width: 12),
                Text('正在执行任务...',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            if (_generationStatus.isNotEmpty)
              Text(_generationStatus,
                  style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _generationProgress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCharactersSection() {
    return _charactersData.isNotEmpty
        ? ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _charactersData.length,
            itemBuilder: (context, index) {
              return _EditableCharacterCardItem(
                characterData: _charactersData[index],
                onDataChanged: _debounceSaveWorkbenchData,
                onDelete: () => _deleteCharacter(index),
              );
            },
          )
        : const Center(
            child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('没有角色信息'),
          ));
  }

  Widget _buildScriptSection() {
    return _script.isEmpty
        ? const Center(
            child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('没有可用的分镜脚本'),
          ))
        : ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _script.length,
            itemBuilder: (context, chapterIndex) {
              return _buildChapterItem(_script[chapterIndex], chapterIndex);
            },
          );
  }

  Widget _buildChapterItem(ChapterScript chapter, int chapterIndex) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        backgroundColor: theme.colorScheme.surface.withAlpha(100),
        collapsedBackgroundColor: theme.cardColor,
        shape: const RoundedRectangleBorder(),
        collapsedShape: const RoundedRectangleBorder(),
        title: Container(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'CH ${chapterIndex + 1}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  chapter.originalChapterTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
        initiallyExpanded: chapterIndex == 0,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 16),
          ...chapter.scenes.asMap().entries.map((entry) {
            int sceneNumber = entry.key + 1;
            Scene scene = entry.value;
            return _buildSceneItem(chapter, scene, chapterIndex, sceneNumber);
          }).toList()
        ],
      ),
    );
  }

  Widget _buildSceneItem(
      ChapterScript chapter, Scene scene, int chapterIndex, int sceneNumber) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(
                    width: 5,
                    color: theme.colorScheme.primary.withOpacity(0.8),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'SC ${chapterIndex + 1}-$sceneNumber',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const VerticalDivider(width: 16),
                  Expanded(
                    child: _buildEditableField(
                      scene.titleController,
                      isTitle: true,
                      hint: '场景标题 (例: 日/外景 森林边缘)',
                      onChanged: _debounceSaveWorkbenchData,
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteScene(chapter, scene),
                    tooltip: '删除场景',
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: scene.shots.isEmpty
                ? const Center(
                    child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text("该场景下无分镜")))
                : Column(
                    children: scene.shots
                        .map((shot) => _buildShotItem(scene, shot))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField(TextEditingController controller,
      {bool isTitle = false, String? hint, VoidCallback? onChanged}) {
    return TextFormField(
      controller: controller,
      onChanged: (value) => onChanged?.call(),
      decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400)),
      style: TextStyle(
        fontWeight: isTitle ? FontWeight.bold : FontWeight.normal,
        fontSize: isTitle ? 16 : 14,
      ),
    );
  }

  Widget _buildShotItem(Scene scene, Shot shot) {
    final theme = Theme.of(context);
    final isGeneratingPrompt =
        _generatingTasks.contains('${shot.hashCode}_prompt');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
        color: theme.scaffoldBackgroundColor,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
            child: Row(
              children: [
                Text(
                  'SHOT ${shot.shotNumber}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.grey.shade600),
                  onPressed: () => _deleteShot(scene, shot),
                  tooltip: '删除分镜',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  splashRadius: 20,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildEditablePairRow(
                  label1: '景别',
                  controller1: shot.shotTypeController,
                  label2: '运镜',
                  controller2: shot.cameraMoveController,
                  onChanged: _debounceSaveWorkbenchData,
                ),
                const SizedBox(height: 12),
                _buildEditablePairRow(
                  label1: '登场角色',
                  controller1: shot.charactersController,
                  label2: '分镜时长',
                  controller2: shot.durationController,
                  onChanged: _debounceSaveWorkbenchData,
                ),
                const SizedBox(height: 12),
                _buildEditableSingleRow('画面内容', shot.contentController,
                    minLines: 2, onChanged: _debounceSaveWorkbenchData),
                const SizedBox(height: 12),
                _buildEditableSingleRow('声音/对白', shot.soundController,
                    minLines: 2, onChanged: _debounceSaveWorkbenchData),
                const Divider(thickness: 1, height: 24),
                Row(
                  children: [
                    Text('AI 生成',
                        style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: isGeneratingPrompt
                          ? null
                          : () => _generateFirstFramePromptForShot(shot, scene),
                      icon: isGeneratingPrompt
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome, size: 16),
                      label: Text(isGeneratingPrompt ? '生成中...' : '生成提示词'),
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildAiGenerationRow(
                  shot: shot,
                  promptController: shot.firstFramePromptController,
                  mainCharacterController: shot.mainCharacterController,
                  charactersData: _charactersData,
                  promptLabel: '首帧图像提示词',
                  mediaPaths: shot.firstFrameImagePaths,
                  mediaType: 'image',
                ),
                const SizedBox(height: 16),
                _buildAiGenerationRow(
                  shot: shot,
                  promptController: shot.videoPromptController,
                  mainCharacterController: shot.mainCharacterController,
                  charactersData: _charactersData,
                  promptLabel: '短视频提示词',
                  mediaPaths: shot.videoPaths,
                  mediaType: 'video',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// [MODIFIED] 改进的AI生成行布局 - 精简角色信息卡片
  Widget _buildAiGenerationRow({
    required Shot shot,
    required TextEditingController promptController,
    required TextEditingController mainCharacterController,
    required List<Map<String, dynamic>> charactersData,
    required String promptLabel,
    required List<String> mediaPaths,
    required String mediaType,
  }) {
    final isImageRow = mediaType == 'image';
    final isGeneratingMedia =
        _generatingTasks.contains('${shot.hashCode}_$mediaType');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧:媒体预览
        SizedBox(
          width: 150,
          height: 150,
          child: mediaPaths.isEmpty
              ? _buildPlaceholder(
                  mediaType: mediaType,
                  onGenerate: () {
                    if (mediaType == 'image') {
                      _generateImageForShot(shot);
                    } else {
                      _generateVideoForShot(shot);
                    }
                  },
                  isGenerating: isGeneratingMedia,
                )
              : _buildMediaGallery(shot, mediaPaths, mediaType),
        ),
        const SizedBox(width: 12),
        // 中间:提示词输入框
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: promptController,
            onChanged: (value) => _debounceSaveWorkbenchData(),
            decoration: InputDecoration(
                labelText: promptLabel,
                border: const OutlineInputBorder(),
                isDense: true,
                alignLabelWithHint: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: '复制提示词',
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: promptController.text));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('已复制到剪贴板'),
                        duration: Duration(seconds: 1)));
                  },
                )),
            minLines: 6,
            maxLines: 6,
          ),
        ),
        // 右侧:角色信息卡片(仅图片行显示,且更紧凑)
        if (isImageRow) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: 120, // [修改] 固定更小的宽度
            child: _buildCompactCharacterInfoCard(
              mainCharacterController: mainCharacterController,
              charactersData: charactersData,
            ),
          ),
        ],
      ],
    );
  }

  /// [新增] 紧凑版角色信息卡片
  Widget _buildCompactCharacterInfoCard({
    required TextEditingController mainCharacterController,
    required List<Map<String, dynamic>> charactersData,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: mainCharacterController,
      builder: (context, value, child) {
        if (value.text.isEmpty) {
          return _buildEmptyCompactCharacterCard();
        }

        final characterName = value.text;
        final character = charactersData.firstWhere(
          (c) => c['characterName'] == characterName,
          orElse: () => <String, dynamic>{},
        );

        if (character.isEmpty) {
          return _buildEmptyCompactCharacterCard();
        }

        return _buildFilledCompactCharacterCard(character);
      },
    );
  }

  /// [新增] 空的紧凑角色卡片
  Widget _buildEmptyCompactCharacterCard() {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Container(
        height: 150,
        padding: const EdgeInsets.all(8.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_outline,
                size: 32,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 6),
              Text(
                '无主体角色',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [新增] 已填充的紧凑角色卡片
  Widget _buildFilledCompactCharacterCard(Map<String, dynamic> character) {
    final theme = Theme.of(context);
    final characterName = character['characterName']?.toString() ?? '';
    final imagePath = character['referenceImagePath'] as String?;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.3)),
      ),
      child: Container(
        height: 150,
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 角色头像
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: imagePath != null && imagePath.isNotEmpty
                    ? Image.file(
                        File(imagePath),
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: theme.colorScheme.primaryContainer,
                            child: Center(
                              child: Text(
                                characterName.isNotEmpty
                                    ? characterName.substring(0, 1)
                                    : '?',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : Container(
                        color: theme.colorScheme.primaryContainer,
                        child: Center(
                          child: Text(
                            characterName.isNotEmpty
                                ? characterName.substring(0, 1)
                                : '?',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            // 角色名
            Text(
              characterName,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder({
    required String mediaType,
    required VoidCallback onGenerate,
    required bool isGenerating,
  }) {
    final isImage = mediaType == 'image';
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: Colors.grey.shade300, width: 1.5, style: BorderStyle.solid),
      ),
      child: Center(
        child: isGenerating
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                      isImage
                          ? Icons.image_outlined
                          : Icons.video_library_outlined,
                      size: 32,
                      color: Colors.grey[600]),
                  const SizedBox(height: 8),
                  Text(isImage ? '无图片' : '无视频',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: onGenerate,
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    label: const Text('生成'),
                    style: ElevatedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildMediaGallery(Shot shot, List<String> paths, String mediaType) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          if (paths.isNotEmpty)
            _MediaItem(
              key: ValueKey(paths.first),
              path: paths.first,
              mediaType: mediaType,
              isGenerating:
                  _generatingTasks.contains('${shot.hashCode}_$mediaType'),
              onTap: () => _showEnlargedMediaDialog(
                  context: context,
                  shot: shot,
                  path: paths.first,
                  mediaType: mediaType),
              onDelete: () => _deleteMediaItem(shot, paths.first, mediaType),
              onRegenerate: () {
                if (mediaType == 'image') {
                  _generateImageForShot(shot);
                } else {
                  _generateVideoForShot(shot);
                }
              },
            )
        ],
      ),
    );
  }

  InputDecoration _modernInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      isDense: true,
      filled: true,
      fillColor: Theme.of(context).scaffoldBackgroundColor,
    );
  }

  Widget _buildEditablePairRow({
    required String label1,
    required TextEditingController controller1,
    required String label2,
    required TextEditingController controller2,
    VoidCallback? onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
            child: TextFormField(
                controller: controller1,
                onChanged: (v) => onChanged?.call(),
                decoration: _modernInputDecoration(label1))),
        const SizedBox(width: 12),
        Expanded(
            child: TextFormField(
                controller: controller2,
                onChanged: (v) => onChanged?.call(),
                decoration: _modernInputDecoration(label2))),
      ],
    );
  }

  Widget _buildEditableSingleRow(String label, TextEditingController controller,
      {int minLines = 1, VoidCallback? onChanged}) {
    return TextFormField(
      controller: controller,
      onChanged: (value) => onChanged?.call(),
      decoration:
          _modernInputDecoration(label).copyWith(alignLabelWithHint: true),
      minLines: minLines,
      maxLines: minLines + 2,
    );
  }
}

// 角色卡片编辑组件 (保持不变)
class _EditableCharacterCardItem extends StatefulWidget {
  final Map<String, dynamic> characterData;
  final VoidCallback onDataChanged;
  final VoidCallback onDelete;
  const _EditableCharacterCardItem({
    required this.characterData,
    required this.onDataChanged,
    required this.onDelete,
  });

  @override
  State<_EditableCharacterCardItem> createState() =>
      _EditableCharacterCardItemState();
}

class _EditableCharacterCardItemState
    extends State<_EditableCharacterCardItem> {
  Future<void> _pickReferenceImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final sourceFile = File(result.files.single.path!);

        final workbenchDirs = await ConfigService().getOrCreateWorkbenchDirs();
        final characterDir = workbenchDirs['character']!;

        final fileName = '${const Uuid().v4()}${p.extension(sourceFile.path)}';
        final newPath = p.join(characterDir.path, fileName);

        await sourceFile.copy(newPath);

        setState(() {
          widget.characterData['referenceImagePath'] = newPath;
        });
        widget.onDataChanged();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('参考图片已添加'), duration: Duration(seconds: 2)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加图片失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteReferenceImage() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认删除'),
            content: const Text('确定要删除参考图片吗?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmed) {
      setState(() {
        widget.characterData['referenceImagePath'] = null;
      });
      widget.onDataChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('参考图片已删除'), duration: Duration(seconds: 2)),
        );
      }
    }
  }

  Widget _buildReferenceImageSection() {
    final imagePath = widget.characterData['referenceImagePath'] as String?;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '参考图片',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (imagePath != null && imagePath.isNotEmpty) ...[
              TextButton.icon(
                onPressed: _pickReferenceImage,
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('更换'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: _deleteReferenceImage,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('删除'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ] else
              TextButton.icon(
                onPressed: _pickReferenceImage,
                icon: const Icon(Icons.add_photo_alternate, size: 18),
                label: const Text('添加图片'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 200,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.dividerColor),
          ),
          child: _buildImageContent(imagePath, theme),
        ),
      ],
    );
  }

  Widget _buildImageContent(String? imagePath, ThemeData theme) {
    if (imagePath == null || imagePath.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 8),
            Text(
              '暂无参考图片',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(imagePath),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline,
                    size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 8),
                const Text('图片加载失败'),
                const SizedBox(height: 4),
                Text(
                  '路径: ${p.basename(imagePath)}',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            (widget.characterData['characterName']?.toString() ?? '?')[0],
            style: TextStyle(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          widget.characterData['name']?.toString() ?? '未命名角色',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '角色: ${widget.characterData['characterName']?.toString() ?? ''} | 身份: ${widget.characterData['identity']?.toString() ?? ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          _buildReferenceImageSection(),
          const SizedBox(height: 16),
          _buildEditableDetailRow('name', '卡片名称'),
          _buildEditableDetailRow('characterName', '角色名'),
          _buildEditableDetailRow('identity', '身份'),
          _buildEditableDetailRow('appearance', '外貌', minLines: 2),
          _buildEditableDetailRow('clothing', '服装', minLines: 2),
          _buildEditableDetailRow('personality', '性格'),
          _buildEditableDetailRow('status', '状态'),
          _buildEditableDetailRow('other', '其他', minLines: 3),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('删除角色'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableDetailRow(String key, String label,
      {int minLines = 1, String? hint}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: TextFormField(
        initialValue: widget.characterData[key]?.toString() ?? '',
        onChanged: (newValue) {
          setState(() {
            widget.characterData[key] = newValue;
          });
          widget.onDataChanged();
        },
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          alignLabelWithHint: true,
          isDense: true,
        ),
        minLines: minLines,
        maxLines: minLines + 3,
        style: const TextStyle(fontSize: 14),
      ),
    );
  }
}

// 视频播放器组件 (保持不变)
class _VideoPlayerWidget extends StatefulWidget {
  final String videoPath;
  const _VideoPlayerWidget({required this.videoPath});

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
        }
        _controller.setLooping(true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized
        ? GestureDetector(
            onTap: () {
              setState(() {
                _controller.value.isPlaying
                    ? _controller.pause()
                    : _controller.play();
              });
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(_controller),
                if (!_controller.value.isPlaying)
                  const Icon(Icons.play_arrow, size: 40, color: Colors.white70),
              ],
            ),
          )
        : const Center(child: CircularProgressIndicator());
  }
}

// 媒体项组件 (保持不变)
class _MediaItem extends StatelessWidget {
  final String path;
  final String mediaType;
  final bool isGenerating;
  final VoidCallback onTap;
  final VoidCallback onRegenerate;
  final VoidCallback onDelete;

  const _MediaItem({
    super.key,
    required this.path,
    required this.mediaType,
    required this.isGenerating,
    required this.onTap,
    required this.onRegenerate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        fit: StackFit.expand,
        children: [
          mediaType == 'image'
              ? Image.file(File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => const Icon(Icons.broken_image))
              : _VideoPlayerWidget(videoPath: path),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                splashColor: Colors.white.withOpacity(0.1),
                highlightColor: Colors.white.withOpacity(0.1),
                child: Container(),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.black.withOpacity(0.0),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _MediaActionButton(
                      icon: Icons.refresh,
                      tooltip: '重新生成',
                      onPressed: onRegenerate),
                  _MediaActionButton(
                      icon: Icons.delete_outline,
                      tooltip: '删除',
                      onPressed: onDelete),
                ],
              ),
            ),
          ),
          if (isGenerating)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                    child: CircularProgressIndicator(color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }
}

class _MediaActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _MediaActionButton(
      {required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white),
      tooltip: tooltip,
      onPressed: onPressed,
      splashRadius: 20,
      iconSize: 22,
    );
  }
}

// 媒体预览弹窗 (保持不变)
class _MediaViewerDialog extends StatefulWidget {
  final String mediaPath;
  final String mediaType;
  final VoidCallback onRegenerate;
  final VoidCallback onDelete;

  const _MediaViewerDialog({
    required this.mediaPath,
    required this.mediaType,
    required this.onRegenerate,
    required this.onDelete,
  });

  @override
  State<_MediaViewerDialog> createState() => _MediaViewerDialogState();
}

class _MediaViewerDialogState extends State<_MediaViewerDialog> {
  VideoPlayerController? _videoController;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == 'video') {
      _videoController = VideoPlayerController.file(File(widget.mediaPath))
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _isInitialized = true;
              _videoController?.setLooping(true);
              _videoController?.play();
            });
          }
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (widget.mediaType == 'video' && _videoController != null) {
                  setState(() {
                    _videoController!.value.isPlaying
                        ? _videoController!.pause()
                        : _videoController!.play();
                  });
                }
              },
              child: widget.mediaType == 'image'
                  ? InteractiveViewer(
                      clipBehavior: Clip.none,
                      child: Image.file(File(widget.mediaPath)))
                  : (_isInitialized && _videoController != null
                      ? AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(_videoController!),
                              if (!_videoController!.value.isPlaying)
                                const Icon(Icons.play_arrow,
                                    color: Colors.white70, size: 60),
                            ],
                          ),
                        )
                      : const Center(child: CircularProgressIndicator())),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ViewerButton(
                    icon: Icons.refresh,
                    label: '重新生成',
                    onPressed: widget.onRegenerate),
                const SizedBox(width: 16),
                _ViewerButton(
                    icon: Icons.delete_outline,
                    label: '删除',
                    onPressed: widget.onDelete),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _ViewerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ViewerButton(
      {required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}