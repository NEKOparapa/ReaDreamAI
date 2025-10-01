// lib/ui/bookshelf/generate_illustration_dialog.dart

import 'package:flutter/material.dart';
import 'dart:io';
import '../../base/config_service.dart';
import '../../models/book.dart';
import '../../models/character_card_model.dart';
import '../../models/style_card_model.dart';
import '../../models/tag_card_model.dart';
import '../../models/bookshelf_entry.dart';
import '../../services/cache_manager/cache_manager.dart';
import '../../services/task_splitter/task_splitter_service.dart';
import '../../services/task_manager/task_manager_service.dart';

class GenerateIllustrationDialog extends StatefulWidget {
  final BookshelfEntry entry;

  const GenerateIllustrationDialog({
    super.key,
    required this.entry,
  });

  @override
  State<GenerateIllustrationDialog> createState() =>
      _GenerateIllustrationDialogState();
}

class _GenerateIllustrationDialogState extends State<GenerateIllustrationDialog> {
  final ConfigService _configService = ConfigService();

  // 角色设定
  List<CharacterCard> _characterCards = [];
  List<String> _selectedCharacterIds = [];

  // 绘画风格
  List<StyleCard> _styleCards = [];
  String? _selectedStyleId;

  // 追加标签
  List<TagCard> _otherTags = [];
  String? _selectedOtherTagId;

  // 快速设置的状态
  late int _scenesPerChapter;
  late int _imagesPerScene;

  // 内部状态
  Book? _book;
  int? _estimatedImageCount;
  bool _isLoading = true;
  String? _calculationError;

  @override
  void initState() {
    super.initState();
    _loadConfigurations();
    _loadDataAndCalculate();
  }

  void _loadConfigurations() {
    // 加载角色设定
    final characterJson = _configService.getSetting<List<dynamic>>(
        'drawing_character_cards', []);
    final activeCharacterIds = _configService
        .getSetting<List<dynamic>>('active_drawing_character_card_ids', []);

    // 加载绘画风格
    final styleJson =
        _configService.getSetting<List<dynamic>>('drawing_style_tags', []);
    final activeStyleId =
        _configService.getSetting<String?>('active_drawing_style_tag_id', null);

    // 加载追加标签
    final otherTagsJson =
        _configService.getSetting<List<dynamic>>('drawing_other_tags', []);
    final activeOtherTagId = _configService
        .getSetting<String?>('active_drawing_other_tag_id', null);

    // 新增：加载快速设置的默认值
    _scenesPerChapter =
        _configService.getSetting<int>('image_gen_scenes_per_chapter', 3);
    _imagesPerScene =
        _configService.getSetting<int>('image_gen_images_per_scene', 2);


    setState(() {
      _characterCards = characterJson
          .map((json) => CharacterCard.fromJson(json as Map<String, dynamic>))
          .toList();
      _selectedCharacterIds = List<String>.from(activeCharacterIds);

      _styleCards = styleJson
          .map((json) => StyleCard.fromJson(json as Map<String, dynamic>))
          .toList();
      _selectedStyleId = activeStyleId;

      _otherTags = otherTagsJson
          .map((json) => TagCard.fromJson(json as Map<String, dynamic>))
          .toList();
      _selectedOtherTagId = activeOtherTagId;
    });
  }

  /// 动态计算预计图片数量
  void _recalculateEstimation() {
    if (_book == null) return;
    setState(() {
      _estimatedImageCount =
          _book!.chapters.length * _scenesPerChapter * _imagesPerScene;
    });
  }

