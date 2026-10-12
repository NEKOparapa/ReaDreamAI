// lib/ui/settings/drawing_presets/image_gen_settings_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../base/config_service.dart';
import '../../../base/default_configs.dart';
import '../widgets/settings_widgets.dart';

class ImageGenSettingsPage extends StatefulWidget {
  const ImageGenSettingsPage({super.key});

  @override
  State<ImageGenSettingsPage> createState() => _ImageGenSettingsPageState();
}

class _ImageGenSettingsPageState extends State<ImageGenSettingsPage> {
  final ConfigService _configService = ConfigService();

  late final TextEditingController _tokensController;
  late final TextEditingController _scenesController;
  late final TextEditingController _imagesController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;

  late int _scenesPerChapter;
  late int _imagesPerScene;
  late String _selectedSize;
  late String _appliedSize;
  late String _appliedSizeMode;
  String? _lastCustomSize;
  bool _isSavingSize = false;
  bool _showSizeErrors = false;
  static const _customSizeOption = 'custom';
  static const _sizeOptions = ['1024*1024', '768*1024', '1280*720'];

  @override
  void initState() {
    super.initState();
    // 加载配置
    _scenesPerChapter = _configService.getSetting(
      'image_gen_scenes_per_chapter',
      appDefaultConfigs['image_gen_scenes_per_chapter'],
    );
    _imagesPerScene = _configService.getSetting(
      'image_gen_images_per_scene',
      appDefaultConfigs['image_gen_images_per_scene'],
    );
    _appliedSize =
        _normalizeSize(
          _configService.getSetting<Object?>('image_gen_size', null),
        ) ??
        appDefaultConfigs['image_gen_size'] as String;
    final savedMode = _configService.getSetting<Object?>(
      'image_gen_size_mode',
      null,
    );
    _appliedSizeMode =
        savedMode == _customSizeOption || !_sizeOptions.contains(_appliedSize)
        ? _customSizeOption
        : 'preset';
    _selectedSize = _appliedSizeMode == _customSizeOption
        ? _customSizeOption
        : _appliedSize;
    _lastCustomSize =
        _normalizeSize(
          _configService.getSetting<Object?>('image_gen_custom_size', null),
        ) ??
        (_appliedSizeMode == _customSizeOption ? _appliedSize : null);

    // 初始化控制器
    _tokensController = TextEditingController(
      text: _configService
          .getSetting('image_gen_tokens', appDefaultConfigs['image_gen_tokens'])
          .toString(),
    );
    _scenesController = TextEditingController(
      text: _scenesPerChapter.toString(),
    );
    _imagesController = TextEditingController(text: _imagesPerScene.toString());
    _widthController = TextEditingController();
    _heightController = TextEditingController();
    _resetCustomSizeDraft();

    // 添加监听器
    _tokensController.addListener(() {
      final value = int.tryParse(_tokensController.text);
      if (value != null) {
        _configService.modifySetting<int>('image_gen_tokens', value);
      }
    });

    _scenesController.addListener(() {
      final value = int.tryParse(_scenesController.text);
      // 检查值是否有效且已更改
      if (value != null && value > 0 && value != _scenesPerChapter) {
        setState(() => _scenesPerChapter = value);
        _configService.modifySetting<int>(
          'image_gen_scenes_per_chapter',
          value,
        );
      }
    });

    _imagesController.addListener(() {
      final value = int.tryParse(_imagesController.text);
      // 检查值是否有效且已更改
      if (value != null && value > 0 && value != _imagesPerScene) {
        setState(() => _imagesPerScene = value);
        _configService.modifySetting<int>('image_gen_images_per_scene', value);
      }
    });
  }

  @override
  void dispose() {
    _tokensController.dispose();
    _scenesController.dispose();
    _imagesController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  String? _dimensionError(String text, String label) {
    final value = text.trim();
    if (value.isEmpty) return '请输入$label';
    if (!RegExp(r'^[0-9]+$').hasMatch(value)) return '$label必须为正整数';
    final dimension = int.tryParse(value);
    if (dimension == null) return '$label数值过大';
    if (dimension <= 0) return '$label必须大于 0';
    return null;
  }

  String? _normalizeSize(Object? value) {
    if (value is! String) return null;
    final parts = value.split('*');
    if (parts.length != 2 ||
        _dimensionError(parts[0], '宽度') != null ||
        _dimensionError(parts[1], '高度') != null) {
      return null;
    }
    return '${int.parse(parts[0].trim())}*${int.parse(parts[1].trim())}';
  }

  void _resetCustomSizeDraft() {
    final parts = (_lastCustomSize ?? _appliedSize).split('*');
    _widthController.text = parts[0];
    _heightController.text = parts[1];
    _showSizeErrors = false;
  }

  void _onSizeChanged(String? size) {
    if (size == null || _isSavingSize || size == _selectedSize) return;
    setState(() {
      _selectedSize = size;
      _resetCustomSizeDraft();
    });
    if (size != _customSizeOption) {
      _saveSize(size, mode: 'preset');
    }
  }

  void _applyCustomSize() {
    if (_isSavingSize) return;
    setState(() => _showSizeErrors = true);
    final size = _normalizeSize(
      '${_widthController.text}*${_heightController.text}',
    );
    if (size == null) return;
    _saveSize(size, mode: _customSizeOption);
  }

  Future<void> _saveSize(String size, {required String mode}) async {
    setState(() => _isSavingSize = true);
    try {
      await _configService.modifySettings({
        'image_gen_size': size,
        'image_gen_size_mode': mode,
        if (mode == _customSizeOption) 'image_gen_custom_size': size,
        // 首次应用预设时，也保留从旧配置推断出的自定义尺寸。
        if (mode != _customSizeOption && _lastCustomSize != null)
          'image_gen_custom_size': _lastCustomSize,
      });
      if (!mounted) return;
      setState(() {
        _appliedSize = size;
        _appliedSizeMode = mode;
        if (mode == _customSizeOption) _lastCustomSize = size;
        _selectedSize = mode == _customSizeOption ? _customSizeOption : size;
        _resetCustomSizeDraft();
      });
    } catch (_) {
      if (!mounted) return;
      // 自定义输入保留以便重试，预设选择恢复到此前生效的模式。
      if (mode != _customSizeOption) {
        setState(() {
          _selectedSize = _appliedSizeMode == _customSizeOption
              ? _customSizeOption
              : _appliedSize;
        });
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('图片尺寸保存失败，仍使用此前生效的尺寸，请重试。')));
    } finally {
      if (mounted) setState(() => _isSavingSize = false);
    }
  }

