// lib/ui/bookshelf/ai_novel_creation/ai_generate_outline_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  bool _isGeneratingOutline = false;
  final _configService = ConfigService();

  /// 保存拆分后的大纲数据到配置文件
  Future<void> _saveOutlineToConfig(Map<String, dynamic> outlineData) async {
    await _configService.modifySetting('ai_novel_creation_title', outlineData['title'] ?? '');
    await _configService.modifySetting('ai_novel_creation_background_setting', outlineData['background_setting'] ?? '');
    await _configService.modifySetting('ai_novel_creation_writing_style', outlineData['writing_style'] ?? '');
    await _configService.modifySetting('ai_novel_creation_main_characters', outlineData['main_characters'] ?? []);
    await _configService.modifySetting('ai_novel_creation_storyline', outlineData['storyline'] ?? []);
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
        writingStyle: selectedStyle,
        mainCharacters: selectedCharacters,
      );
      LogService.instance.success('AI 小说大纲生成成功。');

      // 关键点：整合用户选择和AI生成的结果
      final finalOutline = {
        'title': result['title'] ?? '未命名小说',
        'background_setting': selectedBackground ?? result['background_setting'] ?? '',
        'writing_style': selectedStyle ?? result['writing_style'] ?? '',
        'main_characters': (selectedCharacters != null && selectedCharacters.isNotEmpty) ? selectedCharacters : result['main_characters'] ?? [],
        'storyline': result['storyline'] ?? [],
      };
      
      LogService.instance.info('正在保存生成的大纲到配置...');
      await _saveOutlineToConfig(finalOutline);
      LogService.instance.info('大纲已保存，准备跳转到编辑页面。');

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const EditAndGeneratePage(),
          ),
        );
      }
    } catch (e, s) {
      LogService.instance.error('AI 生成大纲失败', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成大纲失败: $e')),
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
        title: const Text('AI 创作小说：第一步'),
      ),
      body: GenerateOutlineForm(
        isLoading: _isGeneratingOutline,
        onGenerate: _handleGenerateAndProceed,
      ),
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
  }) onGenerate;

  const GenerateOutlineForm({
    super.key,
    required this.isLoading,
    required this.onGenerate,
  });

  @override
  State<GenerateOutlineForm> createState() => _GenerateOutlineFormState();
}

