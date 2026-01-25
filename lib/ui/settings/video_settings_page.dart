// lib/ui/settings/video_settings_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../base/config_service.dart';
import '../../base/default_configs.dart';
import 'widgets/settings_widgets.dart';

class VideoSettingsPage extends StatefulWidget {
  const VideoSettingsPage({super.key});

  @override
  State<VideoSettingsPage> createState() => _VideoSettingsPageState();
}

class _VideoSettingsPageState extends State<VideoSettingsPage> {
  final ConfigService _configService = ConfigService();

  late TextEditingController _durationController; // 改为文本控制器
  late String _selectedResolution;
  
  String? _durationErrorText; // 错误提示文本

  final List<String> _resolutionOptions = ['720p', '1080p'];

  @override
  void initState() {
    super.initState();
    // 加载当前时长并初始化控制器
    int duration = _configService.getSetting<int>(
      'video_gen_duration', 
      appDefaultConfigs['video_gen_duration']
    );
    _durationController = TextEditingController(text: duration.toString());
    
    _selectedResolution = _configService.getSetting(
      'video_gen_resolution', 
      appDefaultConfigs['video_gen_resolution']
    );
  }

  @override
  void dispose() {
    _durationController.dispose(); // 释放控制器
    super.dispose();
  }

  /// 验证并保存时长
  void _validateAndSaveDuration(String value) {
    final duration = int.tryParse(value);
    
    if (duration == null) {
      setState(() {
        _durationErrorText = '请输入有效数字';
      });
      return;
    }
    
    if (duration < 3 || duration > 999) {
      setState(() {
        _durationErrorText = '时长必须在 3-999 秒之间';
      });
      return;
    }
    
    // 验证通过，清除错误并保存
    setState(() {
      _durationErrorText = null;
    });
    _configService.modifySetting<int>('video_gen_duration', duration);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageLayout(
      title: '视频设置',
      children: [
        SettingsGroup(
          title: '输出设置',
          children: [
            // 视频时长设置 - 改为输入框
            SettingsCard(
              title: '视频时长',
              subtitle: '输入生成视频的长度（3-999秒）',
              control: SizedBox(
                width: 80,
                child: TextField(
                  controller: _durationController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly, // 只允许数字
                    LengthLimitingTextInputFormatter(3), // 最多3位
                  ],
                  decoration: InputDecoration(
                    suffixText: 's',
                    errorText: _durationErrorText,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  // 失焦时验证并保存
                  onEditingComplete: () {
                    _validateAndSaveDuration(_durationController.text);
                    FocusScope.of(context).unfocus();
                  },
                  // 按回车时验证并保存
                  onSubmitted: (value) {
                    _validateAndSaveDuration(value);
                  },
                ),
              ),
            ),
            
            // 视频分辨率设置（保持不变）
            SettingsCard(
              title: '分辨率',
              subtitle: '选择生成视频的分辨率',
              control: DropdownButton<String>(
                value: _selectedResolution,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                items: _resolutionOptions.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() => _selectedResolution = newValue);
                    _configService.modifySetting<String>('video_gen_resolution', newValue);
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