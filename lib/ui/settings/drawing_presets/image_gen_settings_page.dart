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
  
  late int _scenesPerChapter;
  late int _imagesPerScene;
  late String _selectedSize;
  final List<String> _sizeOptions = ['1024*1024', '768*1024', '1280*720'];

  @override
  void initState() {
    super.initState();
    // 加载配置
    _scenesPerChapter = _configService.getSetting('image_gen_scenes_per_chapter', appDefaultConfigs['image_gen_scenes_per_chapter']);
    _imagesPerScene = _configService.getSetting('image_gen_images_per_scene', appDefaultConfigs['image_gen_images_per_scene']);
    _selectedSize = _configService.getSetting('image_gen_size', appDefaultConfigs['image_gen_size']);

    // 初始化控制器
    _tokensController = TextEditingController(
      text: _configService.getSetting('image_gen_tokens', appDefaultConfigs['image_gen_tokens']).toString(),
    );
    _scenesController = TextEditingController(text: _scenesPerChapter.toString());
    _imagesController = TextEditingController(text: _imagesPerScene.toString());

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
        _configService.modifySetting<int>('image_gen_scenes_per_chapter', value);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 统一样式，避免重复代码
    final inputDecoration = InputDecoration(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      isDense: true,
    );

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