import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../base/config_service.dart';
import '../../base/default_configs.dart';
import 'widgets/settings_widgets.dart'; // 导入新的组件

class ComfyUiSettingsPage extends StatefulWidget {
  const ComfyUiSettingsPage({super.key});

  @override
  State<ComfyUiSettingsPage> createState() => _ComfyUiSettingsPageState();
}

class _ComfyUiSettingsPageState extends State<ComfyUiSettingsPage> {
  final ConfigService _configService = ConfigService();

  late String _selectedWorkflowType;
  final List<String> _workflowTypeOptions = [
    'WAI+illustrious的API工作流',
    'WAI+NoobAI的API工作流',
    'WAI+Pony的API工作流',
    '自定义工作流',
  ];

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
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      setState(() => _controllers['comfyui_custom_workflow_path']!.text = path);
      _configService.modifySetting<String>('comfyui_custom_workflow_path', path);
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
              title: '工作流类型',
              subtitle: '选择用于AI绘画的ComfyUI工作流',
              control: DropdownButton<String>(
                value: _selectedWorkflowType,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                items: _workflowTypeOptions.map((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value));
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() => _selectedWorkflowType = newValue);
                    _configService.modifySetting<String>('comfyui_workflow_type', newValue);
                  }
                },
              ),
            ),
            if (_selectedWorkflowType == '自定义工作流')
              SettingsCard(
                title: '自定义工作流文件',
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
          title: '输出节点',
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