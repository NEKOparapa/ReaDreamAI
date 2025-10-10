// lib/ui/settings/writing_presets_settings_page.dart

import 'package:flutter/material.dart';
import 'widgets/setting_entry_card.dart';
import 'drawing_tags/tag_category_page.dart';

class WritingPresetsSettingsPage extends StatelessWidget {
  const WritingPresetsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('写作预设'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8.0),
        children: [
          SettingEntryCard(
            icon: Icons.map_outlined,
            title: '背景设定',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TagCategoryPage(
                    title: '背景设定',
                    cardsConfigKey: 'writing_background_cards',
                    activeIdConfigKey: 'active_writing_background_card_id',
                  ),
                ),
              );
            },
          ),
          SettingEntryCard(
            icon: Icons.style_outlined,
            title: '文风设定',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TagCategoryPage(
                    title: '文风设定',
                    cardsConfigKey: 'writing_style_cards',
                    activeIdConfigKey: 'active_writing_style_card_id',
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