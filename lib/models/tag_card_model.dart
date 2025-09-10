// lib/models/tag_card_model.dart


/// 通用标签卡片模型
class TagCard {
  final String id;
  final String name;
  final String content;
  final bool isSystemPreset;

  TagCard({
    required this.id,
    required this.name,
    required this.content,
    this.isSystemPreset = false,
  });

  // 工厂构造函数：用于从JSON创建实例
  factory TagCard.fromJson(Map<String, dynamic> json) {
    return TagCard(
      id: json['id'],
      name: json['name'],
      content: json['content'],
      isSystemPreset: json['isSystemPreset'] ?? false,
    );
  }

  // 方法：将实例转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'content': content,
      'isSystemPreset': isSystemPreset,
    };
  }
}