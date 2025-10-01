// lib/models/style_card_model.dart

/// 绘画风格卡片模型
class StyleCard {
  final String id;
  final String name;
  final String content;
  final bool isSystemPreset;
  final String? exampleImage; 

  StyleCard({
    required this.id,
    required this.name,
    required this.content,
    this.isSystemPreset = false,
    this.exampleImage,
  });

  // 工厂构造函数：用于从JSON创建实例
  factory StyleCard.fromJson(Map<String, dynamic> json) {
    // 兼容旧的数组格式
    String? exampleImage;
    if (json['exampleImage'] != null) {
      exampleImage = json['exampleImage'] as String;
    } else if (json['exampleImages'] != null && (json['exampleImages'] as List).isNotEmpty) {
      // 从旧格式迁移：取第一张图片
      exampleImage = (json['exampleImages'] as List).first as String;
    }

    return StyleCard(
      id: json['id'],
      name: json['name'],
      content: json['content'],
      isSystemPreset: json['isSystemPreset'] ?? false,
      exampleImage: exampleImage,
    );
  }

  // 方法：将实例转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'content': content,
      'isSystemPreset': isSystemPreset,
      'exampleImage': exampleImage,
    };
  }

  // 复制并修改
  StyleCard copyWith({
    String? id,
    String? name,
    String? content,
    bool? isSystemPreset,
    String? exampleImage,
  }) {
    return StyleCard(
      id: id ?? this.id,
      name: name ?? this.name,
      content: content ?? this.content,
      isSystemPreset: isSystemPreset ?? this.isSystemPreset,
      exampleImage: exampleImage ?? this.exampleImage,
    );
  }
}
