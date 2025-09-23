import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../base/config_service.dart';
import '../../../base/default_configs.dart';
import 'widgets/settings_widgets.dart';

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

  // 1. 直接在此处定义语言选项的映射
  final Map<String, String> _languageOptions = {
    'zh-CN': '简中',
    'zh-TW': '繁中',
    'ko': '韩语',
    'ja': '日语',
    'en': '英语',
    'ru': '俄语',
  };

  @override
  void initState() {
    super.initState();
    _tokensController = TextEditingController(
      text: _configService.getSetting('translation_tokens', appDefaultConfigs['translation_tokens']).toString(),
    );
    // 从配置中加载语言代号
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

  @override
  Widget build(BuildContext context) {
    return SettingsPageLayout(
      title: '翻译设置',
      children: [
        SettingsGroup(
          title: '处理设置',
          children: [
            SettingsCard(
              title: '文本切分数 (tokens)',
              subtitle: '单次翻译请求处理的文本量',
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
                    hintText: '${appDefaultConfigs['translation_tokens']}',
                  ),
                ),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '语言选项',
          children: [
            SettingsCard(
              title: '原文语言',
              subtitle: '选择文本的原始语言',
              control: DropdownButton<String>(
                value: _sourceLang,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                items: _languageOptions.entries.map<DropdownMenuItem<String>>((entry) {
                  return DropdownMenuItem<String>(
                    value: entry.key,      // value 是代号
                    child: Text(entry.value), // child 显示的是名称
                  );
                }).toList(),
                onChanged: (String? newValue) { 
                  if (newValue != null) {
                    setState(() => _sourceLang = newValue);
                    // 保存代号到配置
                    _configService.modifySetting<String>('translation_source_lang', newValue);
                  }
                },
              ),
            ),
            SettingsCard(
              title: '译文语言',
              subtitle: '选择要翻译成的目标语言',
              control: DropdownButton<String>(
                value: _targetLang,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                items: _languageOptions.entries.map<DropdownMenuItem<String>>((entry) {
                  return DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() => _targetLang = newValue);
                    _configService.modifySetting<String>('translation_target_lang', newValue);
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