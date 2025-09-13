// lib/ui/settings/prompt_card_edit_page.dart

import 'package:flutter/material.dart';
import '../../../base/config_service.dart';
import '../../../models/prompt_card_model.dart';

class PromptCardEditPage extends StatefulWidget {
  final PromptCard? cardToEdit;

  const PromptCardEditPage({super.key, this.cardToEdit});

  @override
  State<PromptCardEditPage> createState() => _PromptCardEditPageState();
}

class _PromptCardEditPageState extends State<PromptCardEditPage> {
  final _formKey = GlobalKey<FormState>();
  final ConfigService _configService = ConfigService();
  late TextEditingController _nameController;
  late TextEditingController _contentController;
  bool get _isEditing => widget.cardToEdit != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.cardToEdit?.name ?? '');
    _contentController = TextEditingController(text: widget.cardToEdit?.content ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _saveCard() async {
    if (_formKey.currentState!.validate()) {
      final allCardsJson = _configService.getSetting<List<dynamic>>('prompt_cards', []);
      List<PromptCard> allCards = allCardsJson.map((json) => PromptCard.fromJson(json as Map<String, dynamic>)).toList();

      if (_isEditing) {
        final index = allCards.indexWhere((c) => c.id == widget.cardToEdit!.id);
        if (index != -1) {
          allCards[index].name = _nameController.text;
          allCards[index].content = _contentController.text;
        }
      } else {
        final newCard = PromptCard(
          name: _nameController.text,
          content: _contentController.text,
        );
        allCards.add(newCard);
      }
      
      await _configService.modifySetting(
        'prompt_cards',
        allCards.map((c) => c.toJson()).toList(),
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存成功！')),
        );
        Navigator.of(context).pop(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑提示词' : '新增提示词'),
        // 【修改】移除AppBar中的actions
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '名称',
                border: OutlineInputBorder(),
                helperText: '为这个提示词起一个方便识别的名字',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '名称不能为空';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _contentController,
              decoration: const InputDecoration(
                labelText: '内容',
                border: OutlineInputBorder(),
                helperText: '这里填写将要发送给语言模型的系统指令',
                alignLabelWithHint: true,
              ),
              maxLines: 15,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '内容不能为空';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      // 【修改】使用bottomNavigationBar添加底部的保存按钮
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 24.0),
        child: FilledButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('保存'),
          onPressed: _saveCard,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            textStyle: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );
  }
}