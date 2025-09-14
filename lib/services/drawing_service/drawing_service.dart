// lib/services/drawing_service/drawing_service.dart

import 'package:http/http.dart' as http;

import '../../models/api_model.dart';
import 'drawing_platform.dart';
import 'platforms/comfyui_platform.dart';
import 'platforms/dashscope_platform.dart'; // 新增
import 'platforms/google_drawing_platform.dart'; // 新增
import 'platforms/kling_platform.dart';
import 'platforms/openai_platform.dart';
import 'platforms/volcengine_platform.dart';


/// 绘图服务，作为所有绘图平台的统一分发器。
class DrawingService {
  // 私有构造函数，用于实现单例模式。
  DrawingService._();
  // 静态单例实例，确保全局只有一个实例。
  static final DrawingService instance = DrawingService._();

  // 全局共享的 http 客户端，用于网络请求。
  final _client = http.Client();

  /// 根据传入的 apiConfig 配置，选择合适的绘图平台并生成图像。
  Future<List<String>?> generateImages({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    required ApiModel apiConfig,
    String? referenceImagePath, // 新增参数
  }) async {
    try {
      final DrawingPlatform platform;
      // 根据 API 配置中的 provider 类型，选择并实例化对应的平台实现。
      switch (apiConfig.provider) {
        case ApiProvider.custom: // 自定义 平台
          platform = OpenAiPlatform(client: _client, apiConfig: apiConfig);
          break;
        case ApiProvider.comfyui: // ComfyUI 平台
          platform = ComfyUiPlatform(client: _client, apiConfig: apiConfig);
          break;
        case ApiProvider.volcengine: // 火山引擎平台
          platform = VolcenginePlatform(client: _client, apiConfig: apiConfig);
          break;
        case ApiProvider.google: // Google 平台
          platform = GoogleDrawingPlatform(client: _client, apiConfig: apiConfig);
          break;
        case ApiProvider.dashscope: // 阿里通义千问平台
          platform = DashscopePlatform(client: _client, apiConfig: apiConfig);
          break;
        case ApiProvider.kling: // Kling 平台
          platform = KlingPlatform(client: _client, apiConfig: apiConfig);
          break;
        default:
          throw UnimplementedError('[DrawingService] ❌ 绘图平台 "${apiConfig.provider.name}" 尚未实现。');
      }

      // 调用所选平台的 generate 方法来生成图像。
      return await platform.generate(
        positivePrompt: positivePrompt,
        negativePrompt: negativePrompt,
        saveDir: saveDir,
        count: count,
        width: width,
        height: height,
        referenceImagePath: referenceImagePath, // 传递参数
      );
    } catch (e, st) {
      // 捕获并打印任何在生成过程中发生的错误。
      print('[DrawingService] ❌ 生成图像时发生错误 "${apiConfig.provider.name}": $e\n$st');
      return null;
    }
  }
}