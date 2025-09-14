// lib/ui/api/api_settings_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import '../../models/api_model.dart';

// 用于承载平台信息的辅助类 
class PlatformInfo {
  final ApiProvider provider;
  final String name;
  final String defaultUrl;
  final IconData icon;
  final ApiFormat defaultFormat;

  const PlatformInfo({
    required this.provider,
    required this.name,
    required this.defaultUrl,
    required this.icon,
    required this.defaultFormat,
  });
}

class ApiSettingsPage extends StatefulWidget {
  final ApiModel apiModel;

  const ApiSettingsPage({
    super.key,
    required this.apiModel,
  });

  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<ApiSettingsPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _keyController;
  late TextEditingController _modelController;
  late TextEditingController _urlController;
  late TextEditingController _concurrencyController;
  late TextEditingController _rpmController;

  late ApiProvider _selectedProvider;
  late ApiFormat _selectedFormat;

  // 预设平台选项
  final List<PlatformInfo> _platformOptions = [
    PlatformInfo(provider: ApiProvider.openai, name: 'OpenAI', defaultUrl: 'https://api.openai.com/v1', icon: Icons.cloud_outlined, defaultFormat: ApiFormat.openai),
    PlatformInfo(provider: ApiProvider.volcengine, name: 'VolcEngine', defaultUrl: 'https://ark.cn-beijing.volces.com/api/v3', icon: Icons.filter_hdr_outlined, defaultFormat: ApiFormat.openai),
    PlatformInfo(provider: ApiProvider.deepseek, name: 'DeepSeek', defaultUrl: 'https://api.deepseek.com/v1', icon: Icons.search, defaultFormat: ApiFormat.openai),
    PlatformInfo(provider: ApiProvider.google, name: 'Google', defaultUrl: 'https://generativelanguage.googleapis.com/v1beta', icon: Icons.bubble_chart_outlined, defaultFormat: ApiFormat.google),
    PlatformInfo(provider: ApiProvider.anthropic, name: 'Anthropic', defaultUrl: 'https://api.anthropic.com/v1', icon: Icons.hub_outlined, defaultFormat: ApiFormat.anthropic),
    PlatformInfo(provider: ApiProvider.custom, name: '自定义', defaultUrl: '', icon: Icons.settings_ethernet, defaultFormat: ApiFormat.openai),
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.apiModel.name);
    _keyController = TextEditingController(text: widget.apiModel.apiKey);
    _modelController = TextEditingController(text: widget.apiModel.model);
    _urlController = TextEditingController(text: widget.apiModel.url);
    _concurrencyController = TextEditingController(text: widget.apiModel.concurrencyLimit?.toString() ?? '');
    _rpmController = TextEditingController(text: widget.apiModel.rpm?.toString() ?? '');

    _selectedProvider = widget.apiModel.provider;
    _selectedFormat = widget.apiModel.format;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _keyController.dispose();
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
        apiKey: _keyController.text,
        model: _modelController.text,
        provider: _selectedProvider,
        format: _selectedFormat,
        url: _urlController.text,
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
        title: const Text('接口设置'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionTitle('基础信息'),
              _buildTextField(_nameController, '接口命名', '为你的接口取一个好记的名字'),
              _buildTextField(_keyController, '接口Key (API Key)', '请输入你的API Key'),
              _buildTextField(_modelController, '模型选择', '例如：gpt-4, gemini-pro'),
              const SizedBox(height: 24),

              _buildSectionTitle('接口平台'),
              _buildPlatformSelector(),

              const SizedBox(height: 16),
              _buildUrlField(),

              const SizedBox(height: 8),
              _buildFormatSelector(),

              // 新增：速率设置部分
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

  Widget _buildSectionTitle(String title) {
    // ... (此函数未改变)
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

  Widget _buildTextField(TextEditingController controller, String label, String hint) {
    // ... (此函数未改变)
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
          if (controller == _keyController || controller == _modelController) {
            return null;
          }
          if (value == null || value.isEmpty) {
            return '此项不能为空';
          }
          return null;
        },
      ),
    );
  }
  
  // 新增：用于数值输入的辅助方法
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
          FilteringTextInputFormatter.digitsOnly // 只允许输入数字
        ],
      ),
    );
  }

  // 新增：构建速率限制部分的UI
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

  Widget _buildUrlField() {
    // ... (此函数未改变)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: _urlController,
        enabled: _selectedProvider == ApiProvider.custom,
        decoration: InputDecoration(
          labelText: '接口地址',
          hintText: '请输入完整的接口URL',
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return '接口地址不能为空';
          }
          if (!Uri.tryParse(value)!.isAbsolute) {
            return '请输入有效的URL';
          }
          return null;
        },
      ),
    );
  }

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
              _selectedFormat = option.defaultFormat;

              if (_selectedProvider != ApiProvider.custom) {
                _urlController.text = option.defaultUrl;
              } else {
                if (widget.apiModel.provider != ApiProvider.custom) {
                  _urlController.text = '';
                } else {
                  _urlController.text = widget.apiModel.url;
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

  Widget _buildFormatSelector() {
    // ... (此函数未改变)
    bool isCustomProvider = _selectedProvider == ApiProvider.custom;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: DropdownButtonFormField<ApiFormat>(
        value: _selectedFormat,
        decoration: InputDecoration(
          labelText: '接口格式',
          border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          helperText: isCustomProvider ? '为自定义地址选择兼容的接口格式' : '此平台格式已固定，无需选择',
        ),
        onChanged: isCustomProvider
            ? (ApiFormat? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedFormat = newValue;
                  });
                }
              }
            : null,
        items: ApiFormat.values.map((ApiFormat format) {
          return DropdownMenuItem<ApiFormat>(
            value: format,
            child: Text(format.name),
          );
        }).toList(),
      ),
    );
  }
}