// lib/ui/bookshelf/ai_novel_creation/ai_generate_outline_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../base/config_service.dart';
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
  }) async {
    setState(() => _isGeneratingOutline = true);
    try {
      final result = await NovelGeneratorService.instance.generateNovelOutline(
        storyPrompt: storyPrompt,
        chapterCount: chapterCount,
        wordsPerChapter: wordsPerChapter,
      );
      
      // 关键点：先保存配置
      await _saveOutlineToConfig(result);

      // 关键点：保存成功后，再跳转到新的编辑页面
      if (mounted) {
        // 使用 pushReplacement 替换当前页面，这样编辑页返回时会直接回到书架
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const EditAndGeneratePage(),
          ),
        );
      }
    } catch (e) {
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

  @override
  void initState() {
    super.initState();
    _loadFormData();
    _addListeners();
  }

  void _loadFormData() {
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
      widget.onGenerate(
        storyPrompt: _storyPromptController.text,
        chapterCount: int.parse(_chapterCountController.text),
        wordsPerChapter: int.parse(_wordsPerChapterController.text),
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
              maxLines: 8,
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
            Text('2. 设置章节和字数', style: Theme.of(context).textTheme.titleMedium),
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
            const SizedBox(height: 16), // 新增：为预览按钮留出空间
            // 新增：直接预览/编辑的按钮
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.isLoading
                    ? null
                    : () {
                        // 直接跳转到编辑页，不经过生成
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
}