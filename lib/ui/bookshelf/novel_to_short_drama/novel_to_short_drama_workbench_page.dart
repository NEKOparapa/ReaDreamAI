// lib/ui/bookshelf/novel_to_short_drama/novel_to_short_drama_workbench_page.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pool/pool.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as p;

import '../../../base/config_service.dart';
import '../../../models/book.dart';
import '../../../models/character_card_model.dart';
import '../../../services/cache_manager/cache_manager.dart';
import '../../../services/drawing_service/drawing_service.dart';
import '../../../services/task_executor/storyboard_generator_executor.dart';
import '../../../services/video_service/video_service.dart';
import 'package:file_picker/file_picker.dart';  // 新增
import 'package:uuid/uuid.dart';                 // 新增

// [模型定义]
class Shot {
  int shotNumber;
  TextEditingController shotTypeController;
  TextEditingController cameraMoveController;
  TextEditingController charactersController;
  TextEditingController contentController;
  TextEditingController soundController;
  TextEditingController durationController;
  TextEditingController firstFramePromptController = TextEditingController();
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

    shot.firstFramePromptController.text = json['firstFramePrompt'] as String? ?? '';
    shot.firstFrameImagePaths = List<String>.from(json['firstFrameImagePaths'] ?? []);
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
      shots: shotsList.map((s) => Shot.fromJson(s as Map<String, dynamic>)).toList(),
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
      scenes: scenesList.map((s) => Scene.fromJson(s as Map<String, dynamic>)).toList(),
    );
  }
}

