// lib/models/character_card_model.dart

import 'package:uuid/uuid.dart';


/// 角色设定卡片模型
class CharacterCard {
  final String id;
  final String name; // 卡片名
  final String characterName; // 角色名, 用于在小说文本中匹配
  final String identity; // 身份
  final String appearance; // 外貌
  final String clothing; // 服装
  final String personality; // 性格
  final String status; // 状态
  final String other; // 其他
  final String? referenceImageUrl; // 网络参考图
  final String? referenceImagePath; // 本地参考图
  final bool isSystemPreset;

  CharacterCard({
    required this.id,
    required this.name,
    this.characterName = '',
    this.identity = '',
    this.appearance = '',
    this.clothing = '',
    this.personality = '',
    this.status = '',
    this.other = '',
    this.referenceImageUrl,
    this.referenceImagePath,
    this.isSystemPreset = false,
  });

  // 工厂构造函数：用于从JSON创建实例
  factory CharacterCard.fromJson(Map<String, dynamic> json) {
    return CharacterCard(
      id: json['id'] ?? const Uuid().v4(),  // 如果 id 缺失，生成一个新的 UUID
      name: json['name'] ?? '未命名角色',    // 如果 name 缺失，提供默认名称
      characterName: json['characterName'] ?? '',
      identity: json['identity'] ?? '',
      appearance: json['appearance'] ?? '',
      clothing: json['clothing'] ?? '',
      personality: json['personality'] ?? '',
      status: json['status'] ?? '',          
      other: json['other'] ?? '',
      referenceImageUrl: json['referenceImageUrl'],
      referenceImagePath: json['referenceImagePath'],
      isSystemPreset: json['isSystemPreset'] ?? false,
    );
  }

  // 方法：将实例转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'characterName': characterName,
      'identity': identity,
      'appearance': appearance,
      'clothing': clothing,
      'personality': personality,
      'status': status,          
      'other': other,
      'referenceImageUrl': referenceImageUrl,
      'referenceImagePath': referenceImagePath,
      'isSystemPreset': isSystemPreset,
    };
  }
}