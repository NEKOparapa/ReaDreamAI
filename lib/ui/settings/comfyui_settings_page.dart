// lib/ui/settings/comfyui_settings_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../base/config_service.dart';
import '../../base/default_configs.dart';
import 'widgets/settings_widgets.dart';

class ComfyUiSettingsPage extends StatefulWidget {
  const ComfyUiSettingsPage({super.key});

  @override
  State<ComfyUiSettingsPage> createState() => _ComfyUiSettingsPageState();
}

class _ComfyUiSettingsPageState extends State<ComfyUiSettingsPage> {
  final ConfigService _configService = ConfigService();

  late String _selectedWorkflowType; // 现在存储的是代号，如 'wai_nsfw_sdxl'

  // 定义工作流预设，包含代号、显示名称和资源路径
  final Map<String, Map<String, String>> _workflowPresets = {
    'wai_illustrious': {
      'name': 'WAI_NSFW-illustrious-SDXL工作流',
      'path': 'assets/comfyui/WAI_NSFW-illustrious-SDXL工作流.json',
    },
    'wai_shuffle_noob': {
      'name': 'WAI-SHUFFLE-NOOB工作流',
      'path': 'assets/comfyui/WAI-SHUFFLE-NOOB工作流.json',
    },
    'custom': {
      'name': '自定义工作流',
      'path': '', // 自定义类型没有预设路径
    },
  };
  
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _selectedWorkflowType = _configService.getSetting('comfyui_workflow_type', appDefaultConfigs['comfyui_workflow_type']);

    final keys = [
      'comfyui_custom_workflow_path', 'comfyui_positive_prompt_node_id',
      'comfyui_positive_prompt_field', 'comfyui_negative_prompt_node_id',
      'comfyui_negative_prompt_field', 'comfyui_batch_size_node_id', 'comfyui_batch_size_field'
    ];

    _controllers = {
      for (var key in keys) key: _createController(key, autoSave: key != 'comfyui_custom_workflow_path')
    };
  }

  TextEditingController _createController(String key, {bool autoSave = true}) {
    final controller = TextEditingController(
      text: _configService.getSetting(key, appDefaultConfigs[key] ?? ''),
    );
    if (autoSave) {
      controller.addListener(() => _configService.modifySetting<String>(key, controller.text));
    }
    return controller;
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
  
  Future<void> _pickCustomWorkflow() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null && result.files.single.path != null) {
      final sourceFile = File(result.files.single.path!);
      final configDir = _configService.getConfigDirectoryPath();
      final workflowsDir = Directory(p.join(configDir, 'workflows'));

      if (!await workflowsDir.exists()) {
        await workflowsDir.create(recursive: true);
      }

      final fileName = p.basename(sourceFile.path);
      final newPath = p.join(workflowsDir.path, fileName);
      await sourceFile.copy(newPath);

      setState(() {
        _controllers['comfyui_custom_workflow_path']!.text = newPath;
      });
      await _configService.modifySetting<String>('comfyui_custom_workflow_path', newPath);
    }
  }

  //当工作流类型改变时调用的核心方法
  Future<void> _onWorkflowTypeChanged(String? newTypeCode) async {
    if (newTypeCode == null || newTypeCode == _selectedWorkflowType) return;

    setState(() {
      _selectedWorkflowType = newTypeCode;
    });

    // 1. 保存新的工作流类型代号
    await _configService.modifySetting<String>('comfyui_workflow_type', newTypeCode);

    // 2. 如果选择的是系统预设，则更新系统预设路径
    if (newTypeCode != 'custom') {
      final newPath = _workflowPresets[newTypeCode]!['path']!;
      await _configService.modifySetting<String>('comfyui_system_workflow_path', newPath);
    }
  }

  Widget _buildTextFieldControl(String key) {
    return SizedBox(
      width: 120,
      child: TextField(
        controller: _controllers[key],
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          isDense: true,
          hintText: '${appDefaultConfigs[key]}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customPath = _controllers['comfyui_custom_workflow_path']!.text;

    return SettingsPageLayout(
      title: 'ComfyUI设置',
      children: [
        SettingsGroup(
          title: '工作流选择',
          children: [
            SettingsCard(
              title: '文生图工作流',
              subtitle: '选择用于AI绘画的ComfyUI工作流',
              control: DropdownButton<String>(
                value: _selectedWorkflowType,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                //使用 _workflowPresets 构建下拉菜单项
                items: _workflowPresets.entries.map((entry) {
                  return DropdownMenuItem<String>(
                    value: entry.key, // 值是代号
                    child: Text(entry.value['name']!), // 显示的是名称
                  );
                }).toList(),
                onChanged: _onWorkflowTypeChanged, // 调用新的处理函数
              ),
            ),
            // 判断条件改为代号 'custom'
            if (_selectedWorkflowType == 'custom')
              SettingsCard(
                title: '自定义工作流文件(API版)',
                subtitle: customPath.isEmpty ? '请选择.json文件' : customPath,
                control: FilledButton(
                  onPressed: _pickCustomWorkflow,
                  child: const Text('选择'),
                ),
                onTap: _pickCustomWorkflow,
              ),
          ],
        ),
        SettingsGroup(
          title: '提示词节点',
          children: [
            SettingsCard(
              title: '正面提示词节点 ID',
              subtitle: 'Positive Prompt Node ID',
              control: _buildTextFieldControl('comfyui_positive_prompt_node_id'),
            ),
            SettingsCard(
              title: '输入字段',
              subtitle: 'Field name for positive prompt',
              control: _buildTextFieldControl('comfyui_positive_prompt_field'),
            ),
            SettingsCard(
              title: '负面提示词节点 ID',
              subtitle: 'Negative Prompt Node ID',
              control: _buildTextFieldControl('comfyui_negative_prompt_node_id'),
            ),
            SettingsCard(
              title: '输入字段',
              subtitle: 'Field name for negative prompt',
              control: _buildTextFieldControl('comfyui_negative_prompt_field'),
            ),
          ],
        ),
        SettingsGroup(
          title: '控制节点',
          children: [
            SettingsCard(
              title: '生图数量/尺寸节点 ID',
              subtitle: 'Batch Size/Latent Node ID',
              control: _buildTextFieldControl('comfyui_batch_size_node_id'),
            ),
            SettingsCard(
              title: '生图数量输入字段',
              subtitle: 'Field name for batch size',
              control: _buildTextFieldControl('comfyui_batch_size_field'),
            ),
          ],
        ),
      ],
    );
  }
}