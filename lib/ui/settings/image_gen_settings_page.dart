import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../base/config_service.dart';
import '../../base/default_configs.dart';
import 'widgets/settings_widgets.dart'; // 导入新的组件

class ImageGenSettingsPage extends StatefulWidget {
  const ImageGenSettingsPage({super.key});

  @override
  State<ImageGenSettingsPage> createState() => _ImageGenSettingsPageState();
}

class _ImageGenSettingsPageState extends State<ImageGenSettingsPage> {
  final ConfigService _configService = ConfigService();

  late final TextEditingController _tokensController;
  late int _scenesPerChapter;
  late int _imagesPerScene;
  late String _selectedSize;
  final List<String> _sizeOptions = ['1024*1024', '768*1024', '1280*720'];

  @override
  void initState() {
    super.initState();
    _tokensController = TextEditingController(
      text: _configService.getSetting('image_gen_tokens', appDefaultConfigs['image_gen_tokens']).toString(),
    );
    _scenesPerChapter = _configService.getSetting('image_gen_scenes_per_chapter', appDefaultConfigs['image_gen_scenes_per_chapter']);
    _imagesPerScene = _configService.getSetting('image_gen_images_per_scene', appDefaultConfigs['image_gen_images_per_scene']);
    _selectedSize = _configService.getSetting('image_gen_size', appDefaultConfigs['image_gen_size']);

    _tokensController.addListener(() {
      final value = int.tryParse(_tokensController.text);
      if (value != null) {
        _configService.modifySetting<int>('image_gen_tokens', value);
      }
    });
  }

  @override
  void dispose() {
    _tokensController.dispose();
    super.dispose();
  }

  Widget _buildNumberStepperControl({
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.remove, size: 20),
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
        SizedBox(width: 16),
        Text(value.toString(), style: Theme.of(context).textTheme.titleMedium),
        SizedBox(width: 16),
        IconButton(
          icon: Icon(Icons.add, size: 20),
          onPressed: () => onChanged(value + 1),
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageLayout(
      title: '生图设置',
      children: [
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
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                    hintText: '${appDefaultConfigs['image_gen_tokens']}',
                  ),
                ),
              ),
            ),
            SettingsCard(
              title: '每章节场景数',
              subtitle: 'AI 从每个章节中提取的场景数量',
              control: _buildNumberStepperControl(
                value: _scenesPerChapter,
                onChanged: (newValue) {
                  setState(() => _scenesPerChapter = newValue);
                  _configService.modifySetting<int>('image_gen_scenes_per_chapter', newValue);
                },
              ),
            ),
            SettingsCard(
              title: '每场景图片数',
              subtitle: '为每个场景描述生成的图片数量',
              control: _buildNumberStepperControl(
                value: _imagesPerScene,
                onChanged: (newValue) {
                  setState(() => _imagesPerScene = newValue);
                  _configService.modifySetting<int>('image_gen_images_per_scene', newValue);
                },
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '输出设置',
          children: [
            SettingsCard(
              title: '图片尺寸',
              subtitle: '选择生成图片的分辨率',
              control: DropdownButton<String>(
                value: _selectedSize,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                items: _sizeOptions.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value));
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() => _selectedSize = newValue);
                    _configService.modifySetting<String>('image_gen_size', newValue);
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}