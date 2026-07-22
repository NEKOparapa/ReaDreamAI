// lib/ui/api/music_api_settings_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../base/api_model.dart';

class MusicApiSettingsPage extends StatefulWidget {
  final ApiModel apiModel;

  const MusicApiSettingsPage({super.key, required this.apiModel});

  @override
  State<MusicApiSettingsPage> createState() => _MusicApiSettingsPageState();
}

class _MusicApiSettingsPageState extends State<MusicApiSettingsPage> {
  final _formKey = GlobalKey<FormState>();

  // 控制器
  late TextEditingController _nameController;
  late TextEditingController _keyController;
  late TextEditingController _modelController;
  late TextEditingController _urlController;
  late TextEditingController _concurrencyController;
  late TextEditingController _rpmController;

  late ApiProvider _selectedProvider;

  // 使用定义好的音乐平台预设
  final List<ApiPlatformPreset> _platformOptions = musicPlatformPresets;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.apiModel.name);
    _keyController = TextEditingController(text: widget.apiModel.apiKey);
    _modelController = TextEditingController(text: widget.apiModel.model);
    _urlController = TextEditingController(text: widget.apiModel.url);

    // 初始化速率设置
    _concurrencyController = TextEditingController(
      text: widget.apiModel.concurrencyLimit?.toString() ?? '',
    );
    _rpmController = TextEditingController(
      text: widget.apiModel.rpm?.toString() ?? '',
    );

    _selectedProvider = widget.apiModel.provider;
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
        format: widget.apiModel.format,
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
      appBar: AppBar(title: const Text('音乐接口设置')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 32.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 第一部分：基础信息 (名称、Key、模型)
                    _buildSectionTitle('基础信息'),
                    _buildTextField(
                      _nameController,
                      '接口名称',
                      '例如：Minimax Music',
                    ),
                    _buildTextField(
                      _keyController,
                      'API Key',
                      '请输入 API Key / Group ID',
                    ),
                    _buildTextField(_modelController, '模型名称', '例如：music-2.5+'),

                    const SizedBox(height: 24),

                    // 第二部分：接口平台 (选择器 + URL)
                    _buildSectionTitle('接口平台'),
                    _buildPlatformSelector(),
                    const SizedBox(height: 16),
                    _buildUrlField(),

                    const SizedBox(height: 24),

                    // 第三部分：接口速率 (并发、RPM)
                    _buildRateLimitSection(),
                  ],
                ),
              ),
            ),
          ),
          _buildBottomActionBar(),
        ],
      ),
    );
  }

  // 底部保存栏
  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.save),
          label: const Text(
            '保存配置',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          onPressed: _saveAndExit,
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint,
  ) {
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
          fillColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        ),
        validator: (value) {
          // Key 和 Model 允许为空
          if (controller == _keyController || controller == _modelController) {
            return null;
          }
          if (value == null || value.isEmpty) return '此项不能为空';
          return null;
        },
      ),
    );
  }

  Widget _buildUrlField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: _urlController,
        enabled: _selectedProvider == ApiProvider.custom,
        decoration: InputDecoration(
          labelText: '接口地址',
          hintText: 'https://api.example.com/v1',
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          filled: true,
          fillColor: _selectedProvider == ApiProvider.custom
              ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
              : Theme.of(context).disabledColor.withValues(alpha: 0.05),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) return '接口地址不能为空';
          return null;
        },
      ),
    );
  }

  Widget _buildNumberField(
    TextEditingController controller,
    String label,
    String hint,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          filled: true,
          fillColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _buildRateLimitSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('接口速率'),
        _buildNumberField(_concurrencyController, '并发数限制', '同时进行的最大请求数 (可选)'),
        _buildNumberField(_rpmController, 'RPM (每分钟请求数)', '每分钟允许的最大请求数 (可选)'),
      ],
    );
  }

  Widget _buildPlatformSelector() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.1,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _platformOptions.length,
      itemBuilder: (context, index) {
        final option = _platformOptions[index];
        final isSelected = _selectedProvider == option.provider;
        return InkWell(
          onTap: () {
            setState(() {
              _selectedProvider = option.provider;
              // 切换平台时，如果是预设平台，自动填入所有默认值
              if (_selectedProvider != ApiProvider.custom) {
                _urlController.text = option.defaultUrl;
                _modelController.text = option.defaultModel;
                _concurrencyController.text = option.defaultConcurrency
                    .toString();
                _rpmController.text = option.defaultRpm.toString();
              }
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Card(
            elevation: isSelected ? 4 : 0, // 选中时增加阴影
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            color: isSelected
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  option.icon,
                  size: 30,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(height: 8),
                Text(
                  option.name,
                  style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
