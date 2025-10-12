//lib/ui/bookshelf/ai_novel_creation/edit_and_generate_page.dart

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../base/config_service.dart';
import '../../../base/default_configs.dart';
import '../../../base/log/log_service.dart';
import '../../../models/character_card_model.dart';
import 'novel_generation_progress_page.dart'; // 导入新页面

class EditAndGeneratePage extends StatefulWidget {
  const EditAndGeneratePage({super.key});

  @override
  State<EditAndGeneratePage> createState() => EditAndGeneratePageState();
}

class EditAndGeneratePageState extends State<EditAndGeneratePage> {
  final _configService = ConfigService();
  late Map<String, dynamic> _outline;
  // 移除 _isGenerating, _progress, _statusMessage
  bool _isLoading = true;
  
  late TextEditingController _titleController;

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
    _titleController.text = _outline['title'];
    if (mounted) setState(() => _isLoading = false);
  }

  // startGeneration, _createLines, _saveBook 方法已移动到新页面，在此处删除
  
  void navigateToGenerationPage() {
    // 在导航前，确保所有最新的修改都已保存（尽管我们的实现是实时保存的）
    _configService.modifySetting('ai_novel_creation_title', _titleController.text);
    _outline['title'] = _titleController.text;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NovelGenerationProgressPage(outline: _outline),
      ),
    ).then((success) {
      // 当生成页面关闭后，如果返回的是 true (代表成功)，则关闭当前编辑页，返回书架
      if (success == true && mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  // ... (保留 _saveCharacterToPresets, _addCharacter, _deleteCharacter, _addChapter, _deleteChapter 方法)
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
                _configService.modifySetting(
                    'ai_novel_creation_main_characters', _outline['main_characters']);
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
        "chapter_title": "新章节",
        "chapter_summary": "请填写本章的简要描述...",
      };
      (_outline['storyline'] as List).add(newChapter);
    });
    _configService.modifySetting(
        'ai_novel_creation_storyline', _outline['storyline']);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已添加一个新章节。'), duration: Duration(seconds: 2)),
    );
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
                });
                _configService.modifySetting(
                    'ai_novel_creation_storyline', _outline['storyline']);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('章节已删除。'), duration: Duration(seconds: 2)),
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
        title: const Text('故事大纲'),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
              onPressed: navigateToGenerationPage, // 修改 onPressed
              icon: const Icon(Icons.auto_awesome),
              label: const Text('开始生成小说'),
            ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    
    // 移除 if (_isGenerating) {...} 分支
    
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold);

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
                      // 实时保存标题
                      _configService.modifySetting('ai_novel_creation_title', newValue);
                    },
                  ),
                ),
                Text('》', style: titleStyle),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ... (所有 _build... 卡片和列表的UI代码保持不变)
          _buildStaticEditableCard(
            '背景设定',
            Icons.public,
            _outline['background_setting'],
            'ai_novel_creation_background_setting',
            maxLines: 5,
          ),
          _buildStaticEditableCard(
            '文风设定',
            Icons.brush,
            _outline['writing_style'],
            'ai_novel_creation_writing_style',
            maxLines: 3,
          ),
          
          _buildSectionHeader(theme, '主要角色', Icons.people_alt_outlined, onAddPressed: _addCharacter),
          ..._buildCharacterCards(),
          
          const SizedBox(height: 16),
          _buildSectionHeader(theme, '故事线', Icons.timeline, onAddPressed: _addChapter),
          const SizedBox(height: 8),
          ...(_outline['storyline'] as List).asMap().entries.map((entry) {
            int idx = entry.key;
            var chapter = entry.value;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(child: Text('${idx + 1}')),
                      title: TextFormField(
                        initialValue: chapter['chapter_title'] ?? '',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        decoration: const InputDecoration.collapsed(hintText: '章节标题'),
                        onChanged: (val) {
                          _outline['storyline'][idx]['chapter_title'] = val;
                          _configService.modifySetting(
                              'ai_novel_creation_storyline',
                              _outline['storyline']);
                        },
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '删除本章',
                        onPressed: () => _deleteChapter(idx),
                      ),
                      contentPadding: const EdgeInsets.only(left: 4),
                    ),
                    const Divider(height: 24, endIndent: 12),
                    Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: TextFormField(
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
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
  
  // ... (保留 _buildStaticEditableCard, _buildSectionHeader, _buildCharacterCards 方法)
   Widget _buildStaticEditableCard(
    String title,
    IconData icon,
    String initialValue,
    String configKey, {
    int maxLines = 1,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(icon),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: initialValue,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                filled: true,
              ),
              maxLines: maxLines,
              onChanged: (newValue) {
                _configService.modifySetting(configKey, newValue);
                _outline[configKey.replaceFirst('ai_novel_creation_', '')] = newValue;
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon, {required VoidCallback onAddPressed}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: theme.textTheme.headlineSmall),
          const Spacer(),
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
              _configService.modifySetting(
                  'ai_novel_creation_main_characters',
                  _outline['main_characters']);
            },
          ),
        );
      }

      return Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: ExpansionTile(
          leading: const Icon(Icons.person_outline),
          title: Text(char['name'] ?? '未命名角色', style: const TextStyle(fontWeight: FontWeight.bold)),
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