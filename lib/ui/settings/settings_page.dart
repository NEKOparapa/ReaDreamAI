// lib/ui/settings/settings_page.dart

import 'package:flutter/material.dart';
import 'widgets/setting_entry_card.dart'; // 引入一级入口卡片
import 'app_settings_page.dart'; // 引入应用设置页
import 'comfyui_settings_page.dart'; // 引入ComfyUI设置页
import 'drawing_presets/drawing_presets_settings_page.dart'; // 引入绘图预设设置页
import 'translation_settings_page.dart'; // 引入翻译设置页
import 'video_settings_page.dart'; // 引入视频设置页
import 'log_history_page.dart'; // 引入日志历史页
import 'character_settings/character_settings_page.dart'; // 引入角色设定页
import 'writing_presets/writing_presets_settings_page.dart'; // 引入写作预设设置页


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
          // 角色设定卡片 (位置调整)
          SettingEntryCard(
            icon: Icons.person_outline,
            title: '角色设定',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CharacterSettingsPage()),
              );
            },
          ),
          // 绘图预设卡片
          SettingEntryCard(
            icon: Icons.label_important_outline,
            title: '绘画预设',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DrawingTagsSettingsPage()),
              );
            },
          ),
          // 写作预设卡片
          SettingEntryCard(
            icon: Icons.edit_note_outlined,
            title: '写作预设',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const WritingPresetsSettingsPage()),
              );
            },
          ),
          SettingEntryCard(
            icon: Icons.videocam_outlined,
            title: '视频设置',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const VideoSettingsPage()),
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
          // 日志历史卡片
          SettingEntryCard(
            icon: Icons.history_outlined,
            title: '日志历史',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LogHistoryPage()),
              );
            },
          ),
        ],
      ),
    );
  }
}