  Widget _buildSizeSettings() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: colors.outlineVariant),
    );

    Widget dimensionField(TextEditingController controller, String label) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          TextField(
            key: ValueKey(
              label == '宽度' ? 'image-size-width' : 'image-size-height',
            ),
            controller: controller,
            enabled: !_isSavingSize,
            keyboardType: TextInputType.number,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              // 标签留在输入框上方，避免边框被浮动标签切断。
              hintText: label,
              suffixText: 'px',
              suffixStyle: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
              filled: true,
              fillColor: colors.surfaceContainerLowest,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: fieldBorder,
              enabledBorder: fieldBorder,
              focusedBorder: fieldBorder.copyWith(
                borderSide: BorderSide(color: colors.primary, width: 2),
              ),
              errorText: _showSizeErrors
                  ? _dimensionError(controller.text, label)
                  : null,
              errorMaxLines: 2,
            ),
            onChanged: (_) => setState(() => _showSizeErrors = true),
            onSubmitted: (_) => _applyCustomSize(),
          ),
        ],
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final title = Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.photo_size_select_large_rounded,
                        size: 21,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '图片尺寸',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '选择预设，或自定义宽高',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final selector = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedSize,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    borderRadius: BorderRadius.circular(12),
                    icon: Icon(
                      Icons.expand_more_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    items: [
                      for (final size in _sizeOptions)
                        DropdownMenuItem(
                          value: size,
                          child: Text(size.replaceAll('*', ' × ')),
                        ),
                      const DropdownMenuItem(
                        value: _customSizeOption,
                        child: Text('自定义'),
                      ),
                    ],
                    onChanged: _isSavingSize ? null : _onSizeChanged,
                  ),
                );
                if (constraints.maxWidth < 520) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 16), selector],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 24),
                    SizedBox(width: 184, child: selector),
                  ],
                );
              },
            ),
            if (_selectedSize == _customSizeOption) ...[
              const SizedBox(height: 20),
              Divider(
                height: 1,
                color: colors.outlineVariant.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final widthField = dimensionField(_widthController, '宽度');
                  final heightField = dimensionField(_heightController, '高度');
                  final applyButton = FilledButton(
                    onPressed: _isSavingSize ? null : _applyCustomSize,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(96, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(_isSavingSize ? '保存中…' : '应用'),
                  );
                  final fields = constraints.maxWidth < 360
                      ? Column(
                          children: [
                            widthField,
                            const SizedBox(height: 16),
                            heightField,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: widthField),
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 12,
                                right: 12,
                                top: 39,
                              ),
                              child: Text(
                                '×',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(child: heightField),
                          ],
                        );
                  if (constraints.maxWidth < 520) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        fields,
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: applyButton,
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 504),
                            child: fields,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Padding(
                        padding: const EdgeInsets.only(top: 28),
                        child: applyButton,
                      ),
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '实际输出尺寸及支持范围取决于所选模型，部分平台会自动调整尺寸。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 统一样式，避免重复代码
    final inputDecoration = InputDecoration(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      isDense: true,
    );

    final sections = [
      SettingsGroup(
        title: '生成策略',
        children: [
          SettingsCard(
            title: '文本切分数 (tokens)',
            subtitle: '单次处理的文本量，影响场景描述的生成',
            control: SizedBox(
              width: 80,
              child: TextField(
                controller: _tokensController,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: inputDecoration.copyWith(
                  hintText: '${appDefaultConfigs['image_gen_tokens']}',
                ),
              ),
            ),
          ),
          SettingsCard(
            title: '每章节场景数',
            subtitle: 'AI 从每个章节中提取的场景数量',
            // 直接使用 TextField
            control: SizedBox(
              width: 80,
              child: TextField(
                controller: _scenesController,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: inputDecoration,
              ),
            ),
          ),
          SettingsCard(
            title: '每场景图片数',
            subtitle: '为每个场景描述生成的图片数量',
            control: SizedBox(
              width: 80,
              child: TextField(
                controller: _imagesController,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: inputDecoration,
              ),
            ),
          ),
        ],
      ),
      SettingsGroup(title: '输出设置', children: [_buildSizeSettings()]),
    ];

    return SettingsPageLayout(
      title: '生图设置',
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: sections,
            ),
          ),
        ),
      ],
    );
  }
}
