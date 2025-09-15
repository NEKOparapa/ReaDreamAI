// lib/ui/settings/app_settings_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart'; 
import '../../base/config_service.dart';
import '../../base/config_backup_service.dart';
import 'widgets/settings_widgets.dart';

class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({super.key});

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  final ConfigService _configService = ConfigService();
  final ConfigBackupService _backupService = ConfigBackupService();
  late bool _isDarkMode;
  late bool _proxyEnabled;
  late TextEditingController _proxyPortController;

  bool _isExporting = false;
  bool _isImporting = false;

  // GitHub 项目主页的 URL
  final Uri _githubUrl = Uri.parse('https://github.com');

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

  Future<void> _exportSettings() async {
    setState(() => _isExporting = true);
    final success = await _backupService.exportConfiguration();
    if (!mounted) return;
    setState(() => _isExporting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? '配置导出成功！' : '导出失败，请检查应用权限或查看日志。'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _importSettings() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 确认导入配置'),
        content: const Text('此操作将覆盖您当前的所有数据（包括设置、书架、角色卡片等），且无法撤销。导入成功后应用将需要重启。\n\n您确定要继续吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认导入')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isImporting = true);
    final success = await _backupService.importConfiguration();
    if (!mounted) return;
    setState(() => _isImporting = false);

    if (success) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('导入成功'),
          content: const Text('配置已成功恢复。应用现在需要关闭以应用更改，请您手动重新启动。'),
          actions: [
            FilledButton(
              onPressed: () => SystemNavigator.pop(), // 关闭应用
              child: const Text('关闭应用'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('导入失败，文件可能已损坏或权限不足。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // 处理 URL 跳转
  Future<void> _launchUrl(Uri url) async {
    // 使用外部应用（如浏览器）打开链接
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开链接: ${url.toString()}')),
        );
      }
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
        SettingsGroup(
          title: '数据管理',
          children: [
            SettingsCard(
              title: '导出配置',
              subtitle: '备份所有设置、书架、角色卡片及图片',
              control: _isExporting
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                  : const Icon(Icons.file_upload_outlined),
              onTap: _isExporting || _isImporting ? null : _exportSettings,
            ),
            SettingsCard(
              title: '导入配置',
              subtitle: '从备份文件恢复。将覆盖当前所有数据！',
              control: _isImporting
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                  : const Icon(Icons.file_download_outlined),
              onTap: _isExporting || _isImporting ? null : _importSettings,
            ),
          ],
        ),

        SettingsGroup(
          title: '关于',
          children: [
            SettingsCard(
              title: '项目主页',
              subtitle: '在 GitHub 上查看本项目',
              control: const Icon(Icons.open_in_new), // 使用一个表示“打开新页面”的图标
              onTap: () => _launchUrl(_githubUrl),   // 点击时调用跳转方法
            ),
          ],
        ),
      ],
    );
  }
}