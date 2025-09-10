// lib/ui/widgets/setting_card.dart

import 'package:flutter/material.dart';

/// 具体设置页面中的设置项卡片
class SettingCard extends StatelessWidget {
  final String title;
  final Widget? subtitle; // 副标题可以是 Widget，更灵活
  final Widget? trailing; // 右侧控件，如 Switch

  const SettingCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    // 获取当前主题下的副标题文本样式
    final subtitleStyle = Theme.of(context).textTheme.bodySmall;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ListTile(
        title: Text(title),
        // 如果有副标题，添加一些顶部间距并应用样式
        subtitle: subtitle != null
            ? Padding(
                padding: const EdgeInsets.only(top: 4.0),
                // 使用 DefaultTextStyle 来统一副标题样式
                child: DefaultTextStyle(
                  style: subtitleStyle ?? const TextStyle(color: Colors.grey),
                  child: subtitle!,
                ),
              )
            : null,
        trailing: trailing,
      ),
    );
  }
}