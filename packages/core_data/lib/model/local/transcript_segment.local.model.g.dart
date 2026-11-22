// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcript_segment.local.model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TranscriptSegmentLocalModel _$TranscriptSegmentLocalModelFromJson(
  Map<String, dynamic> json,
) => _TranscriptSegmentLocalModel(
  id: json['id'] as String,
  sessionId: json['sessionId'] as String,
  source: json['source'] as String,
  text: json['text'] as String,
  timestampMs: (json['timestampMs'] as num).toInt(),
  createdAt: json['createdAt'] as String,
  isPartial: json['isPartial'] as bool? ?? false,
);

Map<String, dynamic> _$TranscriptSegmentLocalModelToJson(
  _TranscriptSegmentLocalModel instance,
) => <String, dynamic>{
  'id': instance.id,
  'sessionId': instance.sessionId,
  'source': instance.source,
  'text': instance.text,
  'timestampMs': instance.timestampMs,
  'createdAt': instance.createdAt,
  'isPartial': instance.isPartial,
};
