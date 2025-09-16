import 'package:flutter/material.dart';
import '../../base/config_service.dart';
import '../../base/default_configs.dart';
import 'widgets/settings_widgets.dart'; // 复用设置组件

class VideoSettingsPage extends StatefulWidget {
  const VideoSettingsPage({super.key});

  @override
  State<VideoSettingsPage> createState() => _VideoSettingsPageState();
}

class _VideoSettingsPageState extends State<VideoSettingsPage> {
  final ConfigService _configService = ConfigService();

  late String _selectedDuration;
  late String _selectedResolution;

  final List<String> _durationOptions = ['5s', '10s'];
  final List<String> _resolutionOptions = ['720p', '1080p'];

  @override
  void initState() {
    super.initState();
    // 从ConfigService加载设置，如果未设置则使用默认值
    _selectedDuration = _configService.getSetting('video_gen_duration', appDefaultConfigs['video_gen_duration']);
    _selectedResolution = _configService.getSetting('video_gen_resolution', appDefaultConfigs['video_gen_resolution']);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageLayout(
      title: '视频设置',
      children: [
        SettingsGroup(
          title: '输出设置',
          children: [
            // 视频时长设置
            SettingsCard(
              title: '视频时长',
              subtitle: '选择生成视频的长度',
              control: DropdownButton<String>(
                value: _selectedDuration,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                items: _durationOptions.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value));
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() => _selectedDuration = newValue);
                    _configService.modifySetting<String>('video_gen_duration', newValue);
                  }
                },
              ),
            ),
            // 视频分辨率设置
            SettingsCard(
              title: '分辨率',
              subtitle: '选择生成视频的分辨率',
              control: DropdownButton<String>(
                value: _selectedResolution,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                items: _resolutionOptions.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value));
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