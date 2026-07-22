// lib/ui/creation/novel_to_short_drama/dialogs/generate_media_dialog.dart

import 'package:flutter/material.dart';
import '../../../../models/storyboard_script_model.dart';

/// “生成图片和视频”对话框
class GenerateMediaDialog extends StatefulWidget {
  final List<ChapterScript> script;

  const GenerateMediaDialog({super.key, required this.script});

  @override
  State<GenerateMediaDialog> createState() => _GenerateMediaDialogState();
}

class _GenerateMediaDialogState extends State<GenerateMediaDialog> {
  int _imageCount = 0;
  int _videoCount = 0;

  @override
  void initState() {
    super.initState();
    _calculateCounts();
  }

  /// 计算需要生成的媒体数量
  void _calculateCounts() {
    int imgCount = 0;
    int vidCount = 0;
    for (final chapter in widget.script) {
      for (final scene in chapter.scenes) {
        for (final shot in scene.shots) {
          final hasImagePrompt = shot.firstFramePromptController.text.isNotEmpty;
          final hasVideoPrompt = shot.videoPromptController.text.isNotEmpty;

          // 只要有首帧提示词，就会生成图片
          if (hasImagePrompt) {
            imgCount++;
            // 只有同时有首帧提示词和视频提示词时，才会生成视频
            if (hasVideoPrompt) {
              vidCount++;
            }
          }
        }
      }
    }
    setState(() {
      _imageCount = imgCount;
      _videoCount = vidCount;
    });
  }

  /// 确认生成，关闭对话框并返回true
  void _onConfirm() {
    Navigator.of(context).pop(true);
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
                const Text('生成图片和视频', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('将根据已生成的提示词开始生成媒体文件。', style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 16),
                        _buildCountRow('待生成图片数量', _imageCount, Icons.photo_library_outlined),
                        const Divider(height: 24),
                        _buildCountRow('待生成视频数量', _videoCount, Icons.movie_creation_outlined),
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
                  icon: const Icon(Icons.rocket_launch_outlined),
                  label: const Text('开始生成'),
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
}