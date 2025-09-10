// lib/ui/settings/drawing_tags/edit_tag_card_page.dart

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../models/tag_card_model.dart';

class EditTagCardPage extends StatefulWidget {
  final TagCard? card;

  const EditTagCardPage({super.key, this.card});

  @override
  State<EditTagCardPage> createState() => _EditTagCardPageState();
}

class _EditTagCardPageState extends State<EditTagCardPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.card?.name ?? '');
    _contentController = TextEditingController(text: widget.card?.content ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      final newCard = TagCard(
        id: widget.card?.id ?? const Uuid().v4(),
        name: _nameController.text,
        content: _contentController.text,
        isSystemPreset: widget.card?.isSystemPreset ?? false,
      );
      Navigator.pop(context, newCard);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.card == null ? '创建标签卡片' : '编辑标签卡片'),
        // --- REMOVED ---
        // actions: [
        //   IconButton(
        //     icon: const Icon(Icons.save),
        //     onPressed: _save,
        //   ),
        // ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '卡片名字',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入卡片名字';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contentController,
                decoration: const InputDecoration(
                  labelText: '标签内容 (英文逗号分隔)',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 8,
                minLines: 3,
              ),
              // 添加一些底部空间，防止被保存按钮遮挡
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      // --- ADDED SECTION ---
      // 将保存按钮放在底部，方便操作
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            child: const Text('保存'),
          ),
        ),
      ),
      // --- END OF ADDED SECTION ---
    );
  }
}