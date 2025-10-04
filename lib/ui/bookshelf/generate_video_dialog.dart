// lib/ui/bookshelf/generate_video_dialog.dart
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../base/config_service.dart';
import '../../models/book.dart';
import '../../models/bookshelf_entry.dart';
import '../../services/cache_manager/cache_manager.dart';
import '../../services/task_manager/task_manager_service.dart';
import '../../base/default_configs.dart';

class GenerateVideoDialog extends StatefulWidget {
  final BookshelfEntry entry;

  const GenerateVideoDialog({
    super.key,
    required this.entry,
  });

  @override
  State<GenerateVideoDialog> createState() => _GenerateVideoDialogState();
}

class _GenerateVideoDialogState extends State<GenerateVideoDialog> {
  final ConfigService _configService = ConfigService();

  // 视频设置选项
  late String _resolution;
  late int _duration;
  final Map<String, String> _resolutionOptions = {
    '576p': '1024x576',
    '720p': '1280x720',
    '1080p': '1920x1080',
  };
  final List<int> _durationOptions = [3, 5, 7, 10];

  // 内部状态
  Book? _book;
  int? _estimatedVideoCount;
  bool _isLoading = true;
  String? _calculationError;

  @override
  void initState() {
    super.initState();
    _loadConfigurations();
    _loadDataAndEstimate();
  }

  /// 加载配置，如默认分辨率和时长
  void _loadConfigurations() {
    setState(() {
      _resolution = _configService.getSetting('video_gen_resolution', appDefaultConfigs['video_gen_resolution'] as String);
      _duration = _configService.getSetting('video_gen_duration', appDefaultConfigs['video_gen_duration'] as int);
    });
  }

  /// 加载书籍数据并统计插图数量
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
      
      // 统计总插图数
      final totalIllustrations = book.chapters.fold<int>(0, (sum, chapter) {
        return sum + chapter.lines.fold<int>(0, (lineSum, line) => lineSum + line.illustrationPaths.length);
      });

      setState(() {
        _book = book;
        _estimatedVideoCount = totalIllustrations;
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

    // 1. 保存用户的UI选择到配置文件
    await _configService.modifySetting('video_gen_resolution', _resolution);
    await _configService.modifySetting('video_gen_duration', _duration);

    // 2. 遍历书籍，为每张插图创建任务块
    const uuid = Uuid();
    final List<VideoGenerationTaskChunk> chunks = [];
    for (final chapter in _book!.chapters) {
      for (final line in chapter.lines) {
        for (final imagePath in line.illustrationPaths) {
          chunks.add(VideoGenerationTaskChunk(
            id: uuid.v4(),
            chapterId: chapter.id,
            lineId: line.id,
            sourceImagePath: imagePath,
          ));
        }
      }
    }
    
    if (chunks.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('书籍没有插图，无法创建视频生成任务')),
      );
      return;
    }

    // 3. 更新 BookshelfEntry 并保存
    final allEntries = await CacheManager().loadBookshelf();
    final index = allEntries.indexWhere((e) => e.id == widget.entry.id);

    if (index != -1) {
      allEntries[index].videoGenerationTaskChunks = chunks;
      allEntries[index].videoGenerationStatus = TaskStatus.queued;
      allEntries[index].videoGenerationCreatedAt = DateTime.now();
      allEntries[index].videoGenerationUpdatedAt = DateTime.now();
      allEntries[index].videoGenerationErrorMessage = null;
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

  Widget _buildEstimationWidget() {
    if (_isLoading) {
      return const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_calculationError != null) {
      return Text(_calculationError!, style: TextStyle(color: Theme.of(context).colorScheme.error));
    }
    return Text(
      '${_estimatedVideoCount ?? 0} 个',
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
    );
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('图生视频', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 16),
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
                                Icon(Icons.video_library, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 12),
                                const Text('预计生成视频数量：', style: TextStyle(fontWeight: FontWeight.w500)),
                                const Spacer(),
                                _buildEstimationWidget(),
                              ],
                            ),
                            const Divider(height: 24),
                            // Resolution Selector
                            Row(
                              children: [
                                const Text('分辨率', style: TextStyle(fontWeight: FontWeight.w500)),
                                const Spacer(),
                                DropdownButton<String>(
                                  value: _resolution,
                                  items: _resolutionOptions.entries.map((entry) {
                                    return DropdownMenuItem<String>(value: entry.key, child: Text(entry.value));
                                  }).toList(),
                                  onChanged: (newValue) {
                                    if (newValue != null) setState(() => _resolution = newValue);
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Duration Selector
                            Row(
                              children: [
                                const Text('时长 (秒)', style: TextStyle(fontWeight: FontWeight.w500)),
                                const Spacer(),
                                DropdownButton<int>(
                                  value: _duration,
                                  items: _durationOptions.map((duration) {
                                    return DropdownMenuItem<int>(value: duration, child: Text('$duration s'));
                                  }).toList(),
                                  onChanged: (newValue) {
                                    if (newValue != null) setState(() => _duration = newValue);
                                  },
                                ),
                              ],
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
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
                const SizedBox(width: 16),
                FilledButton(
                  onPressed: _book != null && _estimatedVideoCount != null && _estimatedVideoCount! > 0 ? _onConfirm : null,
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