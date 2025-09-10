// lib/ui/settings/settings_page.dart

import 'package:flutter/material.dart';
import '../widgets/setting_entry_card.dart'; // 引入一级入口卡片
import 'app_settings_page.dart'; // 引入应用设置页
import 'comfyui_settings_page.dart'; // 引入ComfyUI设置页
import 'drawing_tags_settings_page.dart'; // 引入绘图标签设置页
import 'image_gen_settings_page.dart'; // 引入生图设置页
import 'translation_settings_page.dart'; // 引入翻译设置页

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        // 给列表一些顶部边距
        padding: const EdgeInsets.only(top: 8.0),
        children: [
          // 生图设置卡片
          SettingEntryCard(
            icon: Icons.image_outlined,
            title: '生图设置',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ImageGenSettingsPage()),
              );
            },
          ),
          // 绘图标签设置卡片
          SettingEntryCard(
            icon: Icons.label_important_outline,
            title: '绘图预设',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DrawingTagsSettingsPage()),
              );
            },
          ),
          // ComfyUI节点设置卡片
          SettingEntryCard(
            icon: Icons.hub_outlined,
            title: 'ComfyUI设置',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ComfyUiSettingsPage()),
              );
            },
          ),
          //  翻译设置卡片
          SettingEntryCard(
            icon: Icons.translate,
            title: '翻译设置',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const TranslationSettingsPage()),
              );
            },
          ),
          // 应用设置卡片
          SettingEntryCard(
            icon: Icons.display_settings_outlined,
            title: '应用设置',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AppSettingsPage()),
              );
            },
          ),
        ],
      ),
    );
  }
}