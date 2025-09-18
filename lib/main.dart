import 'package:flutter/material.dart';
import 'ui/main/main_screen.dart'; // 导入ui/main/ 目录下的文件
import 'base/config_service.dart'; // 导入配置服务
import 'services/task_manager/task_manager_service.dart';

void main() async { 
  // 确保 Flutter 绑定已初始化，这在 main 成为 async 时是必需的
  WidgetsFlutterBinding.ensureInitialized();
  
  // 在运行App之前，初始化配置服务,处理配置文件夹和文件的检查与创建
  await ConfigService().init();

  // 初始化任务管理器服务
  await TaskManagerService.instance.init();

  // 根据配置文件，在应用启动时就设置好代理
  ConfigService().applyHttpProxy();
  

  // 运行应用程序
  runApp(const MyApp()); 
}


class MyApp extends StatelessWidget { // StatelessWidget是一个无状态的静态的不变的组件
  const MyApp({super.key}); // super.key 是一个可选参数，用于标识 Widget 的唯一性，帮助 Flutter 更高效地识别和更新 Widget。


//StatelessWidget (无状态组件): 像一张照片。一旦创建，它就不会再改变。它只负责根据传入的参数来显示信息。例如，一个显示固定文本的标签。
//StatefulWidget (有状态组件): 像一个交互式的白板。它的内容可以根据用户的操作或数据的变化而改变。例如，一个复选框（有选中/未选中两种状态）

  @override  // 表示这个 build 方法是重写了父类 StatelessWidget 中的同名方法。
  Widget build(BuildContext context) {    // 重写 build 方法，每当 Flutter 框架认为需要绘制这个 Widget 时，就会调用它的 build 方法。

    return MaterialApp(  // MaterialApp 是一个方便的 Widget，它封装了应用通常需要的一些功能
      title: 'AiReaa', // 应用的标题
      theme: ThemeData( // 应用的主题数据
        primarySwatch: Colors.indigo, // 设置应用的主色调为靛蓝色
        visualDensity: VisualDensity.adaptivePlatformDensity, // 适应不同平台的视觉密度
      ),
      debugShowCheckedModeBanner: false, // 禁用调试模式下的右上角的 Debug Banner
      home: const MainScreen(), // 设置应用的首页为 MainScreen Widget，指向导入的 main_screen.dart
    );

  }
}

//const：编译时常量，值必须在写代码的时候就“写死”。
//final：运行时常量，值可以在程序跑起来后确定，但只能确定一次