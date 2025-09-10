// lib/ui/settings/drawing_tags_settings_page.dart

import 'package:flutter/material.dart';
import '../widgets/setting_entry_card.dart';
import 'drawing_tags/tag_category_page.dart';
import 'drawing_tags/character_settings_page.dart';

class DrawingTagsSettingsPage extends StatelessWidget {
  const DrawingTagsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('绘图标签设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8.0),
        children: [
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
          SettingEntryCard(
            icon: Icons.high_quality_outlined,
            title: '绘图质量',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TagCategoryPage(
                    title: '绘图质量',
                    cardsConfigKey: 'drawing_quality_tags',
                    activeIdConfigKey: 'active_drawing_quality_tag_id',
                  ),
                ),
              );
            },
          ),
          SettingEntryCard(
            icon: Icons.brush_outlined,
            title: '艺术家',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TagCategoryPage(
                    title: '艺术家',
                    cardsConfigKey: 'drawing_artist_tags',
                    activeIdConfigKey: 'active_drawing_artist_tag_id',
                  ),
                ),
              );
            },
          ),
          SettingEntryCard(
            icon: Icons.style_outlined,
            title: '绘画风格',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TagCategoryPage(
                    title: '绘画风格',
                    cardsConfigKey: 'drawing_style_tags',
                    activeIdConfigKey: 'active_drawing_style_tag_id',
                  ),
                ),
              );
            },
          ),
          SettingEntryCard(
            icon: Icons.label_outline,
            title: '其他标签',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TagCategoryPage(
                    title: '其他标签',
                    cardsConfigKey: 'drawing_other_tags',
                    activeIdConfigKey: 'active_drawing_other_tag_id',
                  ),
                ),
              );
            },
          ),
          SettingEntryCard(
            icon: Icons.mood_bad_outlined,
            title: '负面标签',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TagCategoryPage(
                    title: '负面标签',
                    cardsConfigKey: 'drawing_negative_tags',
                    activeIdConfigKey: 'active_drawing_negative_tag_id',
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}