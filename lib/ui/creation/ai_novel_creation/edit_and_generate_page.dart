// lib/ui/creation/ai_novel_creation/edit_and_generate_page.dart

import 'dart:async';
import 'dart:convert';
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
  late TextEditingController _introductionController;
  final Set<int> _selectedChapterIndices = {};

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _introductionController = TextEditingController();
    loadOutlineFromConfig();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _introductionController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // 防抖保存的辅助方法
  void _debounceSave(VoidCallback saveAction) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      saveAction();
    });
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
    var loadedIntro =
        _configService.getSetting<String>('ai_novel_creation_introduction', '');

    if (loadedStoryline.isEmpty && loadedTitle.isEmpty) {
      LogService.instance.warn('未找到现有大纲，加载默认大纲。');
      _outline = {
        'title': appDefaultConfigs['ai_novel_creation_title'],
        'introduction': appDefaultConfigs['ai_novel_creation_introduction'],
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
        'introduction': loadedIntro,
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
    _introductionController.text = _outline['introduction'] ?? '';
    if (mounted) setState(() => _isLoading = false);
  }

  // 获取当前大纲的完整快照
  Map<String, dynamic> _getCurrentOutlineSnapshot() {
    _outline['title'] = _titleController.text;
    _outline['introduction'] = _introductionController.text;
    return jsonDecode(jsonEncode(_outline));
  }

  // --- 存档功能 ---
  void _showSaveArchiveDialog() {
    final nameController = TextEditingController();
    nameController.text = _titleController.text;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        title: const Text('保存大纲存档'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width, 
          child: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: '存档名称',
              hintText: '请输入存档名称以便识别',
              border: OutlineInputBorder(),
              filled: true, // 稍微美化一下输入框
            ),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('存档名称不能为空')),
                );
                return;
              }

              final currentSnapshot = _getCurrentOutlineSnapshot();
              final newArchive = {
                'id': const Uuid().v4(),
                'name': name,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
                'data': currentSnapshot,
              };

              final List<dynamic> currentList =
                  _configService.getSetting<List>('novel_outline_list', []);
              final newList = List<Map<String, dynamic>>.from(currentList);
              newList.insert(0, newArchive);

              await _configService.modifySetting('novel_outline_list', newList);

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('大纲 "$name" 已保存')),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showSwitchArchiveDialog() {
      final List<dynamic> rawList =
          _configService.getSetting<List>('novel_outline_list', []);
      final archives = List<Map<String, dynamic>>.from(rawList);

      if (archives.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无已保存的大纲存档')),
        );
        return;
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          // 设置 insetPadding，让列表更宽
          insetPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          title: const Text('切换大纲存档'),
          // 使用 SizedBox 配合 MediaQuery 获取屏幕宽度
          content: SizedBox(
            width: MediaQuery.of(context).size.width,
            child: ListView.builder(
              shrinkWrap: true,
              // 增加 itemCount 限制，防止列表过长导致溢出，或者保持默认让其滚动
              itemCount: archives.length,
              itemBuilder: (context, index) {
                final archive = archives[index];
                final date = DateTime.fromMillisecondsSinceEpoch(
                    archive['timestamp'] ?? 0);
                return Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8.0),
                      title: Text(archive['name'] ?? '未命名存档',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('保存时间: ${date.toString().substring(0, 16)}'),
                      leading: const Icon(Icons.description_outlined),
                      onTap: () {
                        _confirmLoadArchive(archive);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.grey),
                        onPressed: () async {
                          final confirmDelete = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                    title: const Text('删除存档'),
                                    content: Text('确定要删除 "${archive['name']}" 吗？'),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(c, false),
                                          child: const Text('取消')),
                                      TextButton(
                                          onPressed: () => Navigator.pop(c, true),
                                          child: const Text('删除')),
                                    ],
                                  ));

                          if (confirmDelete == true) {
                            setState(() {
                              archives.removeAt(index);
                            });
                            await _configService.modifySetting(
                                'novel_outline_list', archives);
                            // 如果删除后列表为空，关闭对话框
                            if (archives.isEmpty && mounted) {
                              Navigator.pop(context); 
                            } else if (mounted) {
                              Navigator.pop(context);
                              _showSwitchArchiveDialog(); // 重新打开以刷新列表
                            }
                          }
                        },
                      ),
                    ),
                    const Divider(height: 1), // 添加分割线让列表更清晰
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    }

  void _confirmLoadArchive(Map<String, dynamic> archive) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认覆盖'),
        content: Text(
            '加载存档 "${archive['name']}" 将覆盖当前正在编辑的内容且无法撤销。\n确定要继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pop(context);
              _loadArchiveData(archive['data']);
            },
            child: const Text('确认加载'),
          ),
        ],
      ),
    );
  }

  void _loadArchiveData(Map<String, dynamic> data) async {
    setState(() => _isLoading = true);

    _outline = jsonDecode(jsonEncode(data));
    _titleController.text = _outline['title'] ?? '';
    _introductionController.text = _outline['introduction'] ?? '';
    _resyncChapterIds();

    await _configService.modifySetting(
        'ai_novel_creation_title', _outline['title']);
    await _configService.modifySetting(
        'ai_novel_creation_introduction', _outline['introduction']);
    await _configService.modifySetting('ai_novel_creation_background_setting',
        _outline['background_setting']);
    await _configService.modifySetting(
        'ai_novel_creation_writing_style', _outline['writing_style']);
    await _configService.modifySetting(
        'ai_novel_creation_main_characters', _outline['main_characters']);
    await _configService.modifySetting(
        'ai_novel_creation_storyline', _outline['storyline']);

    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('存档已加载并刷新页面')),
      );
    }
  }

  void navigateToGenerationPage() {
    _debounce?.cancel();
    _configService.modifySetting(
        'ai_novel_creation_title', _titleController.text);
    _outline['title'] = _titleController.text;

    _configService.modifySetting(
        'ai_novel_creation_introduction', _introductionController.text);
    _outline['introduction'] = _introductionController.text;

    _showGenerationModeDialog();
  }

  void _showGenerationModeDialog() {
    bool? selectedMode;
    final parentContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.auto_awesome),
              SizedBox(width: 8),
              Text('选择生成模式'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '请选择小说生成方式：',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              RadioListTile<bool>(
                title: const Text('并行生成小说'),
                subtitle: const Text('同时生成所有章节，速度更快'),
                value: true,
                groupValue: selectedMode,
                onChanged: (value) {
                  setDialogState(() => selectedMode = value);
                },
              ),
              RadioListTile<bool>(
                title: const Text('线性生成小说'),
                subtitle: const Text('按顺序生成章节，避免内容冲突'),
                value: false,
                groupValue: selectedMode,
                onChanged: (value) {
                  setDialogState(() => selectedMode = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: selectedMode == null
                  ? null
                  : () {
                      Navigator.of(dialogContext).pop();
                      Navigator.of(parentContext)
                          .push(
                        MaterialPageRoute(
                          builder: (context) => NovelGenerationProgressPage(
                            outline: _outline,
                            isLinearMode: selectedMode == false,
                          ),
                        ),
                      )
                          .then((success) {
                        if (success == true && mounted) {
                          Navigator.of(parentContext).pop();
                        }
                      });
                    },
              child: const Text('开始生成'),
            ),
          ],
        ),
      ),
    );
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
            final oldChapter =
                _outline['storyline'][indexToUpdate] as Map<String, dynamic>;
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
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.save_as),
              tooltip: '保存当前大纲存档',
              onPressed: _showSaveArchiveDialog,
            ),
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: '加载/切换大纲存档',
              onPressed: _showSwitchArchiveDialog,
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
                      setState(() {
                        _outline['title'] = newValue;
                      });
                      _debounceSave(() => _configService.modifySetting(
                          'ai_novel_creation_title', newValue));
                    },
                  ),
                ),
                Text('》', style: titleStyle),
              ],
            ),
          ),
          _buildSectionHeader(theme, '小说简介', Icons.info_outline),
          Card(
            margin: const EdgeInsets.only(top: 8.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextFormField(
                controller: _introductionController,
                decoration: const InputDecoration(
                  hintText: '请输入小说简介...',
                  border: OutlineInputBorder(),
                  filled: true,
                ),
                maxLines: 3,
                onChanged: (newValue) {
                  setState(() {
                    _outline['introduction'] = newValue;
                  });
                  _debounceSave(() => _configService.modifySetting(
                      'ai_novel_creation_introduction', newValue));
                },
              ),
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
                  setState(() {
                    _outline['background_setting'] = newValue;
                  });
                  _debounceSave(() => _configService.modifySetting(
                      'ai_novel_creation_background_setting', newValue));
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
                  setState(() {
                    _outline['writing_style'] = newValue;
                  });
                  _debounceSave(() => _configService.modifySetting(
                      'ai_novel_creation_writing_style', newValue));
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
              color: isSelected
                  ? theme.colorScheme.primaryContainer.withOpacity(0.3)
                  : null,
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
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // 阈值设为400，适配一般手机竖屏
                          final bool isCompact = constraints.maxWidth < 320;

                          // 序号组件
                          Widget leadingWidget = Padding(
                            padding: const EdgeInsets.only(right: 12.0),
                            child: CircleAvatar(child: Text('${idx + 1}')),
                          );

                          // 标题输入组件
                          Widget titleWidget = TextFormField(
                            key: ValueKey('chapter_title_$idx'), // 保持状态
                            initialValue: chapter['chapter_title'] ?? '',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                            decoration: const InputDecoration(
                              hintText: '章节标题',
                              isDense: true,
                              border: InputBorder.none,
                            ),
                            onChanged: (val) {
                              setState(() {
                                _outline['storyline'][idx]['chapter_title'] =
                                    val;
                              });
                              _debounceSave(() => _configService.modifySetting(
                                  'ai_novel_creation_storyline',
                                  _outline['storyline']));
                            },
                          );

                          // 按钮组组件
                          Widget actionButtons = Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
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
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                                onPressed: idx == 0
                                    ? null
                                    : () => _moveChapter(idx, idx - 1),
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_downward),
                                tooltip: '下移',
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                                onPressed: idx == storylineList.length - 1
                                    ? null
                                    : () => _moveChapter(idx, idx + 1),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: '删除本章',
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                                onPressed: () => _deleteChapter(idx),
                              ),
                            ],
                          );

                          if (isCompact) {
                            // 手机/窄屏：两行布局
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    leadingWidget,
                                    Expanded(child: titleWidget),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Spacer(),
                                    actionButtons,
                                  ],
                                ),
                              ],
                            );
                          } else {
                            // 宽屏：一行布局 (原样)
                            return Row(
                              children: [
                                leadingWidget,
                                Expanded(child: titleWidget),
                                const SizedBox(width: 8),
                                actionButtons,
                              ],
                            );
                          }
                        },
                      ),
                      const Divider(height: 24),
                      Padding(
                        padding: const EdgeInsets.only(right: 0),
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
                              maxLines: 5,
                              onChanged: (val) {
                                setState(() {
                                  _outline['storyline'][idx]
                                      ['chapter_summary'] = val;
                                });
                                _debounceSave(() => _configService.modifySetting(
                                    'ai_novel_creation_storyline',
                                    _outline['storyline']));
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
                                fillColor: theme.colorScheme.surfaceVariant
                                    .withOpacity(0.3),
                                isDense: true,
                              ),
                              maxLines: 1,
                              onChanged: (val) {
                                setState(() {
                                  _outline['storyline'][idx]['time_span'] = val;
                                });
                                _debounceSave(() => _configService.modifySetting(
                                    'ai_novel_creation_storyline',
                                    _outline['storyline']));
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
                                fillColor: theme.colorScheme.surfaceVariant
                                    .withOpacity(0.3),
                                isDense: true,
                              ),
                              maxLines: 2,
                              onChanged: (val) {
                                setState(() {
                                  _outline['storyline'][idx]['setting_update'] =
                                      val;
                                });
                                _debounceSave(() => _configService.modifySetting(
                                    'ai_novel_creation_storyline',
                                    _outline['storyline']));
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

      Widget buildCharacterField(String key, String label, {int maxLines = 1}) {
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
              setState(() {
                _outline['main_characters'][idx][key] = val;
              });
              _debounceSave(() => _configService.modifySetting(
                  'ai_novel_creation_main_characters',
                  _outline['main_characters']));
            },
          ),
        );
      }

      return Card(
        key: ObjectKey(char),
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: ExpansionTile(
          title: Text(_outline['main_characters'][idx]['name'] ?? '未命名角色',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle:
              Text(_outline['main_characters'][idx]['characterName'] ?? ''),
          leading: const Icon(Icons.person_outline),
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