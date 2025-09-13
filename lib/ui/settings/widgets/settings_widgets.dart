import 'package:flutter/material.dart';

/// 统一的设置页面布局
class SettingsPageLayout extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SettingsPageLayout({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: Container(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          children: children,
        ),
      ),
    );
  }
}

/// 设置项卡片组
class SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SettingsGroup({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, top: 16.0, bottom: 8.0),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        ...children,
      ],
    );
  }
}

/// 单个设置项卡片
class SettingsCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget control;
  final VoidCallback? onTap;

  const SettingsCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.control,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 1.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      // 使用 clipBehavior 保证 InkWell 的水波纹效果不会超出圆角
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          // 调整内边距，让卡片内容有更多呼吸空间
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 左侧的标题和描述文本
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    // 只有当 subtitle 存在且不为空时才显示
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      // 在标题和描述之间添加明确的垂直间距
                      const SizedBox(height: 4.0),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              // 右侧的控制组件
              // 在文本和控件之间也增加一些间距
              const SizedBox(width: 16.0),
              control,
            ],
          ),
        ),
      ),
    );
  }
}