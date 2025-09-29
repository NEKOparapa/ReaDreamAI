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

class _ComfyUiSettingsPageState extends State<ComfyUiSettingsPage> with SingleTickerProviderStateMixin {
  final ConfigService _configService = ConfigService();
  late TabController _tabController;
  
  late String _selectedWorkflowType;
  late String _selectedVideoWorkflowType;

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
      'path': '',
    },
  };
  
  final Map<String, Map<String, String>> _videoWorkflowPresets = {
    'video_wan2_2_14B_i2v': {
      'name': 'video_wan2_2_14B_i2v工作流',
      'path': 'assets/comfyui/video/video_wan2_2_14B_i2v.json',
    },
    'custom': {
      'name': '自定义工作流',
      'path': '',
    },
  };

  late final Map<String, TextEditingController> _controllers;
  late final Map<String, TextEditingController> _videoControllers;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    _selectedWorkflowType = _configService.getSetting('comfyui_workflow_type', appDefaultConfigs['comfyui_workflow_type']);
    _selectedVideoWorkflowType = _configService.getSetting('comfyui_video_workflow_type', appDefaultConfigs['comfyui_video_workflow_type']);

    // 文生图控制器
    final keys = [
      'comfyui_custom_workflow_path', 'comfyui_positive_prompt_node_id',
      'comfyui_positive_prompt_field', 'comfyui_negative_prompt_node_id',
      'comfyui_negative_prompt_field', 'comfyui_batch_size_node_id',
      'comfyui_latent_image_node_id',
      'comfyui_batch_size_field', 'comfyui_latent_width_field',
      'comfyui_latent_height_field'
    ];

    _controllers = {
      for (var key in keys) key: _createController(key, autoSave: key != 'comfyui_custom_workflow_path')
    };
    
    // 视频控制器 (已修改)
    final videoKeys = [
      'comfyui_video_custom_workflow_path', 'comfyui_video_positive_prompt_node_id',
      'comfyui_video_positive_prompt_field', 'comfyui_video_size_node_id', // 合并后的尺寸节点ID
      'comfyui_video_width_field', 'comfyui_video_height_field', 
      'comfyui_video_count_node_id', 'comfyui_video_count_field', 
      'comfyui_video_image_node_id', 'comfyui_video_image_field'
    ];
    
    _videoControllers = {
      for (var key in videoKeys) key: _createController(key, autoSave: key != 'comfyui_video_custom_workflow_path')
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
    _tabController.dispose();
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    for (var controller in _videoControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickCustomWorkflow({required bool isVideo}) async {
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

      if (isVideo) {
        setState(() {
          _videoControllers['comfyui_video_custom_workflow_path']!.text = newPath;
        });
        await _configService.modifySetting<String>('comfyui_video_custom_workflow_path', newPath);
      } else {
        setState(() {
          _controllers['comfyui_custom_workflow_path']!.text = newPath;
        });
        await _configService.modifySetting<String>('comfyui_custom_workflow_path', newPath);
      }
    }
  }

  Future<void> _onWorkflowTypeChanged(String? newTypeCode, {required bool isVideo}) async {
    if (newTypeCode == null) return;
    
    if (isVideo) {
      if (newTypeCode == _selectedVideoWorkflowType) return;
      
      setState(() {
        _selectedVideoWorkflowType = newTypeCode;
      });

      await _configService.modifySetting<String>('comfyui_video_workflow_type', newTypeCode);

      if (newTypeCode != 'custom') {
        final newPath = _videoWorkflowPresets[newTypeCode]!['path']!;
        await _configService.modifySetting<String>('comfyui_video_workflow_path', newPath);
      }
    } else {
      if (newTypeCode == _selectedWorkflowType) return;
      
      setState(() {
        _selectedWorkflowType = newTypeCode;
      });

      await _configService.modifySetting<String>('comfyui_workflow_type', newTypeCode);

      if (newTypeCode != 'custom') {
        final newPath = _workflowPresets[newTypeCode]!['path']!;
        await _configService.modifySetting<String>('comfyui_system_workflow_path', newPath);
      }
    }
  }

  Widget _buildTextFieldControl(String key) {
    final controllers = key.contains('video') ? _videoControllers : _controllers;
    return SizedBox(
      width: 120,
      child: TextField(
        controller: controllers[key],
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

  Widget _buildImageSettings() {
    final customPath = _controllers['comfyui_custom_workflow_path']!.text;
    
    return ListView(
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
                items: _workflowPresets.entries.map((entry) {
                  return DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value['name']!),
                  );
                }).toList(),
                onChanged: (value) => _onWorkflowTypeChanged(value, isVideo: false),
              ),
            ),
            if (_selectedWorkflowType == 'custom')
              SettingsCard(
                title: '自定义工作流文件(API版)',
                subtitle: customPath.isEmpty ? '请选择.json文件' : customPath,
                control: FilledButton(
                  onPressed: () => _pickCustomWorkflow(isVideo: false),
                  child: const Text('选择'),
                ),
                onTap: () => _pickCustomWorkflow(isVideo: false),
              ),
          ],
        ),
        SettingsGroup(
          title: '正面提示词节点',
          children: [
            SettingsCard(
              title: '节点 ID',
              subtitle: 'Positive Prompt Node ID',
              control: _buildTextFieldControl('comfyui_positive_prompt_node_id'),
            ),
            SettingsCard(
              title: '输入字段',
              subtitle: 'Field name for positive prompt',
              control: _buildTextFieldControl('comfyui_positive_prompt_field'),
            ),
          ],
        ),
        SettingsGroup(
          title: '负面提示词节点',
          children: [
            SettingsCard(
              title: '节点 ID',
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
          title: '生图数量节点',
          children: [
            SettingsCard(
              title: '节点 ID',
              subtitle: 'Batch Size Node ID',
              control: _buildTextFieldControl('comfyui_batch_size_node_id'),
            ),
            SettingsCard(
              title: '输入字段',
              subtitle: 'Field name for batch size',
              control: _buildTextFieldControl('comfyui_batch_size_field'),
            ),
          ],
        ),
        SettingsGroup(
          title: '生图尺寸节点',
          children: [
            SettingsCard(
              title: '节点 ID',
              subtitle: 'Latent Image Node ID',
              control: _buildTextFieldControl('comfyui_latent_image_node_id'),
            ),
            SettingsCard(
              title: '宽度输入字段',
              subtitle: 'Field name for latent width',
              control: _buildTextFieldControl('comfyui_latent_width_field'),
            ),
            SettingsCard(
              title: '高度输入字段',
              subtitle: 'Field name for latent height',
              control: _buildTextFieldControl('comfyui_latent_height_field'),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildVideoSettings() {
    final customPath = _videoControllers['comfyui_video_custom_workflow_path']!.text;
    
    return ListView(
      children: [
        SettingsGroup(
          title: '工作流选择',
          children: [
            SettingsCard(
              title: '文+图生视频工作流',
              subtitle: '选择用于AI视频生成的ComfyUI工作流',
              control: DropdownButton<String>(
                value: _selectedVideoWorkflowType,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                items: _videoWorkflowPresets.entries.map((entry) {
                  return DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value['name']!),
                  );
                }).toList(),
                onChanged: (value) => _onWorkflowTypeChanged(value, isVideo: true),
              ),
            ),
            if (_selectedVideoWorkflowType == 'custom')
              SettingsCard(
                title: '自定义工作流文件(API版)',
                subtitle: customPath.isEmpty ? '请选择.json文件' : customPath,
                control: FilledButton(
                  onPressed: () => _pickCustomWorkflow(isVideo: true),
                  child: const Text('选择'),
                ),
                onTap: () => _pickCustomWorkflow(isVideo: true),
              ),
          ],
        ),
        SettingsGroup(
          title: '正面提示词节点',
          children: [
            SettingsCard(
              title: '节点 ID',
              subtitle: 'Positive Prompt Node ID',
              control: _buildTextFieldControl('comfyui_video_positive_prompt_node_id'),
            ),
            SettingsCard(
              title: '输入字段',
              subtitle: 'Field name for positive prompt',
              control: _buildTextFieldControl('comfyui_video_positive_prompt_field'),
            ),
          ],
        ),
        // 负面提示词节点组已删除
        SettingsGroup(
          title: '视频分辨率节点',
          children: [
            SettingsCard(
              title: '节点 ID', // 标题简化
              subtitle: 'Width & Height Node ID', // 副标题更新
              control: _buildTextFieldControl('comfyui_video_size_node_id'), // 使用新的合并ID
            ),
            SettingsCard(
              title: '宽度输入字段',
              subtitle: 'Field name for width',
              control: _buildTextFieldControl('comfyui_video_width_field'),
            ),
            // 高度节点ID设置项已删除
            SettingsCard(
              title: '高度输入字段',
              subtitle: 'Field name for height',
              control: _buildTextFieldControl('comfyui_video_height_field'),
            ),
          ],
        ),
        SettingsGroup(
          title: '视频数量节点',
          children: [
            SettingsCard(
              title: '节点 ID',
              subtitle: 'Video Count Node ID',
              control: _buildTextFieldControl('comfyui_video_count_node_id'),
            ),
            SettingsCard(
              title: '输入字段',
              subtitle: 'Field name for count',
              control: _buildTextFieldControl('comfyui_video_count_field'),
            ),
          ],
        ),
        SettingsGroup(
          title: '参考图片节点',
          children: [
            SettingsCard(
              title: '节点 ID',
              subtitle: 'Reference Image Node ID',
              control: _buildTextFieldControl('comfyui_video_image_node_id'),
            ),
            SettingsCard(
              title: '输入字段',
              subtitle: 'Field name for image',
              control: _buildTextFieldControl('comfyui_video_image_field'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ComfyUI设置'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '绘图设置'),
            Tab(text: '视频设置'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildImageSettings(),
          _buildVideoSettings(),
        ],
      ),
    );
  }
}