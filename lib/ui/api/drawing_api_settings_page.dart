// lib/ui/api/drawing_api_settings_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/api_model.dart';

class DrawingApiSettingsPage extends StatefulWidget {
  final ApiModel apiModel;

  const DrawingApiSettingsPage({
    super.key,
    required this.apiModel,
  });

  @override
  State<DrawingApiSettingsPage> createState() => _DrawingApiSettingsPageState();
}

class _DrawingApiSettingsPageState extends State<DrawingApiSettingsPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _apiKeyController;
  late TextEditingController _accessKeyController;
  late TextEditingController _secretKeyController;
  late TextEditingController _modelController;
  late TextEditingController _urlController;
  late TextEditingController _concurrencyController;
  late TextEditingController _rpmController;

  late ApiProvider _selectedProvider;

  // 直接从 api_model.dart 获取预设平台列表
  final List<ApiPlatformPreset> _platformOptions = drawingPlatformPresets;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.apiModel.name);
    _apiKeyController = TextEditingController(text: widget.apiModel.apiKey);
    _accessKeyController = TextEditingController(text: widget.apiModel.accessKey);
    _secretKeyController = TextEditingController(text: widget.apiModel.secretKey);
    _modelController = TextEditingController(text: widget.apiModel.model);
    _urlController = TextEditingController(text: widget.apiModel.url);
    _concurrencyController = TextEditingController(text: widget.apiModel.concurrencyLimit?.toString() ?? '');
    _rpmController = TextEditingController(text: widget.apiModel.rpm?.toString() ?? '');

    _selectedProvider = widget.apiModel.provider;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _apiKeyController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    _modelController.dispose();
    _urlController.dispose();
    _concurrencyController.dispose();
    _rpmController.dispose();
    super.dispose();
  }

  void _saveAndExit() {
    if (_formKey.currentState!.validate()) {
      final updatedModel = ApiModel(
        id: widget.apiModel.id,
        name: _nameController.text,
        apiKey: _apiKeyController.text,
        accessKey: _accessKeyController.text,
        secretKey: _secretKeyController.text,
        model: _modelController.text,
        provider: _selectedProvider,
        url: _urlController.text,
        format: widget.apiModel.format,
        concurrencyLimit: int.tryParse(_concurrencyController.text),
        rpm: int.tryParse(_rpmController.text),
      );
      Navigator.pop(context, updatedModel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('绘画接口设置'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionTitle('基础信息'),
              _buildTextField(_nameController, '接口命名', '为你的接口取一个好记的名字', isRequired: true),
              _buildTextField(_modelController, '模型选择', '例如：sdxl-lightning, wanx-v1', isRequired: true),
              const SizedBox(height: 24),

              _buildSectionTitle('接口平台'),
              _buildPlatformSelector(),
              const SizedBox(height: 16),
              
              _buildUrlField(),
              ..._buildAuthFields(),

              const SizedBox(height: 24),
              _buildRateLimitSection(),

              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _saveAndExit,
                icon: const Icon(Icons.save),
                label: const Text('保存配置'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // _buildSectionTitle, _buildTextField, _buildNumberField, _buildRateLimitSection, _buildAuthFields, _buildUrlField 方法保持不变
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, String hint, {bool isRequired = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        ),
        validator: (value) {
          if (isRequired && (value == null || value.isEmpty)) {
            return '此项不能为空';
          }
          return null;
        },
      ),
    );
  }
  
  Widget _buildNumberField(TextEditingController controller, String label, String hint) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly
        ],
      ),
    );
  }

  Widget _buildRateLimitSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('接口速率'),
        _buildNumberField(
          _concurrencyController,
          '并发数限制',
          '同时进行的最大请求数 (可选)',
        ),
        _buildNumberField(
          _rpmController,
          'RPM (每分钟请求数)',
          '每分钟允许的最大请求数 (可选)',
        ),
      ],
    );
  }

  List<Widget> _buildAuthFields() {
    switch (_selectedProvider) {
      case ApiProvider.volcengine:
      case ApiProvider.google:
      case ApiProvider.dashscope:
      case ApiProvider.custom:
        return [_buildTextField(_apiKeyController, 'API Key', '请输入平台的 API Key', isRequired: true)];
      case ApiProvider.kling:
        return [
          _buildTextField(_accessKeyController, 'Access Key', '请输入平台的 Access Key', isRequired: true),
          _buildTextField(_secretKeyController, 'Secret Key', '请输入平台的 Secret Key', isRequired: true),
        ];
      case ApiProvider.comfyui:
        return [_buildTextField(_apiKeyController, 'API Key (可选)', '如果ComfyUI启动时设置了--api-key，请在此输入')];
      default:
        return [];
    }
  }

  Widget _buildUrlField() {
    final bool isUrlEditable = _selectedProvider == ApiProvider.custom || _selectedProvider == ApiProvider.comfyui;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: _urlController,
        enabled: isUrlEditable,
        decoration: InputDecoration(
          labelText: '接口地址',
          hintText: isUrlEditable ? '请输入完整的接口URL' : '此平台使用固定地址',
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        ),
        validator: (value) {
          if (isUrlEditable) {
            if (value == null || value.isEmpty) {
              return '接口地址不能为空';
            }
            if (!Uri.tryParse(value)!.isAbsolute) {
              return '请输入有效的URL';
            }
          }
          return null;
        },
      ),
    );
  }
  
  // onTap 逻辑保持不变
  Widget _buildPlatformSelector() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: _platformOptions.length,
      itemBuilder: (context, index) {
        final option = _platformOptions[index];
        final isSelected = _selectedProvider == option.provider;

        return InkWell(
          onTap: () {
            setState(() {
              _selectedProvider = option.provider;
              final bool isEditable = _selectedProvider == ApiProvider.custom || _selectedProvider == ApiProvider.comfyui;

              if (!isEditable) {
                _urlController.text = option.defaultUrl;
                _modelController.text = option.defaultModel;
                _concurrencyController.text = option.defaultConcurrency.toString();
                _rpmController.text = option.defaultRpm.toString();
              } else { 
                if (widget.apiModel.provider == _selectedProvider) {
                  _urlController.text = widget.apiModel.url;
                  _modelController.text = widget.apiModel.model;
                  _concurrencyController.text = widget.apiModel.concurrencyLimit?.toString() ?? '';
                  _rpmController.text = widget.apiModel.rpm?.toString() ?? '';
                } else {
                  _urlController.text = option.defaultUrl;
                  _modelController.text = option.defaultModel;
                  _concurrencyController.text = option.defaultConcurrency.toString();
                  _rpmController.text = option.defaultRpm.toString();
                }
              }
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Card(
            elevation: isSelected ? 4 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
            color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(option.icon, size: 36, color: isSelected ? Theme.of(context).colorScheme.primary : null),
                const SizedBox(height: 8),
                Text(option.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
              ],
            ),
          ),
        );
      },
    );
  }
}