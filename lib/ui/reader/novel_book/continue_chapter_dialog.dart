// lib/ui/reader/novel_book/continue_chapter_dialog.dart

import 'package:flutter/material.dart';

import '../../../models/book.dart';
import '../../../base/config_service.dart';
import '../../../services/task_executor/novel_continuation_service.dart';

/// AI 续写新章配置弹窗
class ContinueChapterDialog extends StatefulWidget {
  final Book book;

  const ContinueChapterDialog({super.key, required this.book});

  @override
  State<ContinueChapterDialog> createState() => _ContinueChapterDialogState();
}

class _ContinueChapterDialogState extends State<ContinueChapterDialog> {
  final _requirementController = TextEditingController();
  final _writingStyleController = TextEditingController();
  final _wordsController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _writingStyleController.text = widget.book.writingStyle ?? '';
    _wordsController.text = ConfigService().getSetting<int>(
          'ai_novel_creation_words_per_chapter',
          1500,
        ).toString();
  }

  @override
  void dispose() {
    _requirementController.dispose();
    _writingStyleController.dispose();
    _wordsController.dispose();
    super.dispose();
  }

  int _parseWords() {
    final s = _wordsController.text.trim();
    if (s.isEmpty) return 1500;
    return int.tryParse(s) ?? 1500;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI 续写新章'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _requirementController,
                decoration: const InputDecoration(
                  labelText: '续写要求',
                  hintText: '例如：主角发现了一个秘密，决定前去调查...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return '请输入续写要求';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _writingStyleController,
                decoration: const InputDecoration(
                  labelText: '文风设定',
                  hintText: '可选，留空则从末两章自动提取',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _wordsController,
                decoration: const InputDecoration(
                  labelText: '章节字数',
                  hintText: '例如：1500',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return '请输入字数';
                  }
                  final n = int.tryParse(v.trim());
                  if (n == null || n < 100 || n > 20000) {
                    return '字数应在 100～20000 之间';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final params = ContinuationParams(
              continuationRequirement: _requirementController.text.trim(),
              writingStyleOverride: _writingStyleController.text.trim(),
              wordsPerChapter: _parseWords(),
            );
            Navigator.of(context).pop(params);
          },
          child: const Text('开始生成'),
        ),
      ],
    );
  }
}
