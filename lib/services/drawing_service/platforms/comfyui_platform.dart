// lib/services/drawing_service/platforms/comfyui_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../models/api_model.dart';
import '../../../base/config_service.dart';
import '../../../base/default_configs.dart';
import '../drawing_platform.dart';

/// ComfyUI 平台的具体实现。
class ComfyUiPlatform implements DrawingPlatform {
  final http.Client client;
  // final ApiModel apiConfig; // <--- 移除成员变量
  final ConfigService _configService = ConfigService();

  // 构造函数不再接收 apiConfig
  ComfyUiPlatform({required this.client});

  @override
  Future<List<String>?> generate({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    required ApiModel apiConfig, // <--- apiConfig 作为参数传入
    String? referenceImagePath,
  }) async {
    /// ComfyUI 绘图调用的主要流程
    
    // 1. 准备工作流（Workflow），根据用户输入修改 JSON 模板。
    final workflow = await _prepareWorkflow(positivePrompt, negativePrompt, count, width, height);
    if (workflow == null) return null;

    // 2. 生成一个唯一的客户端 ID，用于 WebSocket 连接。
    final clientId = const Uuid().v4();
    // 3. 将工作流提交到 ComfyUI 的任务队列中，并获取任务 ID。
    final promptId = await _queuePrompt(workflow, clientId, apiConfig); 
    if (promptId == null) return null;

    // 4. 通过 WebSocket 等待任务执行完成。
    final success = await _waitForCompletion(promptId, clientId, apiConfig); 
    if (!success) return null;

    // 5. 任务完成后，通过 API 获取任务的详细历史记录。
    final history = await _getHistory(promptId, apiConfig); 
    if (history == null) return null;

    // 6. 从历史记录中解析出图像信息，并下载到本地。
    return await _downloadImagesFromHistory(history, saveDir, apiConfig); 
  }

  /// 准备 ComfyUI 工作流。
  Future<Map<String, dynamic>?> _prepareWorkflow(String positive, String negative, int count, int width, int height) async {
    // 从配置中获取用户选择的工作流类型。
    final workflowType = _configService.getSetting<String>('comfyui_workflow_type', appDefaultConfigs['comfyui_workflow_type']);
    String workflowPath;
    bool isAsset = true;

    // 根据工作流类型确定工作流文件的路径。
    switch (workflowType) {
      case 'WAI+illustrious的API工作流':
        workflowPath = 'assets/comfyui/WAI+illustrious的API工作流.json';
        break;
      case 'WAI+NoobAI的API工作流':
        workflowPath = 'assets/comfyui/WAI+NoobAI的API工作流.json';
        break;
      case 'WAI+Pony的API工作流':
        workflowPath = 'assets/comfyui/WAI+Pony的API工作流.json';
        break;
      case '自定义工作流':
        workflowPath = _configService.getSetting<String>('comfyui_custom_workflow_path', '');
        if (workflowPath.isEmpty) {
          throw Exception('未设置自定义ComfyUI工作流路径。');
        }
        isAsset = false; // 自定义工作流来自文件系统，而不是应用内资源。
        break;
      default:
        // 默认回退到一个基础工作流。
        workflowPath = 'assets/comfyui/WAI+illustrious_API.json';
    }

    try {
      // 根据路径来源（应用资源或文件系统）加载工作流文件内容。
      String jsonString;
      if (isAsset) {
        jsonString = await rootBundle.loadString(workflowPath);
      } else {
        final file = File(workflowPath);
        if (!await file.exists()) {
          throw Exception('自定义工作流文件未找到: $workflowPath');
        }
        jsonString = await file.readAsString();
      }

      // 解析 JSON 字符串为 Dart Map 对象。
      final workflow = jsonDecode(jsonString) as Map<String, dynamic>;

      // 从配置服务获取需要修改的节点 ID 和字段名。
      final positiveNodeId = _configService.getSetting<String>('comfyui_positive_prompt_node_id', appDefaultConfigs['comfyui_positive_prompt_node_id']);
      final positiveField = _configService.getSetting<String>('comfyui_positive_prompt_field', appDefaultConfigs['comfyui_positive_prompt_field']);
      final negativeNodeId = _configService.getSetting<String>('comfyui_negative_prompt_node_id', appDefaultConfigs['comfyui_negative_prompt_node_id']);
      final negativeField = _configService.getSetting<String>('comfyui_negative_prompt_field', appDefaultConfigs['comfyui_negative_prompt_field']);
      final latentNodeId = _configService.getSetting<String>('comfyui_batch_size_node_id', appDefaultConfigs['comfyui_batch_size_node_id']);
      final batchSizeField = _configService.getSetting<String>('comfyui_batch_size_field', appDefaultConfigs['comfyui_batch_size_field']);
      final widthField = _configService.getSetting<String>('comfyui_latent_width_field', appDefaultConfigs['comfyui_latent_width_field']);
      final heightField = _configService.getSetting<String>('comfyui_latent_height_field', appDefaultConfigs['comfyui_latent_height_field']);

      // 在工作流中找到对应的节点并更新其输入值。
      workflow[positiveNodeId]['inputs'][positiveField] = positive;
      workflow[negativeNodeId]['inputs'][negativeField] = negative;
      workflow[latentNodeId]['inputs'][batchSizeField] = count;
      workflow[latentNodeId]['inputs'][widthField] = width;
      workflow[latentNodeId]['inputs'][heightField] = height;

      // 返回修改后的工作流。
      return workflow;
    } catch (e) {
      print('加载或解析工作流文件时出错: $workflowPath');
      throw Exception('ComfyUI 工作流文件加载或解析失败于 $workflowPath: $e');
    }
  }

