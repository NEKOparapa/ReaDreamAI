// lib/models/character_profile.dart
import 'package:json_annotation/json_annotation.dart';

part 'character_profile.g.dart';

@JsonSerializable()
class CharacterProfile {
  String name;
  String identity;
  String appearance;
  String personality;
  String costume;
  String status;
  String notes;

  CharacterProfile({
    required this.name,
    required this.identity,
    required this.appearance,
    required this.personality,
    required this.costume,
    required this.status,
    required this.notes,
  });

  factory CharacterProfile.fromJson(Map<String, dynamic> json) => _$CharacterProfileFromJson(json);
  Map<String, dynamic> toJson() => _$CharacterProfileToJson(this);
}