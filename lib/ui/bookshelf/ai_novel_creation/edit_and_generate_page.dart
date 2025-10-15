//lib/ui/bookshelf/ai_novel_creation/edit_and_generate_page.dart

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../base/config_service.dart';
import '../../../base/default_configs.dart';
import '../../../base/log/log_service.dart';
import '../../../models/character_card_model.dart';
import '../../../services/task_executor/novel_generator_service.dart';
import 'novel_generation_progress_page.dart';

class EditAndGeneratePage extends StatefulWidget {
  const EditAndGeneratePage({super.key});

  @override
  State<EditAndGeneratePage> createState() => EditAndGeneratePageState();
}

class EditAndGeneratePageState extends State<EditAndGeneratePage> {
  final _configService = ConfigService();
  late Map<String, dynamic> _outline;
  bool _isLoading = true;
  bool _isRegeneratingChapters = false;

  late TextEditingController _titleController;

  final Set<int> _selectedChapterIndices = {};

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    loadOutlineFromConfig();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _resyncChapterIds() {
    final chapters = _outline['storyline'] as List;
    for (int i = 0; i < chapters.length; i++) {
      if (chapters[i] is Map<String, dynamic>) {
        (chapters[i] as Map<String, dynamic>)['chapter_id'] = i + 1;
      }
    }
  }

  void loadOutlineFromConfig() {
    if (mounted) setState(() => _isLoading = true);
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
    _resyncChapterIds();
    _titleController.text = _outline['title'];
    if (mounted) setState(() => _isLoading = false);
  }

