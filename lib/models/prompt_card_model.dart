// lib/models/prompt_card_model.dart

import 'package:uuid/uuid.dart';

/// 提示词卡片模型
class PromptCard {
  String id;
  String name;
  String content;
  final bool isSystemPreset;

  PromptCard({
    String? id,
    required this.name,
    required this.content,
    this.isSystemPreset = false,
  }) : id = id ?? const Uuid().v4();

  /// 从JSON反序列化
  factory PromptCard.fromJson(Map<String, dynamic> json) {
    return PromptCard(
      id: json['id'],
      name: json['name'],
      content: json['content'],
      isSystemPreset: json['isSystemPreset'] ?? false,
    );
  }

  /// 序列化为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'content': content,
      'isSystemPreset': isSystemPreset,
    };
  }
}