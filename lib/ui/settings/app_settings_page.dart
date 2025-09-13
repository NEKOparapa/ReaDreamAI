import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../base/config_service.dart';
import 'widgets/settings_widgets.dart';

class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({super.key});

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  final ConfigService _configService = ConfigService();
  late bool _isDarkMode;
  late bool _proxyEnabled;
  late TextEditingController _proxyPortController;

  @override
  void initState() {
    super.initState();
    _proxyPortController = TextEditingController();
    _loadSettings();

    _proxyPortController.addListener(() {
      _onProxyPortChanged(_proxyPortController.text);
    });
  }

  @override
  void dispose() {
    _proxyPortController.dispose();
    super.dispose();
  }

  void _loadSettings() {
    setState(() {
      _isDarkMode = _configService.getSetting<bool>('isDarkMode', false);
      _proxyEnabled = _configService.getSetting<bool>('proxy_enabled', false);
      _proxyPortController.text = _configService.getSetting<String>('proxy_port', '7890');
    });
  }

  Future<void> _onProxyEnabledChanged(bool value) async {
    setState(() => _proxyEnabled = value);
    await _configService.modifySetting<bool>('proxy_enabled', value);
    _configService.applyHttpProxy();
  }

  Future<void> _onProxyPortChanged(String value) async {
    await _configService.modifySetting<String>('proxy_port', value);
    if (_proxyEnabled) {
      _configService.applyHttpProxy();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageLayout(
      title: '应用设置',
      children: [
        SettingsGroup(
          title: '外观',
          children: [
            SettingsCard(
              title: '夜间模式',
              subtitle: _isDarkMode ? '已开启，点击切换' : '已关闭，点击切换',
              control: Switch(
                value: _isDarkMode,
                onChanged: (value) async {
                  await _configService.modifySetting<bool>('isDarkMode', value);
                  setState(() => _isDarkMode = value);
                },
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '网络',
          children: [
            Card(
              margin: const EdgeInsets.only(bottom: 12.0),
              elevation: 0.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '网络代理',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 4.0),
                              Text(
                                '为应用的所有网络请求设置HTTP代理',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16.0),
                        Switch(
                          value: _proxyEnabled,
                          onChanged: _onProxyEnabledChanged,
                        ),
                      ],
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: _proxyEnabled
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 16.0),
                            child: TextField(
                              controller: _proxyPortController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(
                                labelText: '代理端口 (例如: 7890)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}