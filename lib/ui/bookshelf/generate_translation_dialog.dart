// lib/ui/bookshelf/generate_translation_dialog.dart

import 'package:flutter/material.dart';
import '../../base/config_service.dart';
import '../../models/book.dart';
import '../../models/bookshelf_entry.dart';
import '../../services/cache_manager/cache_manager.dart';
import '../../services/task_splitter/task_splitter_service.dart';
import '../../services/task_manager/task_manager_service.dart';
import '../../base/default_configs.dart';

class GenerateTranslationDialog extends StatefulWidget {
  final BookshelfEntry entry;

  const GenerateTranslationDialog({
    super.key,
    required this.entry,
  });

  @override
  State<GenerateTranslationDialog> createState() =>
      _GenerateTranslationDialogState();
}

class _GenerateTranslationDialogState extends State<GenerateTranslationDialog> {
  final ConfigService _configService = ConfigService();

  // 语言选项
  late String _sourceLang;
  late String _targetLang;
  final Map<String, String> _languageOptions = {
    'zh-CN': '简中',
    'zh-TW': '繁中',
    'ko': '韩语',
    'ja': '日语',
    'en': '英语',
    'ru': '俄语',
  };

  // 内部状态
  Book? _book;
  int? _estimatedLineCount;
  bool _isLoading = true;
  String? _calculationError;

  @override
  void initState() {
    super.initState();
    _loadConfigurations();
    _loadDataAndEstimate();
  }

  /// 加载配置，如默认语言
  void _loadConfigurations() {
    setState(() {
      _sourceLang = _configService.getSetting('translation_source_lang',
          appDefaultConfigs['translation_source_lang']);
      _targetLang = _configService.getSetting('translation_target_lang',
          appDefaultConfigs['translation_target_lang']);
    });
  }

  /// 加载书籍数据并预估翻译行数
  Future<void> _loadDataAndEstimate() async {
    try {
      final book = await CacheManager().loadBookDetail(widget.entry.id);
      if (!mounted) return;

      if (book == null) {
        setState(() {
          _calculationError = '加载书籍数据失败';
          _isLoading = false;
        });
        return;
      }
      
      // 计算总行数
      final totalLines = book.chapters.fold<int>(0, (sum, chapter) => sum + chapter.lines.length);

      setState(() {
        _book = book;
        _estimatedLineCount = totalLines;
        _isLoading = false;
      });

    } catch (e) {
      if (mounted) {
        setState(() {
          _calculationError = '计算时发生错误: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// 确认生成，执行任务创建逻辑
  Future<void> _onConfirm() async {
    if (_book == null) return;

    // 1. 保存用户的UI选择到配置文件，以便下次使用
    await _configService.modifySetting('translation_source_lang', _sourceLang);
    await _configService.modifySetting('translation_target_lang', _targetLang);

    // 2. 调用服务来切分任务块
    final chunks = TaskSplitterService.instance.splitBookForTranslations(_book!);
    if (chunks.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('书籍内容太少或不符合要求，无法创建翻译任务')),
      );
      return;
    }

    // 3. 加载整个书架，更新指定条目，然后保存
    final allEntries = await CacheManager().loadBookshelf();
    final index = allEntries.indexWhere((e) => e.id == widget.entry.id);

    if (index != -1) {
      // 更新翻译相关的字段
      allEntries[index].translationTaskChunks = chunks;
      allEntries[index].translationStatus = TaskStatus.queued;
      allEntries[index].translationCreatedAt = DateTime.now();
      allEntries[index].translationUpdatedAt = DateTime.now();
      allEntries[index].translationErrorMessage = null;

      await CacheManager().saveBookshelf(allEntries);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('错误：在缓存中找不到书籍条目，无法更新任务状态')),
        );
      }
      return;
    }

    // 4. 通知任务管理器处理新任务
    await TaskManagerService.instance.reloadData();
    TaskManagerService.instance.processQueue();

    // 5. 关闭对话框并返回成功状态
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  /// 构建显示预估数量的Widget
  Widget _buildEstimationWidget() {
    if (_isLoading) {
      return const SizedBox(
        width: 16, height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_calculationError != null) {
      return Text(
        _calculationError!,
        style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w500),
      );
    }
    return Text(
      '${_estimatedLineCount ?? 0} 行',
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
    );
  }

  /// 构建语言选择器
  Widget _buildLanguageSelector({
    required String title,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        const Spacer(),
        DropdownButton<String>(
          value: value,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(12),
          items: _languageOptions.entries.map<DropdownMenuItem<String>>((entry) {
            return DropdownMenuItem<String>(
              value: entry.key,
              child: Text(entry.value),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.6,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          maxWidth: 500, // 翻译对话框不需要太宽
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('生成翻译', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 使用 Flexible 包裹，避免内容过多时溢出
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.translate, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 12),
                                const Text('预计翻译行数：', style: TextStyle(fontWeight: FontWeight.w500)),
                                const Spacer(),
                                _buildEstimationWidget(),
                              ],
                            ),
                            const Divider(height: 24),
                            _buildLanguageSelector(
                              title: '源语言',
                              value: _sourceLang,
                              onChanged: (newValue) {
                                if (newValue != null) {
                                  setState(() => _sourceLang = newValue);
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                             _buildLanguageSelector(
                              title: '目标语言',
                              value: _targetLang,
                              onChanged: (newValue) {
                                if (newValue != null) {
                                  setState(() => _targetLang = newValue);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 16),
                FilledButton(
                  onPressed: _book != null ? _onConfirm : null, // 如果数据未加载成功，则禁用按钮
                  child: const Text('确认生成'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}