// --- 工作台主界面 ---

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
        _charactersData = widget.initialCharacters.map((c) => c.toJson()).toList();
        await _saveWorkbenchData(showSnackbar: false);
      } else {
        final savedBookId = _configService.getSetting<String?>('workbench_last_active_book_id', null);
        if (savedBookId == widget.book.id) {
          _charactersData = List<Map<String, dynamic>>.from(
            _configService.getSetting('workbench_active_characters', [])
          );
          final savedScriptJson = List<Map<String, dynamic>>.from(
            _configService.getSetting('workbench_active_script', [])
          );
          if (savedScriptJson.isNotEmpty) {
            _script = savedScriptJson.map((json) => ChapterScript.fromJson(json)).toList();
          } else {
            _initializeDefaultScript();
          }
        } else {
          _initializeDefaultScript();
          _charactersData = List<Map<String, dynamic>>.from(
            _configService.getSetting('workbench_active_characters', [])
          );
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
      _configService.getSetting('workbench_active_script', [])
    );

    if (defaultScriptJson.isNotEmpty && widget.book.chapters.isNotEmpty) {
      _script = widget.book.chapters.map((chapter) {
        final templateChapter = defaultScriptJson.first;
        return ChapterScript.fromJson({
          ...templateChapter,
          'originalChapterTitle': chapter.title,
        });
      }).toList();
    } else {
      _script = [ChapterScript(originalChapterTitle: widget.book.chapters.isNotEmpty
        ? widget.book.chapters.first.title
        : "默认章节")];
    }
  }

  Future<void> _saveWorkbenchData({bool showSnackbar = true, String message = '工作台已保存'}) async {
    _debounce?.cancel();
    try {
      await _configService.modifySetting('workbench_active_characters', _charactersData);
      final scriptJson = _script.map((cs) => cs.toJson()).toList();
      await _configService.modifySetting('workbench_active_script', scriptJson);
      await _configService.modifySetting('workbench_last_active_book_id', widget.book.id);
      if (mounted && showSnackbar) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
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
      final allShots = _script.expand((cs) => cs.scenes.expand((s) => s.shots)).toList();
      final totalShots = allShots.length;
      if (totalShots == 0) return;

      final characters = _charactersData.map((data) => CharacterCard.fromJson(data)).toList();
      int processedCount = 0;

      await Future.wait(allShots.map((shot) async {
        final prompts = await StoryboardGeneratorExecutor.instance.generatePromptsForShot(
          shot: shot,
          characters: characters,
        );
        processedCount++;
        if (mounted) {
          setState(() {
            shot.firstFramePromptController.text = prompts.imagePrompt;
            shot.videoPromptController.text = prompts.videoPrompt;
            _generationStatus = '正在生成提示词: $processedCount / $totalShots';
            _generationProgress = processedCount / totalShots;
          });
        }
      }));

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('提示词生成完毕!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('提示词生成失败: $e')));
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

    final imageSizeString = _configService.getSetting<String>('image_gen_size', '1024*1024');
    int width = 1024;
    int height = 1024;
    try {
      final parts = imageSizeString.split('*');
      if (parts.length == 2) {
        width = int.parse(parts[0]);
        height = int.parse(parts[1]);
      }
    } catch (_) {}

    final videoDuration = _configService.getSetting<int>('video_gen_duration', 5);
    final videoResolution = _configService.getSetting<String>('video_gen_resolution', '720p');

    final imageSaveDir = await CacheManager().getOrCreateBookSubDir(widget.book.id, p.join('media', 'images'));
    final videoSaveDir = await CacheManager().getOrCreateBookSubDir(widget.book.id, p.join('media', 'videos'));

    final pool = Pool(2);
    final allShots = _script.expand((cs) => cs.scenes.expand((s) => s.shots)).toList();
    final totalShots = allShots.length;
    if (totalShots == 0) {
      setState(() => _isGenerating = false);
      return;
    }
    int processedCount = 0;

    try {
      for (final shot in allShots) {
        pool.withResource(() async {
          if (shot.firstFramePromptController.text.isNotEmpty) {
            try {
              final imagePaths = await DrawingService.instance.generateImages(
                  positivePrompt: shot.firstFramePromptController.text,
                  negativePrompt: _configService.getActiveTagContent(
                      'drawing_negative_tags', 'active_drawing_negative_tag_id'),
                  saveDir: imageSaveDir.path, count: 1, width: width, height: height,
                  apiConfig: _configService.getActiveDrawingApi());

              if (imagePaths != null && imagePaths.isNotEmpty) {
                if (mounted) setState(() => shot.firstFrameImagePaths.addAll(imagePaths));

                if (shot.videoPromptController.text.isNotEmpty) {
                  final videoPaths = await VideoService.instance.generateVideo(
                      positivePrompt: shot.videoPromptController.text,
                      saveDir: videoSaveDir.path, count: 1, referenceImagePath: imagePaths.first,
                      duration: videoDuration, resolution: videoResolution,
                      apiConfig: _configService.getActiveVideoApi());
                  if (videoPaths != null && videoPaths.isNotEmpty) {
                    if (mounted) setState(() => shot.videoPaths.addAll(videoPaths));
                  }
                }
              }
            } catch (e) {
              debugPrint('生成分镜 ${shot.shotNumber} 的媒体失败: $e');
            }
          }
          processedCount++;
          if (mounted) {
             setState(() {
                _generationStatus = '正在生成媒体: $processedCount / $totalShots';
                _generationProgress = processedCount / totalShots;
             });
          }
        });
      }
      await pool.close();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('媒体生成任务完成!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('媒体生成过程中发生错误: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<bool> _showDeleteConfirmationDialog({required String title, required String content}) async {
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
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              child: const Text('删除'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    ) ?? false;
  }

  void _deleteCharacter(int index) async {
    final confirmed = await _showDeleteConfirmationDialog(
      title: '确认删除角色',
      content: '确定要删除角色“${_charactersData[index]['name']}”吗？此操作无法撤销。'
    );
    if (confirmed) {
      setState(() {
        _charactersData.removeAt(index);
      });
      _debounceSaveWorkbenchData();
    }
  }
  
  void _deleteScene(ChapterScript chapter, Scene scene) async {
    final confirmed = await _showDeleteConfirmationDialog(
        title: '确认删除场景',
        content: '确定要删除这个场景及其包含的所有分镜吗？此操作无法撤销。'
    );
    if (confirmed) {
      setState(() {
        chapter.scenes.remove(scene);
      });
      _debounceSaveWorkbenchData();
    }
  }

  void _deleteShot(Scene scene, Shot shot) async {
    final confirmed = await _showDeleteConfirmationDialog(
        title: '确认删除分镜',
        content: '确定要删除这个分镜吗？此操作无法撤销。'
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('短剧工作台 - 《${widget.book.title}》'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.text_fields_outlined, size: 20),
            label: const Text('生成提示词'),
            onPressed: _isGenerating ? null : _generateAllPrompts,
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            icon: const Icon(Icons.movie_creation_outlined, size: 20),
            label: const Text('生成媒体'),
            onPressed: _isGenerating ? null : _generateAllMedia,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: '保存工作台',
            onPressed: _isGenerating ? null : () => _saveWorkbenchData(showSnackbar: true),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
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
                ],
              ),
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
          Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildNovelInfoSection() {
    final theme = Theme.of(context);
    final int chapterCount = _script.length;
    final int sceneCount = _script.fold(0, (sum, chapter) => sum + chapter.scenes.length);
    final int shotCount = _script.fold(0, (sum, chapter) => sum + chapter.scenes.fold(0, (s, scene) => s + scene.shots.length));

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
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.book.title,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
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
      decoration: isLast ? null : BoxDecoration(
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
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)),
                const SizedBox(width: 12),
                Text('正在执行任务...', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            if (_generationStatus.isNotEmpty)
              Text(_generationStatus, style: Theme.of(context).textTheme.bodyMedium),
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

  // =======================================================================
  // [KEPT] 新的章节卡片样式
  // =======================================================================
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

  // =======================================================================
  // [KEPT] 新的场景卡片样式
  // =======================================================================
  Widget _buildSceneItem(ChapterScript chapter, Scene scene, int chapterIndex, int sceneNumber) {
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
                ? const Center(child: Padding(padding: EdgeInsets.all(16), child: Text("该场景下无分镜")))
                : Column(
                    children: scene.shots.map((shot) => _buildShotItem(scene, shot)).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField(TextEditingController controller, {bool isTitle = false, String? hint, VoidCallback? onChanged}) {
    return TextFormField(
      controller: controller,
      onChanged: (value) => onChanged?.call(),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400)
      ),
      style: TextStyle(
        fontWeight: isTitle ? FontWeight.bold : FontWeight.normal,
        fontSize: isTitle ? 16 : 14,
      ),
    );
  }

  // =======================================================================
  // [REVERTED] 恢复到原始的分镜卡片样式
  // =======================================================================
  Widget _buildShotItem(Scene scene, Shot shot) {
    final theme = Theme.of(context);
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
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
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
                  label1: '景别', controller1: shot.shotTypeController,
                  label2: '运镜', controller2: shot.cameraMoveController,
                  onChanged: _debounceSaveWorkbenchData,
                ),
                const SizedBox(height: 12),
                _buildEditablePairRow(
                  label1: '登场角色', controller1: shot.charactersController,
                  label2: '分镜时长', controller2: shot.durationController,
                  onChanged: _debounceSaveWorkbenchData,
                ),
                const SizedBox(height: 12),
                _buildEditableSingleRow('画面内容', shot.contentController, minLines: 2, onChanged: _debounceSaveWorkbenchData),
                const SizedBox(height: 12),
                _buildEditableSingleRow('声音/对白', shot.soundController, minLines: 2, onChanged: _debounceSaveWorkbenchData),
                const Divider(thickness: 1, height: 24),
                Text('AI 生成', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildAiGenerationRow(
                  promptController: shot.firstFramePromptController,
                  promptLabel: '首帧图像提示词',
                  mediaPaths: shot.firstFrameImagePaths,
                  mediaType: 'image',
                ),
                const SizedBox(height: 16),
                _buildAiGenerationRow(
                  promptController: shot.videoPromptController,
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

  Widget _buildAiGenerationRow({
    required TextEditingController promptController,
    required String promptLabel,
    required List<String> mediaPaths,
    required String mediaType,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          height: 84.375,
          child: mediaPaths.isEmpty
              ? _buildPlaceholder(mediaType)
              : _buildMediaGallery(mediaPaths, mediaType),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: promptController,
            onChanged: (value) => _debounceSaveWorkbenchData(),
            decoration: InputDecoration(
              labelText: promptLabel,
              border: const OutlineInputBorder(),
              isDense: true,
              alignLabelWithHint: true,
            ),
            minLines: 4,
            maxLines: 4,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder(String mediaType) {
    final isImage = mediaType == 'image';
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300, width: 1.5, style: BorderStyle.solid),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isImage ? Icons.image_outlined : Icons.video_library_outlined,
            size: 32,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 4),
          Text(
            isImage ? '待生成图片' : '待生成视频',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          )
        ],
      ),
    );
  }

  Widget _buildMediaGallery(List<String> paths, String mediaType) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        itemBuilder: (context, index) {
          final path = paths[index];
          return SizedBox(
            width: 150,
            child: mediaType == 'image'
                ? Image.file(File(path), fit: BoxFit.cover)
                : _VideoPlayerWidget(videoPath: path),
          );
        },
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
    required String label1, required TextEditingController controller1,
    required String label2, required TextEditingController controller2,
    VoidCallback? onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: TextFormField(controller: controller1, onChanged: (v) => onChanged?.call(), decoration: _modernInputDecoration(label1))),
        const SizedBox(width: 12),
        Expanded(child: TextFormField(controller: controller2, onChanged: (v) => onChanged?.call(), decoration: _modernInputDecoration(label2))),
      ],
    );
  }

  Widget _buildEditableSingleRow(String label, TextEditingController controller, {int minLines = 1, VoidCallback? onChanged}) {
    return TextFormField(
      controller: controller,
      onChanged: (value) => onChanged?.call(),
      decoration: _modernInputDecoration(label).copyWith(alignLabelWithHint: true),
      minLines: minLines,
      maxLines: minLines + 2,
    );
  }
}

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
  State<_EditableCharacterCardItem> createState() => _EditableCharacterCardItemState();
}


