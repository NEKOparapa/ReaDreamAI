// lib/ui/main/main_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bookshelf/bookshelf_page.dart';
import '../api/api_management_page.dart';
import '../settings/settings_page.dart';
import '../tasks/task_management_page.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const BookshelfPage(),       // 0: 书架页
    const TaskManagementPage(),  // 1: 任务管理页
    const ApiManagementPage(),   // 2: API管理页
    const SettingsPage(),        // 3: 设置页
  ];

  final List<NavigationItem> _navigationItems = const [
    NavigationItem(
      icon: Icon(Icons.book_outlined),
      selectedIcon: Icon(Icons.book),
      label: '书架',
    ),
    NavigationItem(
      icon: Icon(Icons.task_alt_outlined),
      selectedIcon: Icon(Icons.task_alt),
      label: '任务',
    ),
    NavigationItem(
      icon: Icon(Icons.api_outlined),
      selectedIcon: Icon(Icons.api),
      label: '接口',
    ),
    NavigationItem(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: '设置',
    ),
  ];
  
  // 定义打开 GitHub 的方法
  Future<void> _launchGitHubUrl() async {
    final Uri url = Uri.parse('https://github.com/NEKOparapa/ReaDreamAI'); 
    if (!await launchUrl(url)) {
      // 如果无法启动 URL，可以在这里给用户一些提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开链接')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 根据平台判断是否为桌面端（非Android、iOS），以决定是否显示侧边栏
    final bool isDesktop = !Platform.isAndroid && !Platform.isIOS;
    
    return Scaffold(
      body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
      bottomNavigationBar: isDesktop ? null : _buildBottomNavigationBar(),
    );
  }

  // 修改：将原 _buildDesktopLayout 重命名并添加 GitHub 按钮
  Widget _buildDesktopLayout() {
    return Row(
      children: <Widget>[
        NavigationRail(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (int index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          labelType: NavigationRailLabelType.all,
          // 使用 trailing 属性在导航栏底部添加自定义小部件
          trailing: Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: IconButton(
                  icon: const Icon(Icons.star_border), // 使用一个代码相关的图标代表GitHub
                  tooltip: 'GitHub 仓库', // 鼠标悬停时显示提示
                  onPressed: _launchGitHubUrl, // 点击时调用已有的方法
                ),
              ),
            ),
          ),
          destinations: _navigationItems.map((item) {
            return NavigationRailDestination(
              icon: item.icon,
              selectedIcon: item.selectedIcon,
              label: Text(item.label),
            );
          }).toList(),
        ),
        const VerticalDivider(thickness: 1, width: 0.8),
        Expanded(
          child: _pages[_selectedIndex],
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return _pages[_selectedIndex];
  }

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (int index) {
        setState(() {
          _selectedIndex = index;
        });
      },
      type: BottomNavigationBarType.fixed,
      items: _navigationItems.map((item) {
        return BottomNavigationBarItem(
          icon: item.icon,
          activeIcon: item.selectedIcon,
          label: item.label,
        );
      }).toList(),
    );
  }
}

class NavigationItem {
  final Icon icon;
  final Icon selectedIcon;
  final String label;

  const NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}