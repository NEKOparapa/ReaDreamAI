// lib/ui/creation/novel_to_short_drama/dialogs/generate_prompts_dialog.dart

import 'package:flutter/material.dart';
import '../../../../base/config_service.dart';
import '../../../../models/storyboard_script_model.dart';

/// “生成全部提示词”对话框
class GeneratePromptsDialog extends StatefulWidget {
  final List<ChapterScript> script;

  const GeneratePromptsDialog({super.key, required this.script});

  @override
  State<GeneratePromptsDialog> createState() => _GeneratePromptsDialogState();
}

class _GeneratePromptsDialogState extends State<GeneratePromptsDialog> {
  final ConfigService _configService = ConfigService();
  late String _selectedLanguage;
  int _firstFramePromptCount = 0;
  int _videoPromptCount = 0;

  @override
  void initState() {
    super.initState();
    // 从配置中加载上一次选择的语言，默认为'en'
    _selectedLanguage = _configService.getSetting<String>('storyboard_gen_prompt_language', 'en');
    _calculateCounts();
  }

  /// 计算需要生成的提示词数量
  void _calculateCounts() {
    int shotCount = 0;
    for (final chapter in widget.script) {
      for (final scene in chapter.scenes) {
        shotCount += scene.shots.length;
      }
    }
    setState(() {
      // 首帧提示词和视频提示词是为每个分镜都生成的
      _firstFramePromptCount = shotCount;
      _videoPromptCount = shotCount;
    });
  }

  /// 确认生成，保存设置并返回选择的语言
  void _onConfirm() {
    _configService.modifySetting('storyboard_gen_prompt_language', _selectedLanguage);
    Navigator.of(context).pop(_selectedLanguage);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.6,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          maxWidth: 500,
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
                const Text('生成全部提示词', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 内容区域
            Flexible(
              child: SingleChildScrollView(
                child: Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildCountRow('首帧提示词', _firstFramePromptCount, Icons.image_outlined),
                        const Divider(height: 24),
                        _buildCountRow('视频提示词', _videoPromptCount, Icons.video_library_outlined),
                        const Divider(height: 24),
                        _buildLanguageSelector(),
                      ],
                    ),
                  ),
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
                FilledButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('确认生成'),
                  onPressed: _onConfirm,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  /// 构建数量显示行
  Widget _buildCountRow(String title, int count, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(
          '$count 个',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
        ),
      ],
    );
  }

  /// 构建语言选择器
  Widget _buildLanguageSelector() {
    return Row(
      children: [
        const Icon(Icons.translate_outlined, color: Colors.grey),
        const SizedBox(width: 12),
        const Text('提示词语言', style: TextStyle(fontWeight: FontWeight.w500)),
        const Spacer(),
        DropdownButton<String>(
          value: _selectedLanguage,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(12),
          items: const [
            DropdownMenuItem<String>(
              value: 'en',
              child: Text('英文'),
            ),
            DropdownMenuItem<String>(
              value: 'zh',
              child: Text('中文'),
            ),
          ],
          onChanged: (newValue) {
            if (newValue != null) {
              setState(() => _selectedLanguage = newValue);
            }
          },
        ),
      ],
    );
  }
}