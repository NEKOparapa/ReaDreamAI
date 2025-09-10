// lib/ui/main/main_screen.dart

import 'package:flutter/material.dart';
import '../bookshelf/bookshelf_page.dart'; // '..' 代表上一级目录，所以我们从 ui/main/ 返回到 ui/，然后再进入
import '../api/api_management_page.dart';
import '../settings/settings_page.dart';
import '../tasks/task_management_page.dart';

// MainScreen 是应用的主界面，包含侧边导航栏和内容区域
// 它是一个有状态组件，允许用户在不同的页面之间切换
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  // 创建 MainScreen 的状态类
  // State 是一个泛型类，<> 中的类型参数指定了这个状态类
  // 在这里，_MainScreenState 是 MainScreen 的状态类
  // 它负责管理 MainScreen 的状态和构建 UI
  @override
  State<MainScreen> createState() => _MainScreenState(); // 类名前的下划线 _ 在 Dart 语言中表示私有（private）。这个类只能在当前文件中访问。
}


// State<MainScreen> 是以 MainScreen 为类型参数的状态类，<>是 Dart 语言中的泛型语法



// MainScreenState 是 MainScreen 的状态类，负责管理状态和构建 UI
class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0; // 当前选中的导航项索引

  // 定义一个列表，包含三个页面的 Widget，是 MainScreen 的内容区域
  final List<Widget> _pages = [
    const BookshelfPage(),       // 0: 书架页
    const TaskManagementPage(),  // 1: 任务管理页
    const ApiManagementPage(),   // 2: API管理页
    const SettingsPage(),        // 3: 设置页
  ];

  // build 方法是每当需要重新绘制 UI 时调用的
  @override
  Widget build(BuildContext context) {

    // Scaffold Widget是一个 Material Design 风格的布局结构
    return Scaffold(

      body: Row( // 使用 Row 布局，将子Widget全部水平排列
        children: <Widget>[

          // 侧边导航栏
          NavigationRail(

            selectedIndex: _selectedIndex, // 当前选中的索引,由 _selectedIndex 控制

            onDestinationSelected: (int index) { // 当用户选择一个导航项时调用,
    
              setState(() { // 当 setState() 被调用时，build 方法就会被执行。
                _selectedIndex = index; //改变 _selectedIndex 的值，然后更新UI状态
              });
            },

            labelType: NavigationRailLabelType.all, // 显示所有标签

            destinations: const <NavigationRailDestination>[ // 定义侧边导航栏的各个目的地

              NavigationRailDestination(
                icon: Icon(Icons.book_outlined),
                selectedIcon: Icon(Icons.book),
                label: Text('书架'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.task_alt_outlined),
                selectedIcon: Icon(Icons.task_alt),
                label: Text('任务'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.api_outlined),
                selectedIcon: Icon(Icons.api),
                label: Text('接口'),
              ),
              
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('设置'),
              ),
            ],
          ),

          // 分隔线
          const VerticalDivider(thickness: 1, width: 1), 

          // 内容区域
          Expanded( 
            child: _pages[_selectedIndex],
          ),
        ],
      ),
    );
  }
}
