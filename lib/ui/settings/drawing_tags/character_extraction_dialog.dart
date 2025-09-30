// lib/ui/settings/drawing_tags/character_extraction_dialog.dart

import 'package:flutter/material.dart';
import '../../../services/task_executor/character_extractor.dart';
import '../../../models/character_card_model.dart';
import '../../../base/log/log_service.dart';

class CharacterExtractionDialog extends StatefulWidget {
  const CharacterExtractionDialog({super.key});

  @override
  State<CharacterExtractionDialog> createState() => _CharacterExtractionDialogState();
}

class _CharacterExtractionDialogState extends State<CharacterExtractionDialog> {
  final TextEditingController _textController = TextEditingController();
  String _genderFilter = 'all';
  String _outputLanguage = 'zh';
  bool _isExtracting = false;
  List<CharacterCard>? _extractedCharacters;
  String? _errorMessage;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _extractCharacters() async {
    if (_textController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = '请输入要提取角色的文本';
      });
      return;
    }

    setState(() {
      _isExtracting = true;
      _extractedCharacters = null;
      _errorMessage = null;
    });

    try {
      final characters = await CharacterExtractor.instance.extractCharacters(
        textContent: _textController.text,
        genderFilter: _genderFilter,
        outputLanguage: _outputLanguage,
      );

      setState(() {
        _extractedCharacters = characters;
        _isExtracting = false;
      });

      if (characters.isEmpty) {
        setState(() {
          _errorMessage = '未能从文本中提取到角色信息';
        });
      }
    } catch (e) {
      LogService.instance.error('角色提取失败', e);
      setState(() {
        _isExtracting = false;
        _errorMessage = '提取失败: ${e.toString()}';
      });
    }
  }

  void _confirmAndReturn() {
    if (_extractedCharacters != null && _extractedCharacters!.isNotEmpty) {
      Navigator.pop(context, _extractedCharacters);
    }
  }

  Widget _buildExtractedCharactersList() {
    if (_extractedCharacters == null || _extractedCharacters!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              '提取到 ${_extractedCharacters!.length} 个角色',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _extractedCharacters!.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final character = _extractedCharacters![index];
                return Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        character.characterName.isNotEmpty ? character.characterName : '未命名角色',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (character.identity.isNotEmpty)
                        _buildInfoRow('身份', character.identity),
                      if (character.appearance.isNotEmpty)
                        _buildInfoRow('外貌', character.appearance),
                      if (character.clothing.isNotEmpty)
                        _buildInfoRow('服装', character.clothing),
                      if (character.other.isNotEmpty)
                        _buildInfoRow('其他', character.other),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodySmall?.color,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 获取屏幕尺寸
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width * 0.85;
    final dialogHeight = screenSize.height * 0.85;
    
    return Dialog(
      // 减少内边距，让对话框更大
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      // 设置统一的圆角
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // 适度的圆角
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: dialogWidth.clamp(600, 900), // 最小600，最大900
          maxHeight: dialogHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 使用自定义的顶部栏而不是 AppBar，保持圆角
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Text(
                    '提取角色卡片',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        labelText: '原文文本',
                        hintText: '请输入包含角色描述的文本...',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 10,
                      minLines: 8,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '提取角色类别',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 8),
                              SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(value: 'male', label: Text('男性')),
                                  ButtonSegment(value: 'female', label: Text('女性')),
                                  ButtonSegment(value: 'all', label: Text('全部')),
                                ],
                                selected: {_genderFilter},
                                onSelectionChanged: (selection) {
                                  setState(() {
                                    _genderFilter = selection.first;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '标签语言',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 8),
                              SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(value: 'en', label: Text('英文')),
                                  ButtonSegment(value: 'zh', label: Text('中文')),
                                ],
                                selected: {_outputLanguage},
                                onSelectionChanged: (selection) {
                                  setState(() {
                                    _outputLanguage = selection.first;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(color: Colors.red[700], fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_isExtracting)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(48.0),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    _buildExtractedCharactersList(),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isExtracting ? null : _extractCharacters,
                    icon: const Icon(Icons.search),
                    label: const Text('提取角色'),
                  ),
                  if (_extractedCharacters != null && _extractedCharacters!.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _confirmAndReturn,
                      icon: const Icon(Icons.check),
                      label: const Text('确认添加'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
