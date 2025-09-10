// lib/models/character_card_model.dart


/// 角色设定卡片模型
class CharacterCard {
  final String id;
  final String name;
  final String characterName; // 新增：角色的实际名字
  final String identity;
  final String appearance;
  final String clothing;
  final String other;
  final String? referenceImageUrl; // 新增：参考图 URL
  final String? referenceImagePath; // 新增：参考图本地路径
  final bool isSystemPreset;

  CharacterCard({
    required this.id,
    required this.name,
    this.characterName = '', // 新增
    this.identity = '',
    this.appearance = '',
    this.clothing = '',
    this.other = '',
    this.referenceImageUrl, // 新增
    this.referenceImagePath, // 新增
    this.isSystemPreset = false,
  });

  // 工厂构造函数：用于从JSON创建实例
  factory CharacterCard.fromJson(Map<String, dynamic> json) {
    return CharacterCard(
      id: json['id'],
      name: json['name'],
      characterName: json['characterName'] ?? '', // 新增
      identity: json['identity'] ?? '',
      appearance: json['appearance'] ?? '',
      clothing: json['clothing'] ?? '',
      other: json['other'] ?? '',
      referenceImageUrl: json['referenceImageUrl'], // 新增
      referenceImagePath: json['referenceImagePath'], // 新增
      isSystemPreset: json['isSystemPreset'] ?? false,
    );
  }

  // 方法：将实例转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'characterName': characterName, // 新增
      'identity': identity,
      'appearance': appearance,
      'clothing': clothing,
      'other': other,
      'referenceImageUrl': referenceImageUrl, // 新增
      'referenceImagePath': referenceImagePath, // 新增
      'isSystemPreset': isSystemPreset,
    };
  }
}