class _EditableCharacterCardItemState extends State<_EditableCharacterCardItem> {
  
  /// 选择并添加参考图片
  Future<void> _pickReferenceImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      
      if (result != null && result.files.single.path != null) {
        final sourceFile = File(result.files.single.path!);
        
        // 获取工作台文件夹
        final workbenchDirs = await ConfigService().getOrCreateWorkbenchDirs();
        final characterDir = workbenchDirs['character']!;
        
        // 生成新文件名
        final fileName = '${const Uuid().v4()}${p.extension(sourceFile.path)}';
        final newPath = p.join(characterDir.path, fileName);
        
        // 复制文件到工作台
        await sourceFile.copy(newPath);
        
        // 更新角色数据
        setState(() {
          widget.characterData['referenceImagePath'] = newPath;
        });
        widget.onDataChanged();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('参考图片已添加'), duration: Duration(seconds: 2)),
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

  /// 删除参考图片
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
    ) ?? false;
    
    if (confirmed) {
      setState(() {
        widget.characterData['referenceImagePath'] = null;
      });
      widget.onDataChanged();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('参考图片已删除'), duration: Duration(seconds: 2)),
        );
      }
    }
  }

  /// 构建参考图片显示区域
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

  /// 构建图片内容
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
                Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
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
          _buildReferenceImageSection(),  // 添加参考图片区域
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

  Widget _buildEditableDetailRow(String key, String label, {int minLines = 1, String? hint}) {
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
                _controller.value.isPlaying ? _controller.pause() : _controller.play();
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