// lib/ui/creation/ai_novel_creation/ai_generate_outline_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../base/api_model.dart';
import '../../../base/config_service.dart';
import '../../../base/log/log_service.dart';
import '../../../models/character_card_model.dart';
import '../../../services/task_executor/novel_generator_service.dart';
import 'edit_and_generate_page.dart';

class AiGenerateOutlinePage extends StatefulWidget {
  const AiGenerateOutlinePage({super.key});

  @override
  State<AiGenerateOutlinePage> createState() => _AiGenerateOutlinePageState();
}

class _AiGenerateOutlinePageState extends State<AiGenerateOutlinePage> {
  final _formStateKey = GlobalKey<GenerateOutlineFormState>();

  bool _isGeneratingOutline = false;
  final _configService = ConfigService();

  /// 保存拆分后的大纲数据到配置文件
  Future<void> _saveOutlineToConfig(Map<String, dynamic> outlineData) async {
    await _configService.modifySetting(
      'ai_novel_creation_title',
      outlineData['title'] ?? '',
    );
    await _configService.modifySetting(
      'ai_novel_creation_introduction',
      outlineData['introduction'] ?? '',
    );
    await _configService.modifySetting(
      'ai_novel_creation_background_setting',
      outlineData['background_setting'] ?? '',
    );
    await _configService.modifySetting(
      'ai_novel_creation_writing_style',
      outlineData['writing_style'] ?? '',
    );
    await _configService.modifySetting(
      'ai_novel_creation_main_characters',
      outlineData['main_characters'] ?? [],
    );
    await _configService.modifySetting(
      'ai_novel_creation_storyline',
      outlineData['storyline'] ?? [],
    );
  }

  /// 处理生成大纲和跳转的逻辑
  Future<void> _handleGenerateAndProceed({
    required String storyPrompt,
    required int chapterCount,
    required int wordsPerChapter,
    String? selectedBackground,
    String? selectedStyle,
    List<Map<String, dynamic>>? selectedCharacters,
  }) async {
    setState(() => _isGeneratingOutline = true);
    LogService.instance.info('AI 开始生成小说大纲...');
    try {
      final result = await NovelGeneratorService.instance.generateNovelOutline(
        storyPrompt: storyPrompt,
        chapterCount: chapterCount,
        wordsPerChapter: wordsPerChapter,
        backgroundSetting: selectedBackground,
        writingStyle: null, // 传 null，避免给AI任何文风参考
        mainCharacters: selectedCharacters,
      );
      LogService.instance.success('AI 小说大纲生成成功。');

      final finalOutline = {
        'title': result['title'] ?? '未命名小说',
        'introduction': result['introduction'] ?? '',
        'background_setting':
            selectedBackground ?? result['background_setting'] ?? '',
        'writing_style': selectedStyle ?? (result['writing_style'] ?? ''),
        'main_characters':
            (selectedCharacters != null && selectedCharacters.isNotEmpty)
            ? selectedCharacters
            : result['main_characters'] ?? [],
        'storyline': result['storyline'] ?? [],
      };

      LogService.instance.info('正在保存生成的大纲到配置。..');
      await _saveOutlineToConfig(finalOutline);
      LogService.instance.info('大纲已保存，准备跳转到编辑页面。');

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const EditAndGeneratePage()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI生成大纲失败,请检查接口是否正常工作中...')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingOutline = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('生成大纲'),
        actions: [
          // 将接口设置按钮放在 AppBar 中
          IconButton(
            icon: const Icon(Icons.control_camera),
            tooltip: '接口设置',
            onPressed: _isGeneratingOutline
                ? null
                : () {
                    _showApiSettingsDialog(context);
                  },
          ),
          TextButton.icon(
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('编辑大纲'),
            onPressed: _isGeneratingOutline
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const EditAndGeneratePage(),
                      ),
                    );
                  },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GenerateOutlineForm(
              key: _formStateKey, // 将 key 传递给表单
              isLoading: _isGeneratingOutline,
              onGenerate: _handleGenerateAndProceed,
            ),
          ),
          _buildBottomActionBar(),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton.icon(
          icon: _isGeneratingOutline
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.auto_fix_high),
          label: Text(
            _isGeneratingOutline ? '生成中...' : '生成大纲',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          onPressed: _isGeneratingOutline
              ? null
              : () => _formStateKey.currentState?.triggerGenerate(),
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  // 显示API设置对话框
  void _showApiSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const ApiSettingsDialog(),
    );
  }
}

