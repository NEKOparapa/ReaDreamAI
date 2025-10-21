// lib/ui/settings/widgets/version_check_dialog.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

// 定义检查状态
enum VersionCheckStatus {
  checking,
  upToDate,
  newVersionAvailable,
  error,
}

class VersionCheckDialog extends StatefulWidget {
  final String currentVersion;
  final String appName;
  final String buildNumber;

  const VersionCheckDialog({
    super.key,
    required this.currentVersion,
    required this.appName,
    required this.buildNumber,
  });

  @override
  State<VersionCheckDialog> createState() => _VersionCheckDialogState();
}

class _VersionCheckDialogState extends State<VersionCheckDialog> {
  VersionCheckStatus _status = VersionCheckStatus.checking;
  String _latestVersion = '';
  String _releaseNotes = '';
  String _releaseUrl = '';
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  // 比较版本号
  // 返回值:
  // > 0: remoteVersion > localVersion (有新版)
  // = 0: remoteVersion = localVersion (版本相同)
  // < 0: remoteVersion < localVersion (本地版本更新？)
  int _compareVersions(String localVersion, String remoteVersion) {
    final localParts = localVersion.split('.').map(int.parse).toList();
    final remoteParts = remoteVersion.split('.').map(int.parse).toList();

    final minLength = localParts.length < remoteParts.length ? localParts.length : remoteParts.length;

    for (int i = 0; i < minLength; i++) {
      if (remoteParts[i] > localParts[i]) return 1;
      if (remoteParts[i] < localParts[i]) return -1;
    }

    if (remoteParts.length > localParts.length) return 1;
    if (remoteParts.length < localParts.length) return -1;
    
    return 0;
  }

  Future<void> _checkForUpdates() async {
    try {
      const owner = 'NEKOparapa';
      const repo = 'ReaDreamAI';
      final url = Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest');
      
      final response = await http.get(url);

      // 关键修复 #1：在异步操作完成后，首先检查 widget 是否仍然挂载。
      // 如果已卸载，则直接返回，不执行任何后续的UI更新操作。
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tagName = data['tag_name'] as String;
        final versionRegex = RegExp(r'(\d+\.\d+\.\d+)');
        final match = versionRegex.firstMatch(tagName);

        if (match == null) {
          throw Exception('无法从tag中解析版本号');
        }

        final latestVersionStr = match.group(1)!;

        if (_compareVersions(widget.currentVersion, latestVersionStr) > 0) {
          // 为了提高效率，将多个状态更新合并到一个 setState 调用中
          setState(() {
            _latestVersion = latestVersionStr;
            _releaseUrl = data['html_url'] as String;
            _releaseNotes = data['body'] as String? ?? '暂无更新说明。';
            _status = VersionCheckStatus.newVersionAvailable;
          });
        } else {
          setState(() {
            _status = VersionCheckStatus.upToDate;
          });
        }

      } else {
        throw Exception('未能获取版本信息: ${response.statusCode}');
      }
    } catch (e) {
      // 关键修复 #2：在 catch 块中也需要检查 mounted 属性。
      // 因为错误也可能在 widget 被 dispose 后才捕获到。
      if (mounted) {
        setState(() {
          _status = VersionCheckStatus.error;
          _errorMessage = e.toString();
        });
      } else {
        // (可选) 如果你想在调试时知道发生了什么，可以打印日志
        debugPrint('Version check error after dispose: $e');
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开链接: $url')),
        );
      }
    }
  }

  Widget _buildContent() {
    switch (_status) {
      case VersionCheckStatus.checking:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在检查更新...'),
          ],
        );
      case VersionCheckStatus.upToDate:
        return Text('您目前使用的是最新版本 (v${widget.currentVersion})。');
      case VersionCheckStatus.newVersionAvailable:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('发现新版本: v$_latestVersion', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('当前版本: v${widget.currentVersion}'),
            const SizedBox(height: 16),
            const Text('更新日志:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            // 为了防止更新日志过长，限制其高度并使其可滚动
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                child: Text(_releaseNotes, style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          ],
        );
      case VersionCheckStatus.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('检查更新失败。'),
            const SizedBox(height: 8),
            Text('错误: $_errorMessage', style: Theme.of(context).textTheme.bodySmall),
          ],
        );
    }
  }

  List<Widget> _buildActions() {
    List<Widget> actions = [];
    if (_status == VersionCheckStatus.newVersionAvailable) {
      actions.add(
        TextButton(
          onPressed: () => _launchUrl(_releaseUrl),
          child: const Text('前往下载'),
        ),
      );
    }
    actions.add(
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭'),
      ),
    );
    return actions;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.appName),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('版本: ${widget.currentVersion} (Build ${widget.buildNumber})'),
          const Divider(height: 24),
          // 动态内容区域
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _buildContent(),
          ),
        ],
      ),
      actions: _buildActions(),
    );
  }
}