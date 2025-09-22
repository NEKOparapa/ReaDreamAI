// lib/services/video_service/video_service.dart

import 'package:http/http.dart' as http;
import '../../base/log/log_service.dart';
import '../../models/api_model.dart';
import 'platforms/bailian_platform.dart';
import 'platforms/volcengine_platform.dart';
import 'video_platform.dart';

/// 视频服务
class VideoService {
  // 单例实例
  static final VideoService instance = VideoService._();

  // HTTP 客户端，用于网络请求
  late final http.Client _client;
  // 存储所有已实现的视频平台实例
  late final Map<ApiProvider, VideoPlatform> _platforms;
  
  // 私有构造函数，初始化客户端和平台列表
  VideoService._() {
    _client = http.Client();
    _platforms = {
      // 注册阿里百炼平台
      ApiProvider.bailian: BailianPlatform(client: _client),
      // 注册火山方舟平台
      ApiProvider.volcengine: VolcenginePlatform(client: _client),
      // 未来可以在这里添加更多平台
    };
  }
  
  /// 根据传入的 API 配置，选择合适的平台并生成视频。
  Future<List<String>?> generateVideo({
    required String positivePrompt,    // 正向提示词
    required String saveDir,           // 视频保存目录
    required int count,               // 生成数量 (目前大多平台只支持1)
    required String resolution,        // 分辨率
    required int duration,            // 视频时长(秒)
    String? referenceImagePath,       // (可选) 参考图路径，用于图生视频
    required ApiModel apiConfig,      // API 配置信息
  }) async {
    try {
      // 根据 apiConfig 中的 provider 类型，从 Map 中查找对应的平台实例
      final platform = _platforms[apiConfig.provider];

      // 如果未找到对应的平台实现，则抛出错误
      if (platform == null) {
        throw UnimplementedError('视频平台 "${apiConfig.provider.name}" 尚未实现。');
      }

      // 调用平台实例的 generate 方法执行生成任务
      return await platform.generate(
        positivePrompt: positivePrompt,
        saveDir: saveDir,
        count: count,
        resolution: resolution,
        duration: duration, 
        referenceImagePath: referenceImagePath,
        apiConfig: apiConfig, // 传递完整的 API 配置
      );
    } catch (e, st) {
      // 捕获生成过程中的任何异常，并使用日志系统记录
      LogService.instance.error(
        '[VideoService] ❌ 生成视频时发生错误 "${apiConfig.provider.name}"',
        e,
        st
      );
      // 将异常重新抛出，以便上层UI可以捕获并向用户显示错误信息
      rethrow;
    }
  }
}