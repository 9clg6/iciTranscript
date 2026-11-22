// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session.local.model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SessionLocalModel _$SessionLocalModelFromJson(Map<String, dynamic> json) =>
    _SessionLocalModel(
      id: json['id'] as String,
      title: json['title'] as String,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
      status: json['status'] as String,
      calendarEventId: json['calendarEventId'] as String?,
      calendarEventTitle: json['calendarEventTitle'] as String?,
      attendees: json['attendees'] as String?,
    );

Map<String, dynamic> _$SessionLocalModelToJson(_SessionLocalModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'createdAt': instance.createdAt,
      'updatedAt': instance.updatedAt,
      'durationSeconds': instance.durationSeconds,
      'status': instance.status,
      'calendarEventId': instance.calendarEventId,
      'calendarEventTitle': instance.calendarEventTitle,
      'attendees': instance.attendees,
    };
