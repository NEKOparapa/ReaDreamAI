/// lib/main.dart

import 'package:flutter/material.dart';
import 'ui/main/main_screen.dart'; // 导入ui/main/ 目录下的文件
import 'base/config_service.dart'; // 导入配置服务
import 'services/task_manager/task_manager_service.dart'; // 导入任务管理器服务
import 'base/log/log_service.dart'; // 导入日志服务

void main() async { 
  // 确保 Flutter 绑定已初始化，这在 main 成为 async 时是必需的
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化配置服务,处理配置文件夹和文件的检查与创建
  await ConfigService().init();

  // 初始化日志服务 (在ConfigService之后)
  await LogService.instance.init();

  // 初始化任务管理器服务
  await TaskManagerService.instance.init();

  // 根据配置文件，在应用启动时就设置好代理
  ConfigService().applyHttpProxy();
  
  LogService.instance.info("应用正在启动中...");
  // 运行应用程序
  runApp(const MyApp()); 
}


// 主题颜色定义
class AppColors {
  static const Color primaryColor = Color.fromARGB(255, 109, 126, 213);
  static const Color backgroundColor = Color(0xFFF5F5F5);
  static const Color secondaryColor = Color(0xFF03DAC6);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 定义亮色主题 (Light Theme)
    final lightTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryColor,  // 主题的种子颜色
        brightness: Brightness.light,  // 亮色主题
      ),
      useMaterial3: true,  // 启用 Material 3 设计规范
      visualDensity: VisualDensity.adaptivePlatformDensity,  // 适应不同平台的视觉密度
      fontFamily: 'NotoSansSC', // 设置全局字体，使用定义的字体名字
    );

    // 定义深色主题 (Dark Theme)
    final darkTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryColor,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamily: 'NotoSansSC',
    );

    return MaterialApp(
      title: 'ReaDreamAI',
      theme: lightTheme,
      //darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const MainScreen(),
    );
  }
}
