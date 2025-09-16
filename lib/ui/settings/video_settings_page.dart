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

  // --- 修改开始 ---
  late int _selectedDuration; // 类型从 String 改为 int
  late String _selectedResolution;

  final List<int> _durationOptions = [5, 10]; // 选项列表改为 int 类型
  // --- 修改结束 ---

  final List<String> _resolutionOptions = ['720p', '1080p'];

  @override
  void initState() {
    super.initState();
    // 从ConfigService加载设置，如果未设置则使用默认值
    _selectedDuration = _configService.getSetting<int>('video_gen_duration', appDefaultConfigs['video_gen_duration']);
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
              // --- 修改开始 ---
              control: DropdownButton<int>( // 泛型改为 int
                value: _selectedDuration,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                // items 列表现在处理的是 int 类型
                items: _durationOptions.map<DropdownMenuItem<int>>((int value) {
                  return DropdownMenuItem<int>(
                    value: value, 
                    // 在Text中将 int 格式化为带 's' 的字符串用于显示
                    child: Text('${value}s') 
                  );
                }).toList(),
                // onChanged 回调接收的也是 int? 类型
                onChanged: (int? newValue) {
                  if (newValue != null) {
                    setState(() => _selectedDuration = newValue);
                    // 保存设置时，也使用 <int> 泛型
                    _configService.modifySetting<int>('video_gen_duration', newValue);
                  }
                },
              ),
              // --- 修改结束 ---
            ),
            // 视频分辨率设置 (这部分无需改动)
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