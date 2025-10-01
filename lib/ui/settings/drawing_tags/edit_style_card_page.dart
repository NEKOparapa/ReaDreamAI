// lib/ui/settings/drawing_tags/edit_style_card_page.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import '../../../models/style_card_model.dart';
import '../../../base/config_service.dart';

class EditStyleCardPage extends StatefulWidget {
  final StyleCard? card;

  const EditStyleCardPage({super.key, this.card});

  @override
  State<EditStyleCardPage> createState() => _EditStyleCardPageState();
}

class _EditStyleCardPageState extends State<EditStyleCardPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _contentController;
  String? _exampleImage;
  final _configService = ConfigService();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.card?.name ?? '');
    _contentController = TextEditingController(text: widget.card?.content ?? '');
    _exampleImage = widget.card?.exampleImage;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      // 获取样式图片存储目录
      final styleImagesDir = Directory(path.join(
        _configService.getAppDirectoryPath(),
        'Config',
        'StyleImages',
      ));

      if (!await styleImagesDir.exists()) {
        await styleImagesDir.create(recursive: true);
      }

      final cardId = widget.card?.id ?? const Uuid().v4();
      final file = result.files.single;

      // 生成唯一文件名
      final fileName = '${cardId}_${DateTime.now().millisecondsSinceEpoch}_${path.basename(file.path!)}';
      final newPath = path.join(styleImagesDir.path, fileName);

      // 复制文件到应用目录
      final sourceFile = File(file.path!);
      await sourceFile.copy(newPath);

      // 如果已有图片，删除旧图片
      if (_exampleImage != null && !_exampleImage!.startsWith('assets/')) {
        final oldFile = File(_exampleImage!);
        if (await oldFile.exists()) {
          await oldFile.delete();
        }
      }

      setState(() {
        _exampleImage = newPath;
      });
    }
  }

  void _removeImage() async {
    if (_exampleImage != null && !_exampleImage!.startsWith('assets/')) {
      // 删除文件
      final file = File(_exampleImage!);
      if (await file.exists()) {
        await file.delete();
      }
    }

    setState(() {
      _exampleImage = null;
    });
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      final newCard = StyleCard(
        id: widget.card?.id ?? const Uuid().v4(),
        name: _nameController.text,
        content: _contentController.text,
        isSystemPreset: widget.card?.isSystemPreset ?? false,
        exampleImage: _exampleImage,
      );

      // 如果是编辑现有卡片，需要清理被删除的图片
      if (widget.card != null && widget.card!.exampleImage != null && 
          widget.card!.exampleImage != _exampleImage &&
          !widget.card!.exampleImage!.startsWith('assets/')) {
        final oldFile = File(widget.card!.exampleImage!);
        if (oldFile.existsSync()) {
          oldFile.deleteSync();
        }
      }

      Navigator.pop(context, newCard);
    }
  }

  Widget _buildImageSection() {
    if (_exampleImage == null) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text('暂无示例图片', style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.add_photo_alternate),
                label: const Text('选择图片'),
              ),
            ],
          ),
        ),
      );
    }

    // 检查文件是否存在
    final isAsset = _exampleImage!.startsWith('assets/');
    if (!isAsset && !File(_exampleImage!).existsSync()) {
      // 文件不存在，重置为null并重新构建
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _exampleImage = null;
        });
      });
      return _buildImageSection();
    }

    return Container(
      height: 200,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          Center(
            child: GestureDetector(
              onTap: () => _showImagePreview(_exampleImage!),
              child: Container(
                width: 180,
                height: 180,
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: isAsset
                        ? AssetImage(_exampleImage!) as ImageProvider
                        : FileImage(File(_exampleImage!)),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                  ),
                  onPressed: _pickImage,
                ),
                const SizedBox(width: 4),
                if (widget.card?.isSystemPreset != true)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                    ),
                    onPressed: _removeImage,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showImagePreview(String imagePath) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Stack(
          children: [
            imagePath.startsWith('assets/')
                ? Image.asset(imagePath)
                : Image.file(File(imagePath)),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.card == null ? '创建风格卡片' : '编辑风格卡片'),
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
              const SizedBox(height: 16),
              const Text(
                '示例图片',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              _buildImageSection(),
              // 添加一些底部空间，防止被保存按钮遮挡
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
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
    );
  }
}
