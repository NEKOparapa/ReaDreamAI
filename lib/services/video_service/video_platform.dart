// lib/services/video_service/video_platform.dart

import '../../models/api_model.dart';

/// 定义一个抽象的视频生成平台接口，所有具体的视频平台都需要实现这个接口。
abstract class VideoPlatform {
  /// 生成视频的核心方法。
  ///
  /// [positivePrompt]: 正向提示词。
  /// [saveDir]: 视频保存目录。
  /// [count]: 生成视频的数量 (当前固定为1)。
  /// [resolution]: 视频分辨率 (例如 '720p')。
  /// [referenceImagePath]: (可选) 参考图的本地路径或URL，用于图生视频。
  /// [apiConfig]: 包含API密钥、模型等信息的配置对象，在调用时传入。
  /// 返回一个包含生成视频本地路径的列表。
  Future<List<String>?> generate({
    required String positivePrompt,
    required String saveDir,
    required int count,
    required String resolution,
    String? referenceImagePath,
    required ApiModel apiConfig,
  });
}