  /// 加载书籍数据并进行初次计算
  Future<void> _loadDataAndCalculate() async {
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
      
      setState(() {
        _book = book;
        _isLoading = false;
      });
      _recalculateEstimation(); // 使用新方法进行计算

    } catch (e) {
      if (mounted) {
        setState(() {
          _calculationError = '计算时发生错误';
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildImagePlaceholder({double width = 80, double height = 80}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.image_outlined,
        size: width * 0.5,
        color: Colors.grey[500],
      ),
    );
  }

  // 卡片UI
  Widget _buildSelectableCard({
    required bool isSelected,
    required VoidCallback onTap,
    required String? imagePath,
    required String name,
  }) {
    final hasImage = imagePath != null &&
        (imagePath.startsWith('assets/') || File(imagePath).existsSync());
    
    // 确定图片提供者
    ImageProvider? imageProvider;
    if (hasImage) {
      imageProvider = imagePath.startsWith('assets/')
          ? AssetImage(imagePath)
          : FileImage(File(imagePath)) as ImageProvider;
    }

    return SizedBox(
      width: 120,
      height: 150, // 给予一个固定的高度，确保Wrap布局整齐
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 图片在上
            Expanded(
              child: Card(
                elevation: 1,
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: hasImage
                    ? Image(
                        image: imageProvider!,
                        fit: BoxFit.cover,
                      )
                    : _buildImagePlaceholder(width: 120, height: 120),
              ),
            ),
            const SizedBox(height: 8),
            // 卡片名字在下
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: isSelected
                  ? BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: Text(
                name,
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCharacterCard(CharacterCard card) {
    final isSelected = _selectedCharacterIds.contains(card.id);
    return _buildSelectableCard(
      isSelected: isSelected,
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedCharacterIds.remove(card.id);
          } else {
            _selectedCharacterIds.add(card.id);
          }
        });
      },
      imagePath: card.referenceImagePath,
      name: card.name,
    );
  }

  Widget _buildStyleCard(StyleCard card) {
    final isSelected = _selectedStyleId == card.id;
    return _buildSelectableCard(
      isSelected: isSelected,
      onTap: () {
        setState(() {
          _selectedStyleId = isSelected ? null : card.id;
        });
      },
      imagePath: card.exampleImage,
      name: card.name,
    );
  }

  Widget _buildTagChip(TagCard tag) {
    final isSelected = _selectedOtherTagId == tag.id;

    return ChoiceChip(
      label: Text(tag.name),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedOtherTagId = selected ? tag.id : null;
        });
      },
    );
  }

  /// 确认生成，执行任务创建逻辑
  Future<void> _onConfirm() async {
    // 1. 保存用户的UI选择到配置文件
    await _configService.modifySetting(
        'active_drawing_character_card_ids', _selectedCharacterIds);
    await _configService.modifySetting(
        'active_drawing_style_tag_id', _selectedStyleId);
    await _configService.modifySetting(
        'active_drawing_other_tag_id', _selectedOtherTagId);
    await _configService.modifySetting(
        'image_gen_scenes_per_chapter', _scenesPerChapter);
    await _configService.modifySetting(
        'image_gen_images_per_scene', _imagesPerScene);

    // 2. 调用服务来切分任务块
    final chunks =
        TaskSplitterService.instance.splitBookForIllustrations(_book!);
    if (chunks.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('书籍内容太少或不符合要求，无法创建插图任务')),
      );
      return;
    }

    // 3. 加载整个书架，更新指定条目，然后保存
    final allEntries = await CacheManager().loadBookshelf();
    final index = allEntries.indexWhere((e) => e.id == widget.entry.id);

    if (index != -1) {
      allEntries[index].taskChunks = chunks;
      allEntries[index].status = TaskStatus.queued;
      allEntries[index].createdAt = DateTime.now();
      allEntries[index].updatedAt = DateTime.now();
      allEntries[index].errorMessage = null;

      await CacheManager().saveBookshelf(allEntries);
    } else {
      // 如果条目未找到，这是一个错误状态，提示用户
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('错误：在缓存中找不到书籍条目，无法更新任务状态')),
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

  /// 构建显示预计数量的Widget
  Widget _buildEstimationWidget() {
    if (_isLoading) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_calculationError != null) {
      return Text(
        _calculationError!,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontWeight: FontWeight.w500,
        ),
      );
    }
    return Text(
      '${_estimatedImageCount ?? 0} 张',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  // 构建数字步进器控件
  Widget _buildNumberStepperControl({
    required String title,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.remove, size: 20),
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          style: IconButton.styleFrom(
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
        SizedBox(
            width: 40,
            child: Text(
              value.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            )),
        IconButton(
          icon: const Icon(Icons.add, size: 20),
          onPressed: () => onChanged(value + 1),
          style: IconButton.styleFrom(
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          maxWidth: 850,
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
                const Text(
                  '生成插图',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Expanded(
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
                                Icon(
                                  Icons.auto_awesome,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  '预计生成图片数量：',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                                const Spacer(),
                                _buildEstimationWidget(),
                              ],
                            ),
                            const Divider(height: 24),
                            _buildNumberStepperControl(
                              title: '每章节场景数',
                              value: _scenesPerChapter,
                              onChanged: (newValue) {
                                setState(() => _scenesPerChapter = newValue);
                                _recalculateEstimation();
                              },
                            ),
                            const SizedBox(height: 8),
                            _buildNumberStepperControl(
                              title: '每场景图片数',
                              value: _imagesPerScene,
                              onChanged: (newValue) {
                                setState(() => _imagesPerScene = newValue);
                                _recalculateEstimation();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 角色设定
                    const Text(
                      '角色设定',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    if (_characterCards.isEmpty)
                      Container(
                        height: 100,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '暂无角色设定',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    else
                      // 使用 Wrap 布局代替水平 ListView
                      // 这将使卡片在空间不足时自动换行，避免水平溢出
                      Wrap(
                        spacing: 12.0, // 水平间距
                        runSpacing: 12.0, // 垂直间距（换行后）
                        children: _characterCards.map((card) => _buildCharacterCard(card)).toList(),
                      ),
                    const SizedBox(height: 24),

                    // 绘画风格
                    const Text(
                      '绘画风格',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    if (_styleCards.isEmpty)
                      Container(
                        height: 100,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '暂无绘画风格',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    else
                      // 同样使用 Wrap 布局
                      Wrap(
                        spacing: 12.0,
                        runSpacing: 12.0,
                        children: _styleCards.map((card) => _buildStyleCard(card)).toList(),
                      ),
                    const SizedBox(height: 24),

                    // 追加标签
                    const Text(
                      '追加标签',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    if (_otherTags.isEmpty)
                      Container(
                        height: 60,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '暂无追加标签',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _otherTags.map(_buildTagChip).toList(),
                      ),
                  ],
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
                FilledButton(
                  onPressed:
                      _book != null ? _onConfirm : null, // 如果数据未加载成功，则禁用按钮
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