class ApiSettingsDialog extends StatefulWidget {
  const ApiSettingsDialog({super.key});

  @override
  State<ApiSettingsDialog> createState() => _ApiSettingsDialogState();
}

class _ApiSettingsDialogState extends State<ApiSettingsDialog> {
  final _configService = ConfigService();
  List<ApiModel> _languageApis = [];
  String? _outlineApiId;
  String? _planApiId;
  String? _generateApiId;

  @override
  void initState() {
    super.initState();
    _loadApiData();
  }

  void _loadApiData() {
    final apisJson = _configService.getSetting<List>('languageApis', []);
    _languageApis = apisJson
        .map((json) => ApiModel.fromJson(json as Map<String, dynamic>))
        .toList();

    _outlineApiId = _configService.getSetting<String?>(
      'ai_novel_creation_outline_api_id',
      null,
    );
    _planApiId = _configService.getSetting<String?>(
      'ai_novel_creation_plan_api_id',
      null,
    );
    _generateApiId = _configService.getSetting<String?>(
      'ai_novel_creation_generate_api_id',
      null,
    );

    // 验证已保存的ID是否存在，如果不存在则重置为null（默认）
    if (_outlineApiId != null &&
        !_languageApis.any((api) => api.id == _outlineApiId)) {
      _outlineApiId = null;
    }
    if (_planApiId != null &&
        !_languageApis.any((api) => api.id == _planApiId)) {
      _planApiId = null;
    }
    if (_generateApiId != null &&
        !_languageApis.any((api) => api.id == _generateApiId)) {
      _generateApiId = null;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.control_camera),
          SizedBox(width: 8),
          Text('接口设置'),
        ],
      ),
      content: SingleChildScrollView(
        // 使用 SizedBox 给内容一个固定的宽度，从而放大整个对话框
        child: SizedBox(
          width: 450, // 您可以根据需要调整这个宽度值
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '为不同生成阶段指定语言模型接口',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              _buildApiSelector(
                title: '生成大纲',
                icon: Icons.create_new_folder_outlined,
                selectedApiId: _outlineApiId,
                onChanged: (id) {
                  setState(() => _outlineApiId = id);
                  _configService.modifySetting(
                    'ai_novel_creation_outline_api_id',
                    id,
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildApiSelector(
                title: '章节规划',
                icon: Icons.view_week_outlined,
                selectedApiId: _planApiId,
                onChanged: (id) {
                  setState(() => _planApiId = id);
                  _configService.modifySetting(
                    'ai_novel_creation_plan_api_id',
                    id,
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildApiSelector(
                title: '生成正文',
                icon: Icons.drive_file_rename_outline,
                selectedApiId: _generateApiId,
                onChanged: (id) {
                  setState(() => _generateApiId = id);
                  _configService.modifySetting(
                    'ai_novel_creation_generate_api_id',
                    id,
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildApiSelector({
    required String title,
    required IconData icon,
    required String? selectedApiId,
    required ValueChanged<String?> onChanged,
  }) {
    final theme = Theme.of(context);
    final activeApiId = _configService.getSetting<String?>(
      'activeLanguageApiId',
      null,
    );
    String defaultApiName = '未设置默认接口';
    if (activeApiId != null) {
      try {
        final activeApi = _languageApis.firstWhere(
          (api) => api.id == activeApiId,
        );
        defaultApiName = '默认 (${activeApi.name})';
      } catch (e) {
        defaultApiName = '默认 (接口已删除)';
      }
    }

    return DropdownButtonFormField<String?>(
      initialValue: selectedApiId,
      decoration: InputDecoration(
        labelText: title,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      onChanged: onChanged,
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(defaultApiName)),
        ..._languageApis.map((api) {
          return DropdownMenuItem<String?>(
            value: api.id,
            child: Text(api.name),
          );
        }),
      ],
    );
  }
}

class GenerateOutlineForm extends StatefulWidget {
  final bool isLoading;
  final Future<void> Function({
    required String storyPrompt,
    required int chapterCount,
    required int wordsPerChapter,
    String? selectedBackground,
    String? selectedStyle,
    List<Map<String, dynamic>>? selectedCharacters,
  })
  onGenerate;

  const GenerateOutlineForm({
    super.key,
    required this.isLoading,
    required this.onGenerate,
  });

  @override
  State<GenerateOutlineForm> createState() => GenerateOutlineFormState();
}

class GenerateOutlineFormState extends State<GenerateOutlineForm> {
  final _formKey = GlobalKey<FormState>();
  final _configService = ConfigService();

  final _storyPromptController = TextEditingController();
  final _chapterCountController = TextEditingController();
  final _wordsPerChapterController = TextEditingController();

  List<Map<String, dynamic>> _backgroundCards = [];
  List<Map<String, dynamic>> _styleCards = [];
  List<CharacterCard> _characterCards = [];

  String? _selectedBackgroundId;
  String? _selectedStyleId;
  List<String> _selectedCharacterIds = [];

  @override
  void initState() {
    super.initState();
    _loadFormData();
    _addListeners();
    _loadCardData();
  }

  void _loadCardData() {
    setState(() {
      _backgroundCards = List<Map<String, dynamic>>.from(
        _configService.getSetting('writing_background_cards', []),
      );
      _styleCards = List<Map<String, dynamic>>.from(
        _configService.getSetting('writing_style_cards', []),
      );

      final charList = List<Map<String, dynamic>>.from(
        _configService.getSetting('drawing_character_cards', []),
      );
      _characterCards = charList.map((e) => CharacterCard.fromJson(e)).toList();

      _selectedBackgroundId = _configService.getSetting<String?>(
        'active_writing_background_card_id',
        null,
      );
      _selectedStyleId = _configService.getSetting<String?>(
        'active_writing_style_card_id',
        null,
      );
      _selectedCharacterIds = List<String>.from(
        _configService.getSetting<List>(
          'active_drawing_character_card_ids',
          [],
        ),
      );

      if (_selectedBackgroundId != null &&
          !_backgroundCards.any((c) => c['id'] == _selectedBackgroundId)) {
        _selectedBackgroundId = null;
      }
      if (_selectedStyleId != null &&
          !_styleCards.any((c) => c['id'] == _selectedStyleId)) {
        _selectedStyleId = null;
      }
      _selectedCharacterIds.removeWhere(
        (id) => !_characterCards.any((c) => c.id == id),
      );
    });
  }

  void _loadFormData() {
    _storyPromptController.text = _configService.getSetting<String>(
      'ai_novel_creation_prompt',
      '',
    );
    _chapterCountController.text = _configService
        .getSetting<int>('ai_novel_creation_chapter_count', 2)
        .toString();
    _wordsPerChapterController.text = _configService
        .getSetting<int>('ai_novel_creation_words_per_chapter', 1500)
        .toString();
  }

  void _addListeners() {
    _storyPromptController.addListener(() {
      _configService.modifySetting(
        'ai_novel_creation_prompt',
        _storyPromptController.text,
      );
    });
    _chapterCountController.addListener(() {
      final count = int.tryParse(_chapterCountController.text) ?? 2;
      _configService.modifySetting('ai_novel_creation_chapter_count', count);
    });
    _wordsPerChapterController.addListener(() {
      final words = int.tryParse(_wordsPerChapterController.text) ?? 1500;
      _configService.modifySetting(
        'ai_novel_creation_words_per_chapter',
        words,
      );
    });
  }

  void triggerGenerate() {
    if (_formKey.currentState!.validate()) {
      LogService.instance.info('触发生成大纲操作，正在收集表单数据...');
      String? selectedBackground;
      if (_selectedBackgroundId != null) {
        selectedBackground = _backgroundCards.firstWhere(
          (c) => c['id'] == _selectedBackgroundId,
        )['content'];
      }

      String? selectedStyle;
      if (_selectedStyleId != null) {
        selectedStyle = _styleCards.firstWhere(
          (c) => c['id'] == _selectedStyleId,
        )['content'];
      }

      List<Map<String, dynamic>>? selectedCharacters;
      if (_selectedCharacterIds.isNotEmpty) {
        selectedCharacters = _characterCards
            .where((c) => _selectedCharacterIds.contains(c.id))
            .map((c) => c.toJson())
            .toList();
      }

      widget.onGenerate(
        storyPrompt: _storyPromptController.text,
        chapterCount: int.parse(_chapterCountController.text),
        wordsPerChapter: int.parse(_wordsPerChapterController.text),
        selectedBackground: selectedBackground,
        selectedStyle: selectedStyle,
        selectedCharacters: selectedCharacters,
      );
    }
  }

  @override
  void dispose() {
    _storyPromptController.dispose();
    _chapterCountController.dispose();
    _wordsPerChapterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              color: Theme.of(context).colorScheme.primary,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '故事灵感',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '在这里输入故事的核心创意、关键情节，或只是一个简单的想法。AI将基于此为您构建整个故事大纲。',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _storyPromptController,
                      autofocus: true,
                      maxLines: 15,
                      decoration: const InputDecoration(
                        hintText:
                            '例如：在一个赛博朋克都市，一位失忆的侦探必须找回自己的过去，同时揭露一个足以颠覆整个城市的巨大阴谋。',
                        border: OutlineInputBorder(),
                        filled: true,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入故事描述';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildSingleChoiceChipSelector(
              icon: Icons.public,
              title: '背景设定',
              cards: _backgroundCards,
              selectedId: _selectedBackgroundId,
              onChanged: (id) {
                setState(() => _selectedBackgroundId = id);
                _configService.modifySetting(
                  'active_writing_background_card_id',
                  id,
                );
              },
            ),
            const SizedBox(height: 16),
            _buildSingleChoiceChipSelector(
              icon: Icons.brush,
              title: '文风设定',
              cards: _styleCards,
              selectedId: _selectedStyleId,
              onChanged: (id) {
                setState(() => _selectedStyleId = id);
                _configService.modifySetting(
                  'active_writing_style_card_id',
                  id,
                );
              },
            ),
            const SizedBox(height: 16),
            _buildCharacterSelector(),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.format_list_numbered),
                      title: Text(
                        '篇幅设定',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('设置章节和字数'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _chapterCountController,
                            decoration: const InputDecoration(
                              labelText: '章节数',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.library_books_outlined),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: (value) {
                              if (value == null ||
                                  int.tryParse(value) == null ||
                                  int.parse(value) <= 0) {
                                return '请输入有效数字';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _wordsPerChapterController,
                            decoration: const InputDecoration(
                              labelText: '每章字数',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.text_fields_outlined),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: (value) {
                              if (value == null ||
                                  int.tryParse(value) == null ||
                                  int.parse(value) <= 0) {
                                return '请输入有效数字';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleChoiceChipSelector({
    required IconData icon,
    required String title,
    required List<Map<String, dynamic>> cards,
    required String? selectedId,
    required ValueChanged<String?> onChanged,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(icon),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('从预设中选择或由AI自动生成'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: [
                  ChoiceChip(
                    label: const Text('由AI自动生成'),
                    selected: selectedId == null,
                    onSelected: (isSelected) {
                      if (isSelected) {
                        onChanged(null);
                      }
                    },
                  ),
                  ...cards.map((card) {
                    return ChoiceChip(
                      label: Text(card['name']),
                      selected: selectedId == card['id'],
                      onSelected: (isSelected) {
                        if (isSelected) {
                          onChanged(card['id']);
                        }
                      },
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCharacterSelector() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              leading: Icon(Icons.people_alt_outlined),
              title: Text(
                '主要角色',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('选择参与故事的核心人物'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: [
                  FilterChip(
                    label: const Text('由AI自动生成'),
                    selected: _selectedCharacterIds.isEmpty,
                    onSelected: (isSelected) {
                      if (isSelected) {
                        setState(() {
                          _selectedCharacterIds.clear();
                          _configService.modifySetting(
                            'active_drawing_character_card_ids',
                            _selectedCharacterIds,
                          );
                        });
                      }
                    },
                  ),
                  ..._characterCards.map((card) {
                    final isSelected = _selectedCharacterIds.contains(card.id);
                    return FilterChip(
                      label: Text(card.name),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedCharacterIds.add(card.id);
                          } else {
                            _selectedCharacterIds.remove(card.id);
                          }
                          _configService.modifySetting(
                            'active_drawing_character_card_ids',
                            _selectedCharacterIds,
                          );
                        });
                      },
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
