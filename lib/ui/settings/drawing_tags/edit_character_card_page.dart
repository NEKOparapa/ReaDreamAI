// lib/ui/settings/drawing_tags/edit_character_card_page.dart

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import '../../../base/config_service.dart';
import '../../../models/character_card_model.dart';

class EditCharacterCardPage extends StatefulWidget {
  final CharacterCard? card;

  const EditCharacterCardPage({super.key, this.card});

  @override
  State<EditCharacterCardPage> createState() => _EditCharacterCardPageState();
}

class _EditCharacterCardPageState extends State<EditCharacterCardPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _characterNameController;
  late TextEditingController _identityController;
  late TextEditingController _appearanceController;
  late TextEditingController _clothingController;
  late TextEditingController _otherController;
  late TextEditingController _referenceImageUrlController;
  String? _referenceImagePath;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.card?.name ?? '');
    _characterNameController = TextEditingController(text: widget.card?.characterName ?? '');
    _identityController = TextEditingController(text: widget.card?.identity ?? '');
    _appearanceController = TextEditingController(text: widget.card?.appearance ?? '');
    _clothingController = TextEditingController(text: widget.card?.clothing ?? '');
    _otherController = TextEditingController(text: widget.card?.other ?? '');
    _referenceImageUrlController = TextEditingController(text: widget.card?.referenceImageUrl ?? '');
    _referenceImagePath = widget.card?.referenceImagePath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _characterNameController.dispose();
    _identityController.dispose();
    _appearanceController.dispose();
    _clothingController.dispose();
    _otherController.dispose();
    _referenceImageUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);

    if (result != null) {
      final sourceFile = File(result.files.single.path!);
      final appDir = ConfigService().getConfigDirectoryPath();
      final imagesDir = Directory(p.join(appDir, 'character_images'));
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }
      final fileName = '${const Uuid().v4()}${p.extension(sourceFile.path)}';
      final newPath = p.join(imagesDir.path, fileName);
      await sourceFile.copy(newPath);

      setState(() {
        _referenceImagePath = newPath;
        _referenceImageUrlController.clear(); // 本地和URL互斥
      });
    }
  }

  void _clearImage() {
    setState(() {
      _referenceImagePath = null;
      _referenceImageUrlController.clear();
    });
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      // 当URL不为空时，清空本地路径，确保互斥
      final imageUrl = _referenceImageUrlController.text;
      final imagePath = imageUrl.isNotEmpty ? null : _referenceImagePath;

      final newCard = CharacterCard(
        id: widget.card?.id ?? const Uuid().v4(),
        name: _nameController.text,
        characterName: _characterNameController.text,
        identity: _identityController.text,
        appearance: _appearanceController.text,
        clothing: _clothingController.text,
        other: _otherController.text,
        referenceImageUrl: imageUrl.isNotEmpty ? imageUrl : null,
        referenceImagePath: imagePath,
        isSystemPreset: widget.card?.isSystemPreset ?? false,
      );
      Navigator.pop(context, newCard);
    }
  }

  Widget _buildTextField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      maxLines: 5,
      minLines: 2,
    );
  }

  Widget _buildImagePreview() {
    ImageProvider? imageProvider;
    if (_referenceImagePath != null && _referenceImagePath!.isNotEmpty) {
      imageProvider = FileImage(File(_referenceImagePath!));
    } else if (_referenceImageUrlController.text.isNotEmpty) {
      imageProvider = NetworkImage(_referenceImageUrlController.text);
    }

    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey.shade100,
      ),
      child: imageProvider != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image(
                image: imageProvider,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(child: Icon(Icons.error_outline, color: Colors.red, size: 48));
                },
              ),
            )
          : const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_not_supported_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('无参考图片', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.card == null ? '创建角色卡片' : '编辑角色卡片'),
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
                controller: _characterNameController,
                decoration: const InputDecoration(
                  labelText: '角色名字 (用于在小说文本中匹配,英文逗号区隔多触发词)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              _buildTextField(_identityController, '角色身份'),
              const SizedBox(height: 16),
              _buildTextField(_appearanceController, '外貌特征'),
              const SizedBox(height: 16),
              _buildTextField(_clothingController, '服装配饰'),
              const SizedBox(height: 16),
              _buildTextField(_otherController, '其他标签'),
              const SizedBox(height: 24),
              const Text('参考图片', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildImagePreview(),
              const SizedBox(height: 16),
              TextFormField(
                controller: _referenceImageUrlController,
                decoration: const InputDecoration(
                  labelText: '图片URL (与本地图片互斥)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    setState(() {
                      _referenceImagePath = null; // 输入URL时清除本地路径
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: const Text('导入本地图片'),
                      onPressed: _pickImage,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.clear),
                      label: const Text('清除图片'),
                      onPressed: _clearImage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.1),
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
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
    );
  }
}