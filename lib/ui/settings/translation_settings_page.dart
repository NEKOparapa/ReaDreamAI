// lib/ui/settings/translation_settings_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../base/config_service.dart';
import '../widgets/setting_card.dart';
import '../../base/default_configs.dart';

class TranslationSettingsPage extends StatefulWidget {
  const TranslationSettingsPage({super.key});

  @override
  State<TranslationSettingsPage> createState() => _TranslationSettingsPageState();
}

class _TranslationSettingsPageState extends State<TranslationSettingsPage> {
  final ConfigService _configService = ConfigService();

  late final TextEditingController _tokensController;
  late String _sourceLang;
  late String _targetLang;

  // 预设语言选项
  final List<String> _languageOptions = ['English', '中文', '日本語', 'Français', 'Español', 'Deutsch', 'Русский'];

  @override
  void initState() {
    super.initState();
    _tokensController = TextEditingController(
      text: _configService.getSetting('translation_tokens', appDefaultConfigs['translation_tokens']).toString(),
    );
    _sourceLang = _configService.getSetting('translation_source_lang', appDefaultConfigs['translation_source_lang']);
    _targetLang = _configService.getSetting('translation_target_lang', appDefaultConfigs['translation_target_lang']);

    _tokensController.addListener(() {
      final value = int.tryParse(_tokensController.text);
      if (value != null) {
        _configService.modifySetting<int>('translation_tokens', value);
      }
    });
  }

  @override
  void dispose() {
    _tokensController.dispose();
    super.dispose();
  }

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

  Widget _buildLanguageDropdown({
    required String title,
    required String currentValue,
    required ValueChanged<String?> onChanged,
  }) {
    return SettingCard(
      title: title,
      trailing: DropdownButton<String>(
        value: currentValue,
        underline: const SizedBox.shrink(),
        items: _languageOptions.map<DropdownMenuItem<String>>((String value) {
          return DropdownMenuItem<String>(
            value: value,
            child: Text(value),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('翻译设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8.0),
        children: [
          SettingCard(
            title: '文本切分数 (tokens)',
            subtitle: const Text('将小说内容按指定字数（token）切分成块，每一块进行一次翻译请求。'),
            trailing: _buildTextField(
              controller: _tokensController,
              key: 'translation_tokens',
            ),
          ),
          _buildLanguageDropdown(
            title: '原文语言',
            currentValue: _sourceLang,
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() => _sourceLang = newValue);
                _configService.modifySetting<String>('translation_source_lang', newValue);
              }
            },
          ),
          _buildLanguageDropdown(
            title: '译文语言',
            currentValue: _targetLang,
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() => _targetLang = newValue);
                _configService.modifySetting<String>('translation_target_lang', newValue);
              }
            },
          ),
        ],
      ),
    );
  }
}