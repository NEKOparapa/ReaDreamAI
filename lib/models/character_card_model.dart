// lib/models/character_card_model.dart


/// 角色设定卡片模型
class CharacterCard {
  final String id;
  final String name; // 卡片名
  final String characterName; // 角色名, 用于在小说文本中匹配
  final String identity; // 身份
  final String appearance; // 外貌
  final String clothing; // 服装
  final String personality; // 性格 (新增字段)
  final String status; // 状态 (新增字段)
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
    this.personality = '', // 新增字段
    this.status = '', // 新增字段
    this.other = '',
    this.referenceImageUrl,
    this.referenceImagePath,
    this.isSystemPreset = false,
  });

  // 工厂构造函数：用于从JSON创建实例
  factory CharacterCard.fromJson(Map<String, dynamic> json) {
    return CharacterCard(
      id: json['id'],
      name: json['name'],
      characterName: json['characterName'] ?? '',
      identity: json['identity'] ?? '',
      appearance: json['appearance'] ?? '',
      clothing: json['clothing'] ?? '',
      personality: json['personality'] ?? '', // 新增字段
      status: json['status'] ?? '',           // 新增字段
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
      'personality': personality, // 新增字段
      'status': status,           // 新增字段
      'other': other,
      'referenceImageUrl': referenceImageUrl,
      'referenceImagePath': referenceImagePath,
      'isSystemPreset': isSystemPreset,
    };
  }
}