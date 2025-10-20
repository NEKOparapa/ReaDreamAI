// lib/ui/settings/character_settings/character_extraction_dialog.dart

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
        if (characters.isEmpty) {
          _errorMessage = '未能从文本中提取到角色信息';
        }
      });
    } catch (e) {
      LogService.instance.error('角色提取失败', e);
      setState(() {
        _errorMessage = '提取失败: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isExtracting = false;
      });
    }
  }

  void _confirmAndReturn() {
    if (_extractedCharacters != null && _extractedCharacters!.isNotEmpty) {
      Navigator.pop(context, _extractedCharacters);
    }
  }

  // ==================== UI Widgets ====================

  Widget _buildExtractedCharactersList() {
    if (_extractedCharacters == null || _extractedCharacters!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 24),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '提取到 ${_extractedCharacters!.length} 个角色',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _extractedCharacters!.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final character = _extractedCharacters![index];
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character.characterName.isNotEmpty ? character.characterName : '未命名角色',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: [
                        if (character.identity.isNotEmpty)
                          _buildInfoTag('身份', character.identity),
                        if (character.appearance.isNotEmpty)
                          _buildInfoTag('外貌', character.appearance),
                        if (character.clothing.isNotEmpty)
                          _buildInfoTag('服装', character.clothing),
                        if (character.personality.isNotEmpty)
                          _buildInfoTag('性格', character.personality),
                        if (character.status.isNotEmpty)
                          _buildInfoTag('状态', character.status),
                        if (character.other.isNotEmpty)
                          _buildInfoTag('其他', character.other),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTag(String label, String value) {
    return Chip(
      label: Text('$label: $value'),
      labelStyle: Theme.of(context).textTheme.bodySmall,
      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
      side: BorderSide(color: Theme.of(context).dividerColor),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  /// 变更 1: 创建一个构建 ChoiceChip 组的通用方法
  /// 这完全模仿了你参考代码中 "追加标签" 的实现方式
  Widget _buildChoiceChipGroup({
    required String title,
    required Map<String, String> options,
    required String selectedValue,
    required ValueChanged<String> onSelectionChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: options.entries.map((entry) {
            final isSelected = selectedValue == entry.key;
            return ChoiceChip(
              label: Text(entry.value),
              selected: isSelected,
              onSelected: (selected) {
                // ChoiceChip 的 onSelected 在选中和取消时都会触发
                // 我们只在 "选中" 一个新 chip 时更新状态
                if (selected) {
                  onSelectionChanged(entry.key);
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width.clamp(600.0, 900.0);
    final dialogHeight = screenSize.height * 0.85;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxHeight: dialogHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部栏
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
                  Text('提取角色卡片', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 内容区域
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
                    const SizedBox(height: 24),
                    
                    /// 变更 2: 使用新的 _buildChoiceChipGroup 方法来构建设置项
                    _buildChoiceChipGroup(
                      title: '提取角色类别',
                      options: const {
                        'male': '男性',
                        'female': '女性',
                        'all': '全部',
                      },
                      selectedValue: _genderFilter,
                      onSelectionChanged: (newValue) {
                        setState(() {
                          _genderFilter = newValue;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildChoiceChipGroup(
                      title: '标签语言',
                      options: const {
                        'en': '英文',
                        'zh': '中文',
                      },
                      selectedValue: _outputLanguage,
                      onSelectionChanged: (newValue) {
                        setState(() {
                          _outputLanguage = newValue;
                        });
                      },
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
            // 底部操作按钮
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