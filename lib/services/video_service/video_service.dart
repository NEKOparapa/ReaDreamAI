// lib/services/video_service/video_service.dart

import 'package:http/http.dart' as http;

import '../../models/api_model.dart';
import 'platforms/bailian_platform.dart';
import 'platforms/volcengine_platform.dart';
import 'video_platform.dart';

/// 视频服务，作为所有视频平台的统一分发器。
class VideoService {
  static final VideoService instance = VideoService._();

  late final http.Client _client;
  late final Map<ApiProvider, VideoPlatform> _platforms;
  
  VideoService._() {
    _client = http.Client();
    _platforms = {
      ApiProvider.bailian: BailianPlatform(client: _client),
      ApiProvider.volcengine: VolcenginePlatform(client: _client),
      // 未来可以添加更多平台
    };
  }
  
  /// 根据传入的 apiConfig 配置，选择合适的视频平台并生成视频。
  Future<List<String>?> generateVideo({
    required String positivePrompt,
    required String saveDir,
    required int count,
    required String resolution,
    String? referenceImagePath,
    required ApiModel apiConfig,
  }) async {
    try {
      // 通过 Map 查找平台实例
      final platform = _platforms[apiConfig.provider];

      if (platform == null) {
        throw UnimplementedError('[VideoService] ❌ 视频平台 "${apiConfig.provider.name}" 尚未实现。');
      }

      // 将 apiConfig 作为参数传递给 generate 方法
      return await platform.generate(
        positivePrompt: positivePrompt,
        saveDir: saveDir,
        count: count,
        resolution: resolution,
        referenceImagePath: referenceImagePath,
        apiConfig: apiConfig, // 传递 apiConfig
      );
    } catch (e, st) {
      print('[VideoService] ❌ 生成视频时发生错误 "${apiConfig.provider.name}": $e\n$st');
      // 将底层异常重新抛出，以便上层UI可以捕获并显示给用户
      rethrow;
    }
  }
}