  /// 将准备好的工作流提交到 ComfyUI 的任务队列。
  Future<String?> _queuePrompt(Map<String, dynamic> workflow, String clientId, ApiModel apiConfig) async {
    print('[ComfyUI] 🚀 正在提交工作流...');
    // 构建提交工作流的 API 地址。
    final uri = Uri.parse('${apiConfig.url}/prompt');

    // 发送 POST 请求。
    final response = await client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'prompt': workflow, 'client_id': clientId}),
    );

    // 检查响应状态码。
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final promptId = data['prompt_id'] as String;
      print('[ComfyUI] ✅ 工作流提交成功，任务 ID: $promptId');
      return promptId;
    } else {
      print('[ComfyUI] ❌ 工作流提交失败: ${response.statusCode} ${response.body}');
      return null;
    }
  }

  /// 通过 WebSocket 等待任务完成。
  Future<bool> _waitForCompletion(String promptId, String clientId, ApiModel apiConfig) async {
    final completer = Completer<bool>();
    // 将 http/https 协议替换为 ws/wss 来建立 WebSocket 连接。
    final wsUri = Uri.parse(apiConfig.url.replaceFirst('http', 'ws') + '/ws?clientId=$clientId');
    final channel = WebSocketChannel.connect(wsUri);

    print('[ComfyUI] ⏳ 正在建立 WebSocket 连接并等待任务完成...');

    var sub = channel.stream.listen(
      (message) async {
        if (message is String) {
          final data = jsonDecode(message);
          final type = data['type'] as String;
          final eventData = data['data'];

          // 确保只处理当前任务相关的事件。
          if (eventData != null && eventData['prompt_id'] != null && eventData['prompt_id'] != promptId) {
            return;
          }
          
          // 根据事件类型进行处理。
          switch (type) {
            case 'executing':
              // 当 node 为 null 时，表示整个工作流执行完毕。
              if (eventData['node'] == null) {
                if (!completer.isCompleted) completer.complete(true);
              }
              break;
            case 'execution_cached':
              // 表示某些节点使用了缓存，流程继续。
              break;
            case 'execution_error':
              print('[ComfyUI] ❌ 任务执行出错: $eventData');
              if (!completer.isCompleted) completer.complete(false);
              break;
            case 'progress':
              // 打印任务进度。
              // final progressData = eventData;
              // print('[ComfyUI] 任务进度: ${progressData['value']}/${progressData['max']}');
              break;
          }
        } 
      },
      onError: (error, stackTrace) {
        print('[ComfyUI] ❌ WebSocket 连接出错: $error');
        print('[ComfyUI] ❌ 堆栈跟踪: $stackTrace');
        if (!completer.isCompleted) completer.complete(false);
      },
      onDone: () {
        print('[ComfyUI] WebSocket 连接已关闭。');
        if (!completer.isCompleted) {
          // 有时连接会提前关闭，但任务可能已完成，我们假设成功，后续通过 history API 验证。
          print('[ComfyUI] WebSocket 在没有明确完成信号的情况下关闭。假设任务可能已完成，将通过历史记录 API 进行验证。');
          completer.complete(true);
        }
      },
    );

    // 设置一个超时，防止无限等待。
    Future.delayed(const Duration(minutes: 5), () {
      if (!completer.isCompleted) {
        print('[ComfyUI] ❌ 等待任务完成超时。');
        sub.cancel();
        channel.sink.close();
        completer.complete(false);
      }
    });

    final success = await completer.future;
    // 清理资源。
    await sub.cancel();
    await channel.sink.close();
    return success;
  }

  /// 获取指定任务 ID 的历史记录。
  Future<Map<String, dynamic>?> _getHistory(String promptId, ApiModel apiConfig) async {
    print('[ComfyUI] 正在获取任务历史记录，ID: $promptId');
    final uri = Uri.parse('${apiConfig.url}/history/$promptId');
    final response = await client.get(uri);
    if (response.statusCode == 200) {
      final history = jsonDecode(response.body);
      // 历史记录的 key 就是 promptId。
      return history[promptId] as Map<String, dynamic>?;
    }
    print('[ComfyUI] ❌ 获取历史记录失败: ${response.statusCode}');
    return null;
  }

  /// 从历史记录中解析并下载所有生成的图像。
  Future<List<String>?> _downloadImagesFromHistory(Map<String, dynamic> history, String saveDir, ApiModel apiConfig) async {
    final List<Future<String?>> downloadFutures = [];
    final outputs = history['outputs'] as Map<String, dynamic>;

    // 遍历历史记录中的所有输出节点。
    for (final nodeOutput in outputs.values) {
      // 如果节点输出包含 'images' 字段，则处理其中的图像信息。
      if ((nodeOutput as Map).containsKey('images')) {
        for (final imageInfo in nodeOutput['images']) {
          final filename = imageInfo['filename'] as String;
          final subfolder = imageInfo['subfolder'] as String;
          final type = imageInfo['type'] as String;
          // 为每张图片创建一个下载任务。
          downloadFutures.add(_downloadImage(filename, subfolder, type, saveDir,apiConfig));
        }
      }
    }

    if (downloadFutures.isEmpty) {
      print('[ComfyUI] ❓ 在历史记录输出中未找到图像。');
      return null;
    }

    // 并行等待所有下载任务完成，并过滤掉失败的结果(null)。
    final imagePaths = (await Future.wait(downloadFutures)).whereType<String>().toList();
    return imagePaths.isNotEmpty ? imagePaths : null;
  }

  /// 下载单张图片。
  Future<String?> _downloadImage(String filename, String subfolder, String type, String saveDir, ApiModel apiConfig) async {
    // 构建 ComfyUI 的图像查看/下载 URL。
    final uri = Uri.parse('${apiConfig.url}/view?filename=$filename&subfolder=$subfolder&type=$type');
    try {
      print('[ComfyUI] 📥 正在下载图片: $filename');
      final response = await client.get(uri).timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        // 确保保存目录存在。
        await Directory(saveDir).create(recursive: true);
        final imagePath = p.join(saveDir, filename);
        // 将下载的二进制数据写入文件。
        await File(imagePath).writeAsBytes(response.bodyBytes);
        print('[ComfyUI] ✅ 图片已保存到: $imagePath');
        return imagePath;
      } else {
        print('[ComfyUI] ❌ 下载图片 $filename 失败。状态码: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('[ComfyUI] ❌ 下载图片 $filename 时出错: $e');
      return null;
    }
  }
}