  void navigateToGenerationPage() {
    _configService.modifySetting(
        'ai_novel_creation_title', _titleController.text);
    _outline['title'] = _titleController.text;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NovelGenerationProgressPage(outline: _outline),
      ),
    ).then((success) {
      if (success == true && mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  void _saveCharacterToPresets(Map<String, dynamic> characterData) async {
    LogService.instance.info('正在将角色 ${characterData['name']} 保存为预设...');
    final presetList = List<Map<String, dynamic>>.from(
        _configService.getSetting<List>('drawing_character_cards', []));
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
      isSystemPreset: false,
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

  void _deleteCharacter(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: const Text('您确定要删除这个角色吗？此操作无法撤销。'),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('删除'),
              onPressed: () {
                setState(() {
                  (_outline['main_characters'] as List).removeAt(index);
                });
                _configService.modifySetting('ai_novel_creation_main_characters',
                    _outline['main_characters']);
                Navigator.of(context).pop();
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

  void _addChapter() {
    setState(() {
      final newChapter = {
        "chapter_id": 0,
        "chapter_title": "新章节",
        "chapter_summary": "请填写本章的简要描述...",
        "time_span": "",
        "setting_update": "",
      };
      (_outline['storyline'] as List).add(newChapter);
      _resyncChapterIds();
    });
    _configService.modifySetting(
        'ai_novel_creation_storyline', _outline['storyline']);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已添加一个新章节。'), duration: Duration(seconds: 2)),
    );
  }

  void _moveChapter(int oldIndex, int newIndex) {
    setState(() {
      final chapters = _outline['storyline'] as List;
      final chapter = chapters.removeAt(oldIndex);
      chapters.insert(newIndex, chapter);
      _resyncChapterIds();
      _configService.modifySetting(
          'ai_novel_creation_storyline', _outline['storyline']);
    });
  }

  void _deleteChapter(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认删除章节'),
          content: const Text('您确定要删除这一章吗？此操作无法撤销。'),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('删除'),
              onPressed: () {
                setState(() {
                  (_outline['storyline'] as List).removeAt(index);
                  _resyncChapterIds();
                });
                _configService.modifySetting(
                    'ai_novel_creation_storyline', _outline['storyline']);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('章节已删除。'), duration: Duration(seconds: 2)),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _toggleChapterSelection(int index) {
    setState(() {
      if (_selectedChapterIndices.contains(index)) {
        _selectedChapterIndices.remove(index);
      } else {
        _selectedChapterIndices.add(index);
      }
    });
  }

  void _handleRegenerateSelectedChapters() async {
    if (_selectedChapterIndices.isEmpty) return;

    final modificationPromptController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('重新生成 ${_selectedChapterIndices.length} 个章节'),
        content: TextField(
          controller: modificationPromptController,
          decoration: const InputDecoration(
            labelText: '修改要求',
            hintText: '例如：让主角在这里遇到一个老朋友...',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (modificationPromptController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请填写修改要求！')),
                );
                return;
              }
              Navigator.of(context).pop(true);
            },
            child: const Text('开始生成'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) setState(() => _isRegeneratingChapters = true);

    try {
      final chapterIdsToRegen = _selectedChapterIndices
          .map((index) => _outline['storyline'][index]['chapter_id'] as int)
          .toList();

      final updatedChapters = await NovelGeneratorService.instance
          .regenerateChapterContentInOutline(
        currentOutline: _outline,
        chapterIdsToRegenerate: chapterIdsToRegen,
        modificationPrompt: modificationPromptController.text,
      );

      setState(() {
        for (var updatedChapter in updatedChapters) {
          final chapterId = updatedChapter['chapter_id'];
          final indexToUpdate = (_outline['storyline'] as List)
              .indexWhere((ch) => ch['chapter_id'] == chapterId);

          if (indexToUpdate != -1) {
            final oldChapter = _outline['storyline'][indexToUpdate] as Map<String, dynamic>;
            _outline['storyline'][indexToUpdate] = {
              ...oldChapter,
              ...updatedChapter,
            };
          }
        }
        _selectedChapterIndices.clear();
      });

      _configService.modifySetting(
          'ai_novel_creation_storyline', _outline['storyline']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('所选章节已成功重新生成！')),
        );
      }
    } catch (e, s) {
      LogService.instance.error('重新生成章节失败', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRegeneratingChapters = false);
      }
      modificationPromptController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('故事大纲'),
        actions: [
          if (_selectedChapterIndices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                icon: _isRegeneratingChapters
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.auto_fix_high_rounded),
                label: const Text('重新生成'),
                onPressed: _isRegeneratingChapters
                    ? null
                    : _handleRegenerateSelectedChapters,
              ),
            ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: navigateToGenerationPage,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('开始生成小说'),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);
    final titleStyle =
        theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 88.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('《', style: titleStyle),
                IntrinsicWidth(
                  child: TextFormField(
                    controller: _titleController,
                    textAlign: TextAlign.center,
                    style: titleStyle,
                    decoration: const InputDecoration(
                      hintText: '点击输入小说标题',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 2.0),
                    ),
                    onChanged: (newValue) {
                      _outline['title'] = newValue;
                      _configService.modifySetting(
                          'ai_novel_creation_title', newValue);
                    },
                  ),
                ),
                Text('》', style: titleStyle),
              ],
            ),
          ),
          _buildSectionHeader(theme, '背景设定', Icons.public),
          Card(
            margin: const EdgeInsets.only(top: 8.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextFormField(
                initialValue: _outline['background_setting'],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  filled: true,
                ),
                maxLines: 5,
                onChanged: (newValue) {
                  _outline['background_setting'] = newValue;
                  _configService.modifySetting(
                      'ai_novel_creation_background_setting', newValue);
                },
              ),
            ),
          ),
          _buildSectionHeader(theme, '文风设定', Icons.brush),
          Card(
            margin: const EdgeInsets.only(top: 8.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextFormField(
                initialValue: _outline['writing_style'],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  filled: true,
                ),
                maxLines: 3,
                onChanged: (newValue) {
                  _outline['writing_style'] = newValue;
                  _configService.modifySetting(
                      'ai_novel_creation_writing_style', newValue);
                },
              ),
            ),
          ),
          _buildSectionHeader(theme, '主要角色', Icons.people_alt_outlined,
              onAddPressed: _addCharacter),
          ..._buildCharacterCards(),
          _buildSectionHeader(theme, '故事线', Icons.timeline,
              onAddPressed: _addChapter),
          ...(_outline['storyline'] as List).asMap().entries.map((entry) {
            int idx = entry.key;
            var chapter = entry.value;
            final storylineList = _outline['storyline'] as List;
            final isSelected = _selectedChapterIndices.contains(idx);

            return Card(
              key: ObjectKey(chapter),
              margin: const EdgeInsets.symmetric(vertical: 8),
              color: isSelected ? theme.colorScheme.primaryContainer.withOpacity(0.3) : null,
              shape: isSelected
                  ? RoundedRectangleBorder(
                      side: BorderSide(
                          color: theme.colorScheme.primary, width: 2.0),
                      borderRadius: BorderRadius.circular(12.0),
                    )
                  : null,
              child: InkWell(
                onTap: () => _toggleChapterSelection(idx),
                borderRadius: BorderRadius.circular(12.0),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                  child: Column(
                    children: [
                      ListTile(
                        leading: CircleAvatar(child: Text('${idx + 1}')),
                        title: TextFormField(
                          initialValue: chapter['chapter_title'] ?? '',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                          decoration:
                              const InputDecoration.collapsed(hintText: '章节标题'),
                          onChanged: (val) {
                            _outline['storyline'][idx]['chapter_title'] = val;
                            _configService.modifySetting(
                                'ai_novel_creation_storyline',
                                _outline['storyline']);
                          },
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: isSelected,
                              onChanged: (bool? value) {
                                _toggleChapterSelection(idx);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_upward),
                              tooltip: '上移',
                              onPressed:
                                  idx == 0 ? null : () => _moveChapter(idx, idx - 1),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_downward),
                              tooltip: '下移',
                              onPressed: idx == storylineList.length - 1
                                  ? null
                                  : () => _moveChapter(idx, idx + 1),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: '删除本章',
                              onPressed: () => _deleteChapter(idx),
                            ),
                          ],
                        ),
                        contentPadding: const EdgeInsets.only(left: 4),
                      ),
                      const Divider(height: 24, endIndent: 12),
                      Padding(
                        padding: const EdgeInsets.only(right: 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              initialValue: chapter['chapter_summary'] ?? '',
                              decoration: const InputDecoration(
                                labelText: '章节简述',
                                border: OutlineInputBorder(),
                                filled: true,
                              ),
                              maxLines: 3,
                              onChanged: (val) {
                                _outline['storyline'][idx]['chapter_summary'] = val;
                                _configService.modifySetting(
                                    'ai_novel_creation_storyline',
                                    _outline['storyline']);
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              initialValue: chapter['time_span'] ?? '',
                              style: theme.textTheme.bodyMedium,
                              decoration: InputDecoration(
                                labelText: '时间跨度',
                                hintText: '例如: 半天内、黄昏到午夜...',
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                                isDense: true,
                              ),
                              maxLines: 1,
                              onChanged: (val) {
                                _outline['storyline'][idx]['time_span'] = val;
                                _configService.modifySetting(
                                    'ai_novel_creation_storyline',
                                    _outline['storyline']);
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              initialValue: chapter['setting_update'] ?? '',
                              style: theme.textTheme.bodyMedium,
                              decoration: InputDecoration(
                                labelText: '设定更新',
                                hintText: '例如: 新角色[某某]登场...',
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                                isDense: true,
                              ),
                              maxLines: 2,
                              onChanged: (val) {
                                _outline['storyline'][idx]['setting_update'] = val;
                                _configService.modifySetting(
                                    'ai_novel_creation_storyline',
                                    _outline['storyline']);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon,
      {VoidCallback? onAddPressed}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: theme.textTheme.headlineSmall),
          const Spacer(),
          if (onAddPressed != null)
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加'),
              onPressed: onAddPressed,
            ),
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
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: TextFormField(
            initialValue: char[key] ?? '',
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Theme.of(context).colorScheme.background,
            ),
            maxLines: maxLines,
            onChanged: (val) {
              _outline['main_characters'][idx][key] = val;
              _configService.modifySetting('ai_novel_creation_main_characters',
                  _outline['main_characters']);
            },
          ),
        );
      }

      return Card(
        key: ObjectKey(char),
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: ExpansionTile(
          leading: const Icon(Icons.person_outline),
          title: Text(char['name'] ?? '未命名角色',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(char['characterName'] ?? ''),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buildCharacterField('name', '卡片名称'),
                  buildCharacterField('characterName', '角色名'),
                  buildCharacterField('identity', '身份'),
                  buildCharacterField('appearance', '外貌', maxLines: 2),
                  buildCharacterField('clothing', '服装', maxLines: 2),
                  buildCharacterField('personality', '性格', maxLines: 2),
                  buildCharacterField('status', '状态'),
                  buildCharacterField('other', '其他备注', maxLines: 2),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => _saveCharacterToPresets(char),
                        icon: const Icon(Icons.save_alt, size: 18),
                        label: const Text('存为角色设定'),
                      ),
                      TextButton.icon(
                        onPressed: () => _deleteCharacter(idx),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('删除角色'),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}