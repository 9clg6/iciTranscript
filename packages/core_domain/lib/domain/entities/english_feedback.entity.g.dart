// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'english_feedback.entity.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_EnglishCorrectionEntity _$EnglishCorrectionEntityFromJson(
  Map<String, dynamic> json,
) => _EnglishCorrectionEntity(
  original: json['original'] as String,
  corrected: json['corrected'] as String,
  category: json['category'] as String,
  explanation: json['explanation'] as String,
);

Map<String, dynamic> _$EnglishCorrectionEntityToJson(
  _EnglishCorrectionEntity instance,
) => <String, dynamic>{
  'original': instance.original,
  'corrected': instance.corrected,
  'category': instance.category,
  'explanation': instance.explanation,
};

_EnglishFeedbackEntity _$EnglishFeedbackEntityFromJson(
  Map<String, dynamic> json,
) => _EnglishFeedbackEntity(
  corrections:
      (json['corrections'] as List<dynamic>?)
          ?.map(
            (e) => EnglishCorrectionEntity.fromJson(e as Map<String, dynamic>),
          )
          .toList() ??
      const <EnglishCorrectionEntity>[],
  overall: json['overall'] as String?,
);

Map<String, dynamic> _$EnglishFeedbackEntityToJson(
  _EnglishFeedbackEntity instance,
) => <String, dynamic>{
  'corrections': instance.corrections,
  'overall': instance.overall,
};
