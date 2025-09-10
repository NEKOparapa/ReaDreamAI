import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 导入服务包以使用TextInputFormatter
import '../../base/config_service.dart';
import '../widgets/setting_card.dart';

class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({super.key});

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  final ConfigService _configService = ConfigService();
  late bool _isDarkMode;
  
  // 新增：代理设置相关的状态变量
  late bool _proxyEnabled;
  late TextEditingController _proxyPortController;

  @override
  void initState() {
    super.initState();
    _proxyPortController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    // 释放控制器资源，防止内存泄漏
    _proxyPortController.dispose();
    super.dispose();
  }

  void _loadSettings() {
    setState(() {
      _isDarkMode = _configService.getSetting<bool>('isDarkMode', false);
      
      // 新增：加载代理设置
      _proxyEnabled = _configService.getSetting<bool>('proxy_enabled', false);
      _proxyPortController.text = _configService.getSetting<String>('proxy_port', '7890');
    });
  }

  // 新增：处理代理开关变化的函数
  Future<void> _onProxyEnabledChanged(bool value) async {
    // 更新UI状态
    setState(() {
      _proxyEnabled = value;
    });
    // 保存配置
    await _configService.modifySetting<bool>('proxy_enabled', value);
    // 立即应用代理设置，实现实时生效
    _configService.applyHttpProxy();
  }
  
  // 新增：处理代理端口变化的函数
  Future<void> _onProxyPortChanged(String value) async {
    // 保存配置
    await _configService.modifySetting<String>('proxy_port', value);
    // 如果代理是开启的，则立即应用新端口
    if (_proxyEnabled) {
      _configService.applyHttpProxy();
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('应用设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8.0),
        children: [
          SettingCard(
            title: '夜间模式',
            subtitle: Text(_isDarkMode ? '切换为日间模式' : '切换为夜间模式'),
            trailing: Switch(
              value: _isDarkMode,
              onChanged: (value) async {
                await _configService.modifySetting<bool>('isDarkMode', value);
                setState(() {
                  _isDarkMode = value;
                });
                // 提示：主题的实时切换通常需要全局状态管理（如Provider/Riverpod）来通知顶层MaterialApp重建。
              },
            ),
          ),
          
          // --- 新增：网络代理设置卡片 ---
          SettingCard(
            title: '网络代理',
            trailing: Switch(
              value: _proxyEnabled,
              onChanged: _onProxyEnabledChanged,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('为应用的所有网络请求设置HTTP代理'),
                const SizedBox(height: 8),
                TextField(
                  controller: _proxyPortController,
                  enabled: _proxyEnabled, // 开关关闭时，输入框不可用
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly], // 只允许输入数字
                  decoration: const InputDecoration(
                    labelText: '代理端口',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: _onProxyPortChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}