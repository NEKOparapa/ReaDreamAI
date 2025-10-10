// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'character_profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CharacterProfile _$CharacterProfileFromJson(Map<String, dynamic> json) =>
    CharacterProfile(
      name: json['name'] as String,
      identity: json['identity'] as String,
      appearance: json['appearance'] as String,
      personality: json['personality'] as String,
      costume: json['costume'] as String,
      status: json['status'] as String,
      notes: json['notes'] as String,
    );

Map<String, dynamic> _$CharacterProfileToJson(CharacterProfile instance) =>
    <String, dynamic>{
      'name': instance.name,
      'identity': instance.identity,
      'appearance': instance.appearance,
      'personality': instance.personality,
      'costume': instance.costume,
      'status': instance.status,
      'notes': instance.notes,
    };
