// lib/services/drawing_service/drawing_platform.dart

/// 定义一个抽象的绘图平台接口，所有具体的绘图平台都需要实现这个接口。
abstract class DrawingPlatform {
  /// 生成图像的核心方法。
  ///
  /// [positivePrompt]: 正向提示词。
  /// [negativePrompt]: 反向提示词。
  /// [saveDir]: 图像保存目录。
  /// [count]: 生成图像的数量。
  /// [width]: 图像宽度。
  /// [height]: 图像高度。
  /// [referenceImagePath]: (可选) 参考图的路径或URL，用于图生图。
  /// 返回一个包含生成图像本地路径的列表。
  Future<List<String>?> generate({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    String? referenceImagePath,
  });
}