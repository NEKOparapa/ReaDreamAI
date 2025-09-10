// lib/ui/settings/comfyui_settings_page.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../base/config_service.dart';
import '../widgets/setting_card.dart';
import '../../base/default_configs.dart';

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

  TextEditingController _createController(String key, {bool autoSave = true}) {
    final controller = TextEditingController(
      text: _configService.getSetting(key, appDefaultConfigs[key] ?? ''),
    );
    if (autoSave) {
      controller.addListener(() {
        _configService.modifySetting<String>(key, controller.text);
      });
    }
    return controller;
  }

  late final TextEditingController _customPathController;
  late final TextEditingController _positiveIdController;
  late final TextEditingController _positiveFieldController;
  late final TextEditingController _negativeIdController;
  late final TextEditingController _negativeFieldController;
  late final TextEditingController _batchSizeIdController;
  late final TextEditingController _batchSizeFieldController;

  @override
  void initState() {
    super.initState();
    _selectedWorkflowType = _configService.getSetting('comfyui_workflow_type', appDefaultConfigs['comfyui_workflow_type']);
    _customPathController = _createController('comfyui_custom_workflow_path', autoSave: false);
    _positiveIdController = _createController('comfyui_positive_prompt_node_id');
    _positiveFieldController = _createController('comfyui_positive_prompt_field');
    _negativeIdController = _createController('comfyui_negative_prompt_node_id');
    _negativeFieldController = _createController('comfyui_negative_prompt_field');
    _batchSizeIdController = _createController('comfyui_batch_size_node_id');
    _batchSizeFieldController = _createController('comfyui_batch_size_field');
  }

  @override
  void dispose() {
    _customPathController.dispose();
    _positiveIdController.dispose();
    _positiveFieldController.dispose();
    _negativeIdController.dispose();
    _negativeFieldController.dispose();
    _batchSizeIdController.dispose();
    _batchSizeFieldController.dispose();
    super.dispose();
  }

  Future<void> _pickCustomWorkflow() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      setState(() {
        _customPathController.text = path;
      });
      _configService.modifySetting<String>('comfyui_custom_workflow_path', path);
    }
  }

  Widget _buildTextField(TextEditingController controller, String key) {
    return SizedBox(
      width: 150,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.end,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: '默认 ${appDefaultConfigs[key]}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ComfyUI节点设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8.0),
        children: [
          // 使用标准的 Card 组件来包裹复杂的布局
          Card(
            // 使用和 SettingCard 相似的外边距以保持视觉统一
            margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Column(
              children: [
                // 这个 ListTile 用来显示标题和副标题
                const ListTile(
                  title: Text('节点工作流设置'),
                  subtitle: Text('选择用于AI绘画的ComfyUI工作流。'),
                ),
                // 这个 ListTile 包含下拉菜单
                ListTile(
                  title: const Text('工作流'),
                  trailing: DropdownButton<String>(
                    value: _selectedWorkflowType,
                    underline: const SizedBox.shrink(),
                    items: _workflowTypeOptions.map((String value) {
                      return DropdownMenuItem<String>(
                          value: value, child: Text(value));
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedWorkflowType = newValue;
                        });
                        _configService.modifySetting<String>(
                            'comfyui_workflow_type', newValue);
                      }
                    },
                  ),
                ),
                // 条件显示的 ListTile，用于选择自定义文件
                if (_selectedWorkflowType == '自定义工作流')
                  ListTile(
                    title: Text(
                      _customPathController.text.isEmpty
                          ? '请选择工作流文件'
                          : _customPathController.text,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    trailing: ElevatedButton.icon(
                      icon: const Icon(Icons.folder_open),
                      label: const Text('选择'),
                      onPressed: _pickCustomWorkflow,
                    ),
                  ),
              ],
            ),
          ),
          SettingCard(
            title: '正面提示词节点 ID',
            subtitle: const Text(
                '对应ComfyUI工作流中，接收正面提示词的节点ID。通常是"CLIP Text Encode (Prompt)"等节点。'),
            trailing: _buildTextField(
                _positiveIdController, 'comfyui_positive_prompt_node_id'),
          ),
          SettingCard(
            title: '输入字段',
            subtitle: const Text('上述节点中接收提示词文本的字段名。'),
            trailing: _buildTextField(
                _positiveFieldController, 'comfyui_positive_prompt_field'),
          ),
          SettingCard(
            title: '负面提示词节点 ID',
            subtitle: const Text('对应ComfyUI工作流中，接收负面提示词的节点ID。'),
            trailing: _buildTextField(
                _negativeIdController, 'comfyui_negative_prompt_node_id'),
          ),
          SettingCard(
            title: '输入字段',
            subtitle: const Text('上述节点中接收提示词文本的字段名。'),
            trailing: _buildTextField(
                _negativeFieldController, 'comfyui_negative_prompt_field'),
          ),
          SettingCard(
            title: '生图数量/尺寸节点 ID',
            subtitle: const Text(
                '对应ComfyUI工作流中，控制生成图片数量、宽度和高度的节点ID。通常是"Empty Latent Image"。'),
            trailing: _buildTextField(
                _batchSizeIdController, 'comfyui_batch_size_node_id'),
          ),
          SettingCard(
            title: '生图数量输入字段',
            subtitle: const Text('上述节点中控制批次大小或数量的字段名。'),
            trailing: _buildTextField(
                _batchSizeFieldController, 'comfyui_batch_size_field'),
          ),
        ],
      ),
    );
  }
}