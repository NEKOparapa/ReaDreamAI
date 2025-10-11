// lib/ui/bookshelf/ai_novel_creation/edit_and_generate_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../base/config_service.dart';
import '../../../base/default_configs.dart';
import '../../../base/log/log_service.dart';
import '../../../models/book.dart';
import '../../../models/bookshelf_entry.dart';
import '../../../models/character_card_model.dart';
import '../../../services/cache_manager/cache_manager.dart';
import '../../../services/task_executor/novel_generator_service.dart';

class EditAndGeneratePage extends StatefulWidget {
  const EditAndGeneratePage({super.key});

  @override
  State<EditAndGeneratePage> createState() => EditAndGeneratePageState();
}

class EditAndGeneratePageState extends State<EditAndGeneratePage> {
  final _configService = ConfigService();
  late Map<String, dynamic> _outline;
  bool _isGenerating = false;
  double _progress = 0.0;
  String _statusMessage = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    loadOutlineFromConfig();
  }

  void loadOutlineFromConfig() {
    if (mounted) setState(() => _isLoading = true);
    LogService.instance.info('从配置加载小说大纲...');
    var loadedStoryline = List<Map<String, dynamic>>.from(
        _configService.getSetting<List>('ai_novel_creation_storyline', []));
    var loadedTitle =
        _configService.getSetting<String>('ai_novel_creation_title', '');

    if (loadedStoryline.isEmpty && loadedTitle.isEmpty) {
      LogService.instance.warn('未找到现有大纲，加载默认大纲。');
      _outline = {
        'title': appDefaultConfigs['ai_novel_creation_title'],
        'background_setting':
            appDefaultConfigs['ai_novel_creation_background_setting'],
        'writing_style': appDefaultConfigs['ai_novel_creation_writing_style'],
        'main_characters': List<Map<String, dynamic>>.from(
            appDefaultConfigs['ai_novel_creation_main_characters']),
        'storyline': List<Map<String, dynamic>>.from(
            appDefaultConfigs['ai_novel_creation_storyline']),
      };
    } else {
      LogService.instance.info('小说大纲加载完成。');
      _outline = {
        'title': loadedTitle,
        'background_setting': _configService.getSetting<String>(
            'ai_novel_creation_background_setting', ''),
        'writing_style': _configService.getSetting<String>(
            'ai_novel_creation_writing_style', ''),
        'main_characters': List<Map<String, dynamic>>.from(
            _configService.getSetting<List>(
                'ai_novel_creation_main_characters', [])),
        'storyline': loadedStoryline,
      };
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Widget _buildEditableField(
      String label, String initialValue, String configKey,
      {int maxLines = 1}) {
    return TextFormField(
      initialValue: initialValue,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      maxLines: maxLines,
      onChanged: (newValue) {
        _configService.modifySetting(configKey, newValue);
        _outline[configKey.replaceFirst('ai_novel_creation_', '')] = newValue;
      },
    );
  }

  Future<void> startGeneration() async {
    if (_isGenerating) return;
    setState(() {
      _isGenerating = true;
      _progress = 0.0;
      _statusMessage = '正在初始化...';
    });
    LogService.instance.info('开始生成小说正文...');
    try {
      final List<String> chapterContents = [];
      final List<ChapterStructure> finalChapters = [];
      final storyline = _outline['storyline'] as List;
      int globalLineIdCounter = 0;

      for (int i = 0; i < storyline.length; i++) {
        setState(() => _statusMessage = '正在生成第 ${i + 1}/${storyline.length} 章...');
        LogService.instance.info('正在请求生成第 ${i + 1} 章...');
        final result =
            await NovelGeneratorService.instance.generateChapterContent(
          title: _outline['title'],
          backgroundSetting: _outline['background_setting'],
          writingStyle: _outline['writing_style'],
          mainCharacters:
              List<Map<String, dynamic>>.from(_outline['main_characters']),
          storyline: List<Map<String, dynamic>>.from(storyline),
          chapterIndex: i,
          wordsPerChapter: 1500, // 或从配置读取
        );
        LogService.instance.info('第 ${i + 1} 章生成成功。');
        final String content = result['chapter_content'];
        chapterContents.add("## ${storyline[i]['chapter_title']}\n\n$content");
        _outline['main_characters'] = result['updated_characters'];
        storyline[i]['chapter_summary'] = result['new_chapter_summary'];
        final chapterLines =
            _createLines(content, 'content.txt', globalLineIdCounter);
        final newChapter = ChapterStructure(
          id: const Uuid().v4(),
          title: storyline[i]['chapter_title'],
          sourceFile: 'content.txt',
          lines: chapterLines,
          chapterSummary: storyline[i]['chapter_summary'],
        );
        finalChapters.add(newChapter);
        globalLineIdCounter += chapterLines.length;
        setState(() => _progress = (i + 1) / storyline.length);
      }

      setState(() {
        _statusMessage = '所有章节已生成，正在保存书籍...';
      });
      LogService.instance.info('所有章节内容生成完毕，准备保存书籍...');
      await _saveBook(finalChapters, chapterContents.join('\n\n---\n\n'));

      if (mounted) {
        LogService.instance.success('书籍《${_outline['title']}》已成功创建并保存。');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('《${_outline['title']}》已成功创建！')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e, s) {
      LogService.instance.error('小说正文生成过程中发生错误', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('生成失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  List<LineStructure> _createLines(
      String content, String sourceFilename, int startLineId) {
    final List<LineStructure> result = [];
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    int lineId = startLineId;
    for (final lineText in lines) {
      if (lineText.trim().isNotEmpty) {
        result.add(LineStructure(
          id: lineId++,
          text: lineText.trim(),
          sourceInfo: sourceFilename,
          originalContent: lineText,
        ));
      }
    }
    return result;
  }

  Future<void> _saveBook(
      List<ChapterStructure> chapters, String fullTextContent) async {
    LogService.instance.info('开始保存书籍: ${_outline['title']}');
    final tempDir = await getTemporaryDirectory();
    final sanitizedTitle = _outline['title']
        .replaceAll(RegExp(r'[\\/*?:"<>|]'), '_'); // Sanitize filename
    final tempFileName = '$sanitizedTitle.txt';
    final tempFilePath = p.join(tempDir.path, tempFileName);
    final tempFile = File(tempFilePath);
    await tempFile.writeAsString(fullTextContent);

    final cacheManager = CacheManager();
    final (String bookId, String cachedPath, _) =
        await cacheManager.createBookCacheInfrastructure(tempFilePath);
    LogService.instance
        .info('书籍缓存基础设施已创建，ID: $bookId, 路径: $cachedPath');
    await tempFile.delete();

    // 使用 CharacterCard.fromJson
    final characters = (_outline['main_characters'] as List)
        .map((c) => CharacterCard.fromJson(Map<String, dynamic>.from(c)))
        .toList();

    final newBook = Book(
      id: bookId,
      title: _outline['title'],
      fileType: 'txt',
      originalPath: 'none',
      cachedPath: cachedPath,
      chapters: chapters,
      backgroundSetting: _outline['background_setting'],
      writingStyle: _outline['writing_style'],
      characters: characters,
      coverImagePath: null,
    );

    final subCachePath = await cacheManager.saveBookDetail(newBook);
    LogService.instance.info('书籍详情已保存到: $subCachePath');
    final newEntry = BookshelfEntry(
      id: bookId,
      title: newBook.title,
      originalPath: 'none',
      fileType: 'txt',
      subCachePath: subCachePath,
      coverImagePath: null,
    );

    final entries = await cacheManager.loadBookshelf();
    entries.add(newEntry);
    await cacheManager.saveBookshelf(entries);
    LogService.instance.success('书籍保存流程完成。');
  }

  void _addCharacter() {
    setState(() {
      final newChar =
          CharacterCard(id: const Uuid().v4(), name: '新角色').toJson();
      (_outline['main_characters'] as List).add(newChar);
    });
    _configService.modifySetting(
        'ai_novel_creation_main_characters', _outline['main_characters']);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('已添加一个新角色，请填写信息。'), duration: Duration(seconds: 2)),
    );
  }

  void _saveCharacterToPresets(Map<String, dynamic> characterData) async {
    LogService.instance.info('正在将角色 ${characterData['name']} 保存为预设...');
    final presetList = List<Map<String, dynamic>>.from(
        _configService.getSetting<List>('drawing_character_cards', []));
    // 创建一个新的CharacterCard实例，确保ID是全新的，并且不是系统预设
    final newPreset = CharacterCard(
      id: const Uuid().v4(),
      name: characterData['name'] ?? '未命名预设',
      characterName: characterData['characterName'] ?? '',
      identity: characterData['identity'] ?? '',
      appearance: characterData['appearance'] ?? '',
      clothing: characterData['clothing'] ?? '',
      personality: characterData['personality'] ?? '',
      status: characterData['status'] ?? '',
      other: characterData['other'] ?? '',
      isSystemPreset: false, // 关键：用户保存的都是非系统预设
    ).toJson();

    presetList.add(newPreset);
    await _configService.modifySetting('drawing_character_cards', presetList);
    LogService.instance.success('角色“${newPreset['name']}”已成功保存为新预设。');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('角色“${newPreset['name']}”已存为新预设！')),
      );
    }
  }

  // --- 新增的方法 ---
  void _deleteCharacter(int index) {
    // 弹出确认对话框
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: const Text('您确定要删除这个角色吗？此操作无法撤销。'),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () {
                Navigator.of(context).pop(); // 关闭对话框
              },
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error, // 使用主题中的错误颜色，更醒目
              ),
              child: const Text('删除'),
              onPressed: () {
                setState(() {
                  // 从列表中移除角色
                  (_outline['main_characters'] as List).removeAt(index);
                });
                // 更新并保存配置
                _configService.modifySetting(
                    'ai_novel_creation_main_characters', _outline['main_characters']);
                Navigator.of(context).pop(); // 关闭对话框
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('角色已删除。'), duration: Duration(seconds: 2)),
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 创作：编辑大纲与生成'),
      ),
      body: _buildBody(),
      floatingActionButton: _isGenerating
          ? null
          : FloatingActionButton.extended(
              onPressed: startGeneration,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始生成'),
            ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_isGenerating) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(value: _progress),
              const SizedBox(height: 24),
              Text(_statusMessage,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('${(_progress * 100).toStringAsFixed(0)}% 完成'),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildEditableField(
              '标题', _outline['title'], 'ai_novel_creation_title'),
          const SizedBox(height: 16),
          _buildEditableField('背景设定', _outline['background_setting'],
              'ai_novel_creation_background_setting',
              maxLines: 5),
          const SizedBox(height: 16),
          _buildEditableField('文风设定', _outline['writing_style'],
              'ai_novel_creation_writing_style',
              maxLines: 3),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('主要角色', style: Theme.of(context).textTheme.titleLarge),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('添加新角色'),
                onPressed: _addCharacter,
              )
            ],
          ),
          ..._buildCharacterCards(),
          const SizedBox(height: 24),
          Text('故事线', style: Theme.of(context).textTheme.titleLarge),
          ...(_outline['storyline'] as List).asMap().entries.map((entry) {
            int idx = entry.key;
            var chapter = entry.value;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    TextFormField(
                      initialValue: chapter['chapter_title'] ?? '',
                      decoration:
                          InputDecoration(labelText: '第 ${idx + 1} 章标题'),
                      onChanged: (val) {
                        _outline['storyline'][idx]['chapter_title'] = val;
                        _configService.modifySetting(
                            'ai_novel_creation_storyline',
                            _outline['storyline']);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: chapter['chapter_summary'] ?? '',
                      decoration: const InputDecoration(labelText: '章节简述'),
                      maxLines: 3,
                      onChanged: (val) {
                        _outline['storyline'][idx]['chapter_summary'] = val;
                        _configService.modifySetting(
                            'ai_novel_creation_storyline',
                            _outline['storyline']);
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  List<Widget> _buildCharacterCards() {
    return (_outline['main_characters'] as List).asMap().entries.map((entry) {
      int idx = entry.key;
      var char = entry.value as Map<String, dynamic>;

      Widget buildCharacterField(String key, String label,
          {int maxLines = 1}) {
        return TextFormField(
          initialValue: char[key] ?? '',
          decoration: InputDecoration(labelText: label),
          maxLines: maxLines,
          onChanged: (val) {
            _outline['main_characters'][idx][key] = val;
            _configService.modifySetting(
                'ai_novel_creation_main_characters',
                _outline['main_characters']);
          },
        );
      }

      return Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildCharacterField('name', '卡片名称'),
              const SizedBox(height: 8),
              buildCharacterField('characterName', '角色名'),
              const SizedBox(height: 8),
              buildCharacterField('identity', '身份'),
              const SizedBox(height: 8),
              buildCharacterField('appearance', '外貌', maxLines: 2),
              const SizedBox(height: 8),
              buildCharacterField('clothing', '服装', maxLines: 2),
              const SizedBox(height: 8),
              buildCharacterField('personality', '性格', maxLines: 2),
              const SizedBox(height: 8),
              buildCharacterField('status', '状态'),
              const SizedBox(height: 8),
              buildCharacterField('other', '其他备注', maxLines: 2),
              const SizedBox(height: 12),
              // --- 修改的部分 ---
              Row(
                mainAxisAlignment: MainAxisAlignment.end, // 按钮靠右对齐
                children: [
                  // 新增的删除按钮
                  TextButton.icon(
                    onPressed: () => _deleteCharacter(idx),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('删除角色卡片'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: 8), // 两个按钮之间的间距
                  // 原有的存为预设按钮
                  TextButton.icon(
                    onPressed: () => _saveCharacterToPresets(char),
                    icon: const Icon(Icons.save_alt, size: 18),
                    label: const Text('保存到角色设定'),
                  ),
                ],
              )
            ],
          ),
        ),
      );
    }).toList();
  }
}