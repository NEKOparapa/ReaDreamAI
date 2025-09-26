// lib/ui/main/main_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
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

  // 导航项数据
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

  @override
  Widget build(BuildContext context) {
    // 检查是否运行在安卓设备上
    final bool isAndroid = Platform.isAndroid;
    
    return Scaffold(
      body: isAndroid ? _buildAndroidLayout() : _buildDesktopLayout(),
      bottomNavigationBar: isAndroid ? _buildBottomNavigationBar() : null,
    );
  }

  // 构建桌面端布局（侧边导航栏）
  Widget _buildDesktopLayout() {
    return Row(
      children: <Widget>[
        // 侧边导航栏
        NavigationRail(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (int index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          labelType: NavigationRailLabelType.all,
          destinations: _navigationItems.map((item) {
            return NavigationRailDestination(
              icon: item.icon,
              selectedIcon: item.selectedIcon,
              label: Text(item.label),
            );
          }).toList(),
        ),
        // 分隔线
        const VerticalDivider(thickness: 1, width: 0.8),
        // 内容区域
        Expanded(
          child: _pages[_selectedIndex],
        ),
      ],
    );
  }

  // 构建安卓端布局（底部导航栏）
  Widget _buildAndroidLayout() {
    return _pages[_selectedIndex];
  }

  // 构建底部导航栏（安卓端）
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

// 导航项数据类
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
