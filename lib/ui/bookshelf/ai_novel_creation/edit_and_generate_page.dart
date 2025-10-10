// lib/ui/bookshelf/ai_novel_creation/edit_and_generate_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../base/config_service.dart';
import '../../../base/default_configs.dart';
import '../../../models/book.dart';
import '../../../models/bookshelf_entry.dart';
import '../../../models/character_profile.dart';
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
    // 每次进入这个页面都会重新加载配置，确保数据最新
    loadOutlineFromConfig();
  }

  /// 从配置文件加载数据。如果配置为空，则加载默认预设。
  void loadOutlineFromConfig() {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    
    // 尝试从用户配置加载数据
    var loadedStoryline = List<Map<String, dynamic>>.from(
        _configService.getSetting<List>('ai_novel_creation_storyline', []));
    var loadedTitle = _configService.getSetting<String>('ai_novel_creation_title', '');

    // 如果没有加载到有效数据（比如用户清空了），则使用默认预设
    if (loadedStoryline.isEmpty && loadedTitle.isEmpty) {
      _outline = {
        'title': appDefaultConfigs['ai_novel_creation_title'],
        'background_setting': appDefaultConfigs['ai_novel_creation_background_setting'],
        'writing_style': appDefaultConfigs['ai_novel_creation_writing_style'],
        'main_characters': List<Map<String, dynamic>>.from(appDefaultConfigs['ai_novel_creation_main_characters']),
        'storyline': List<Map<String, dynamic>>.from(appDefaultConfigs['ai_novel_creation_storyline']),
      };
    } else {
      // 否则，使用从配置文件中加载到的用户数据。
      _outline = {
        'title': loadedTitle,
        'background_setting': _configService.getSetting<String>('ai_novel_creation_background_setting', ''),
        'writing_style': _configService.getSetting<String>('ai_novel_creation_writing_style', ''),
        'main_characters': List<Map<String, dynamic>>.from(
            _configService.getSetting<List>('ai_novel_creation_main_characters', [])),
        'storyline': loadedStoryline,
      };
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// 构建可编辑字段，并直接绑定到对应的配置项保存
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
        // 实时保存单个字段到配置文件
        _configService.modifySetting(configKey, newValue);
        // 同时更新内存中的 _outline，以备生成时使用
        _outline[configKey.replaceFirst('ai_novel_creation_', '')] = newValue;
      },
    );
  }

  /// 开始生成小说
  Future<void> startGeneration() async {
    if (_isGenerating) return;

    setState(() {
      _isGenerating = true;
      _progress = 0.0;
      _statusMessage = '正在初始化...';
    });

    try {
      final List<String> chapterContents = [];
      final List<ChapterStructure> finalChapters = [];
      final storyline = _outline['storyline'] as List;
      int globalLineIdCounter = 0;

      for (int i = 0; i < storyline.length; i++) {
        setState(() {
          _statusMessage = '正在生成第 ${i + 1}/${storyline.length} 章...';
        });

        final result = await NovelGeneratorService.instance.generateChapterContent(
          title: _outline['title'],
          backgroundSetting: _outline['background_setting'],
          writingStyle: _outline['writing_style'],
          mainCharacters: List<Map<String, dynamic>>.from(_outline['main_characters']),
          storyline: List<Map<String, dynamic>>.from(storyline),
          chapterIndex: i,
          wordsPerChapter: 1500, // 或从配置读取
        );

        final String content = result['chapter_content'];
        chapterContents.add("## ${storyline[i]['chapter_title']}\n\n$content");

        _outline['main_characters'] = result['updated_characters'];
        storyline[i]['chapter_summary'] = result['new_chapter_summary'];

        final chapterLines = _createLines(content, 'content.txt', globalLineIdCounter);
        final newChapter = ChapterStructure(
          id: const Uuid().v4(),
          title: storyline[i]['chapter_title'],
          sourceFile: 'content.txt',
          lines: chapterLines,
          chapterSummary: storyline[i]['chapter_summary'],
        );
        finalChapters.add(newChapter);
        globalLineIdCounter += chapterLines.length;

        setState(() {
          _progress = (i + 1) / storyline.length;
        });
      }

      setState(() { _statusMessage = '所有章节已生成，正在保存书籍...'; });
      await _saveBook(finalChapters, chapterContents.join('\n\n---\n\n'));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('《${_outline['title']}》已成功创建！')),
        );
        // 成功后返回 true，通知书架刷新
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败: $e')),
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

  /// 根据文本内容创建行结构
  List<LineStructure> _createLines(String content, String sourceFilename, int startLineId) {
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
  
  /// 保存生成的书籍到缓存和书架
  Future<void> _saveBook(List<ChapterStructure> chapters, String fullTextContent) async {
    final tempDir = await getTemporaryDirectory();
    final sanitizedTitle = _outline['title'].replaceAll(RegExp(r'[\/:*?"<>|]'), '_');
    final tempFileName = '$sanitizedTitle.txt';
    final tempFilePath = p.join(tempDir.path, tempFileName);
    final tempFile = File(tempFilePath);
    await tempFile.writeAsString(fullTextContent);

    final cacheManager = CacheManager();
    final (String bookId, String cachedPath, _) = await cacheManager.createBookCacheInfrastructure(tempFilePath);
    await tempFile.delete();

    final characters = (_outline['main_characters'] as List)
        .map((c) => CharacterProfile.fromJson(Map<String, dynamic>.from(c)))
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 创作：编辑大纲与生成'),
      ),
      body: _buildBody(),
      floatingActionButton: _isGenerating
          ? null // 生成时隐藏按钮
          : FloatingActionButton.extended(
              onPressed: startGeneration,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始生成'),
            ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_isGenerating) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(value: _progress),
              const SizedBox(height: 24),
              Text(_statusMessage, style: Theme.of(context).textTheme.titleLarge),
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
          _buildEditableField('标题', _outline['title'], 'ai_novel_creation_title'),
          const SizedBox(height: 16),
          _buildEditableField('背景设定', _outline['background_setting'], 'ai_novel_creation_background_setting', maxLines: 5),
          const SizedBox(height: 16),
          _buildEditableField('文风设定', _outline['writing_style'], 'ai_novel_creation_writing_style', maxLines: 3),
          const SizedBox(height: 24),
          Text('主要角色', style: Theme.of(context).textTheme.titleLarge),
          ...(_outline['main_characters'] as List).asMap().entries.map((entry) {
            int idx = entry.key;
            var char = entry.value;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    TextFormField(
                      initialValue: char['name'] ?? '',
                      decoration: const InputDecoration(labelText: '名字'),
                      onChanged: (val) {
                        _outline['main_characters'][idx]['name'] = val;
                        _configService.modifySetting('ai_novel_creation_main_characters', _outline['main_characters']);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: char['identity'] ?? '',
                      decoration: const InputDecoration(labelText: '身份'),
                      onChanged: (val) {
                        _outline['main_characters'][idx]['identity'] = val;
                        _configService.modifySetting('ai_novel_creation_main_characters', _outline['main_characters']);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: char['appearance'] ?? '',
                      decoration: const InputDecoration(labelText: '外貌'),
                      maxLines: 2,
                      onChanged: (val) {
                        _outline['main_characters'][idx]['appearance'] = val;
                        _configService.modifySetting('ai_novel_creation_main_characters', _outline['main_characters']);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: char['personality'] ?? '',
                      decoration: const InputDecoration(labelText: '性格'),
                      maxLines: 2,
                      onChanged: (val) {
                        _outline['main_characters'][idx]['personality'] = val;
                        _configService.modifySetting('ai_novel_creation_main_characters', _outline['main_characters']);
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
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
                      decoration: InputDecoration(labelText: '第 ${idx + 1} 章标题'),
                      onChanged: (val) {
                        _outline['storyline'][idx]['chapter_title'] = val;
                        _configService.modifySetting('ai_novel_creation_storyline', _outline['storyline']);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: chapter['chapter_summary'] ?? '',
                      decoration: const InputDecoration(labelText: '章节简述'),
                      maxLines: 3,
                       onChanged: (val) {
                        _outline['storyline'][idx]['chapter_summary'] = val;
                        _configService.modifySetting('ai_novel_creation_storyline', _outline['storyline']);
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 80), // 留出空间给浮动按钮
        ],
      ),
    );
  }
}