class _GenerateOutlineFormState extends State<GenerateOutlineForm> {
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
    LogService.instance.info('加载写作相关的卡片数据...');
    setState(() {
      _backgroundCards = List<Map<String, dynamic>>.from(_configService.getSetting('writing_background_cards', []));
      _styleCards = List<Map<String, dynamic>>.from(_configService.getSetting('writing_style_cards', []));
      
      final charList = List<Map<String, dynamic>>.from(_configService.getSetting('drawing_character_cards', []));
      _characterCards = charList.map((e) => CharacterCard.fromJson(e)).toList();

      // [FINAL MODIFICATION] 使用写作和绘画模块共用的配置项
      _selectedBackgroundId = _configService.getSetting<String?>('active_writing_background_card_id', null);
      _selectedStyleId = _configService.getSetting<String?>('active_writing_style_card_id', null);
      // 直接沿用绘画模块的激活角色列表，实现完全同步
      _selectedCharacterIds = List<String>.from(_configService.getSetting<List>('active_drawing_character_card_ids', []));

      // 确保选中的ID在列表中存在，否则置为null
      if (_selectedBackgroundId != null && !_backgroundCards.any((c) => c['id'] == _selectedBackgroundId)) {
        _selectedBackgroundId = null;
      }
      if (_selectedStyleId != null && !_styleCards.any((c) => c['id'] == _selectedStyleId)) {
        _selectedStyleId = null;
      }
      _selectedCharacterIds.removeWhere((id) => !_characterCards.any((c) => c.id == id));
    });
  }

  void _loadFormData() {
    LogService.instance.info('从配置加载表单历史数据...');
    _storyPromptController.text = _configService.getSetting<String>('ai_novel_creation_prompt', '');
    _chapterCountController.text = _configService.getSetting<int>('ai_novel_creation_chapter_count', 2).toString();
    _wordsPerChapterController.text = _configService.getSetting<int>('ai_novel_creation_words_per_chapter', 1500).toString();
  }

  void _addListeners() {
    _storyPromptController.addListener(() {
      _configService.modifySetting('ai_novel_creation_prompt', _storyPromptController.text);
    });
    _chapterCountController.addListener(() {
      final count = int.tryParse(_chapterCountController.text) ?? 2;
      _configService.modifySetting('ai_novel_creation_chapter_count', count);
    });
    _wordsPerChapterController.addListener(() {
      final words = int.tryParse(_wordsPerChapterController.text) ?? 1500;
      _configService.modifySetting('ai_novel_creation_words_per_chapter', words);
    });
  }

  void _triggerGenerate() {
    if (_formKey.currentState!.validate()) {
      LogService.instance.info('触发生成大纲操作，正在收集表单数据...');
      // 获取选定的背景设定内容
      String? selectedBackground;
      if (_selectedBackgroundId != null) {
        selectedBackground = _backgroundCards.firstWhere((c) => c['id'] == _selectedBackgroundId)['content'];
      }

      // 获取选定的文风设定内容
      String? selectedStyle;
      if (_selectedStyleId != null) {
        selectedStyle = _styleCards.firstWhere((c) => c['id'] == _selectedStyleId)['content'];
      }

      // 获取选定的角色卡片内容
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
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. 你希望写一个什么样的故事？', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextFormField(
              controller: _storyPromptController,
              autofocus: true,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '例如：一个关于赛博朋克侦探在反乌托邦城市中寻找失落机器人的故事...',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入故事描述';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            _buildCardSelector(
              title: '2. 选择一个背景设定（可选）',
              cards: _backgroundCards,
              selectedId: _selectedBackgroundId,
              onChanged: (id) {
                setState(() => _selectedBackgroundId = id);
                _configService.modifySetting('active_writing_background_card_id', id);
              },
            ),
            const SizedBox(height: 24),
            _buildCardSelector(
              title: '3. 选择一种文风（可选）',
              cards: _styleCards,
              selectedId: _selectedStyleId,
              onChanged: (id) {
                setState(() => _selectedStyleId = id);
                _configService.modifySetting('active_writing_style_card_id', id);
              },
            ),
            const SizedBox(height: 24),
            _buildCharacterSelector(),
            const SizedBox(height: 24),
            Text('5. 设置章节和字数', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _chapterCountController,
                    decoration: const InputDecoration(
                      labelText: '章节数',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      if (value == null || int.tryParse(value) == null || int.parse(value) <= 0) {
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
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      if (value == null || int.tryParse(value) == null || int.parse(value) <= 0) {
                        return '请输入有效数字';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: widget.isLoading ? null : _triggerGenerate,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                icon: widget.isLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_fix_high),
                label: Text(widget.isLoading ? '生成中...' : '生成大纲', style: const TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.isLoading
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const EditAndGeneratePage(),
                          ),
                        );
                      },
                icon: const Icon(Icons.edit_note),
                label: const Text('预览和编辑上次的大纲'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardSelector({
    required String title,
    required List<Map<String, dynamic>> cards,
    required String? selectedId,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          value: selectedId,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          hint: const Text('由AI自动生成'),
          isExpanded: true,
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('由AI自动生成'),
            ),
            ...cards.map((card) {
              return DropdownMenuItem<String>(
                value: card['id'],
                child: Tooltip(
                  message: card['content'],
                  child: Text(
                    card['name'],
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }).toList(),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildCharacterSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('4. 选择主要角色（可选）', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: [
              FilterChip(
                label: const Text('由AI自动生成'),
                selectedColor: Theme.of(context).primaryColor,
                labelStyle: TextStyle(
                  color: _selectedCharacterIds.isEmpty ? Colors.white : null,
                ),
                selected: _selectedCharacterIds.isEmpty,
                onSelected: (isSelected) {
                  if (isSelected) {
                    setState(() {
                      _selectedCharacterIds.clear();
                      // [FINAL MODIFICATION] 直接更新绘画模块的激活列表
                      _configService.modifySetting('active_drawing_character_card_ids', _selectedCharacterIds);
                    });
                  }
                },
              ),
              // --- 遍历并显示所有可用的角色预设 ---
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
                      // [FINAL MODIFICATION] 直接更新绘画模块的激活列表
                      _configService.modifySetting('active_drawing_character_card_ids', _selectedCharacterIds);
                    });
                  },
                );
              }).toList(),
            ],
          ),
        ),
      ],
    );
  }
}