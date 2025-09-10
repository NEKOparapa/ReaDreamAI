// lib/ui/settings/image_gen_settings_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../base/config_service.dart';
import '../widgets/setting_card.dart';
import '../../base/default_configs.dart';

class ImageGenSettingsPage extends StatefulWidget {
  const ImageGenSettingsPage({super.key});

  @override
  State<ImageGenSettingsPage> createState() => _ImageGenSettingsPageState();
}

class _ImageGenSettingsPageState extends State<ImageGenSettingsPage> {
  final ConfigService _configService = ConfigService();

  // 文本框控制器
  late final TextEditingController _tokensController;

  // 数值状态
  late int _scenesPerChapter;
  late int _imagesPerScene;
  // 新增：生图大小状态
  late String _selectedSize;
  final List<String> _sizeOptions = ['1024*1024', '768*1024', '1280*720'];

  @override
  void initState() {
    super.initState();
    // 加载配置
    _tokensController = TextEditingController(
      text: _configService.getSetting('image_gen_tokens', appDefaultConfigs['image_gen_tokens']).toString(),
    );
    _scenesPerChapter = _configService.getSetting('image_gen_scenes_per_chapter', appDefaultConfigs['image_gen_scenes_per_chapter']);
    _imagesPerScene = _configService.getSetting('image_gen_images_per_scene', appDefaultConfigs['image_gen_images_per_scene']);
    // 新增：加载生图大小配置
    _selectedSize = _configService.getSetting('image_gen_size', appDefaultConfigs['image_gen_size']);

    // 为文本框添加监听器以自动保存
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

  // 数值步进器组件
  Widget _buildNumberStepper({
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > 1 ? () => onChanged(value - 1) : null, // 最小值限制为1
        ),
        Text(value.toString(), style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => onChanged(value + 1),
        ),
      ],
    );
  }

  // 文本输入框组件
  Widget _buildTextField({
    required TextEditingController controller,
    required String key,
  }) {
    return SizedBox(
      width: 100,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.end,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: '默认 ${appDefaultConfigs[key]}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('生图设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8.0),
        children: [
          SettingCard(
            title: '文本切分数 (tokens)',
            subtitle: const Text('将小说内容按指定字数（token）切分成块，每一块生成一次场景描述。数值越大，一次处理的文本越多。'),
            trailing: _buildTextField(
              controller: _tokensController,
              key: 'image_gen_tokens',
            ),
          ),
          SettingCard(
            title: '每章节场景数',
            subtitle: const Text('AI从每个章节中挑选并生成场景描述的数量。'),
            trailing: _buildNumberStepper(
              value: _scenesPerChapter,
              onChanged: (newValue) {
                setState(() {
                  _scenesPerChapter = newValue;
                });
                _configService.modifySetting<int>('image_gen_scenes_per_chapter', newValue);
              },
            ),
          ),
          SettingCard(
            title: '每场景图片数',
            subtitle: const Text('根据每个场景描述词生成的图片数量。'),
            trailing: _buildNumberStepper(
              value: _imagesPerScene,
              onChanged: (newValue) {
                setState(() {
                  _imagesPerScene = newValue;
                });
                _configService.modifySetting<int>('image_gen_images_per_scene', newValue);
              },
            ),
          ),
          // 新增：生图大小选择
          SettingCard(
            title: '生图大小',
            subtitle: const Text('选择生成图片的分辨率。'),
            trailing: DropdownButton<String>(
              value: _selectedSize,
              underline: const SizedBox.shrink(),
              items: _sizeOptions.map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedSize = newValue;
                  });
                  _configService.modifySetting<String>('image_gen_size', newValue);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}